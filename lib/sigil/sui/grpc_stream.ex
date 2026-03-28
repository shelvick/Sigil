defmodule Sigil.Sui.GrpcStream do
  @moduledoc """
  Streams Sui checkpoint events and broadcasts the filtered events over PubSub.
  """

  use GenServer

  require Logger

  alias Sigil.Repo
  alias Sigil.Sui.GrpcStream.{Codec, Connector, CursorStore}

  @default_endpoint "fullnode.testnet.sui.io:443"
  @default_pubsub Sigil.PubSub
  @default_topic "chain_events"
  @default_flush_interval_ms 30_000
  @default_flush_count 100
  @default_reconnect_base_ms 1_000
  @default_reconnect_max_ms 60_000
  @default_stream_id "grpc_main"

  @typedoc "Runtime state for a checkpoint stream instance."
  @type state() :: %{
          enabled?: boolean(),
          endpoint: String.t(),
          pubsub: atom() | module(),
          topic: String.t(),
          stream_id: String.t(),
          repo_module: module(),
          sandbox_owner: pid() | nil,
          cursor: non_neg_integer() | nil,
          last_flushed_cursor: non_neg_integer() | nil,
          checkpoints_since_flush: non_neg_integer(),
          stream_ref: reference() | pid() | term() | nil,
          reader_monitor_ref: reference() | nil,
          flush_timer_token: reference() | nil,
          flush_timer_handle: term() | nil,
          reconnect_timer_token: reference() | nil,
          reconnect_timer_handle: term() | nil,
          connect_fun: (String.t(), non_neg_integer() | nil -> {:ok, term()} | {:error, term()}),
          schedule_fun: (pid(), term(), non_neg_integer() -> term()),
          load_cursor_fun: (-> non_neg_integer() | nil),
          save_cursor_fun: (non_neg_integer() -> :ok | term()),
          event_filter_fun: (map() -> boolean()),
          flush_interval_ms: pos_integer(),
          flush_count: pos_integer(),
          reconnect_base_ms: pos_integer(),
          reconnect_max_ms: pos_integer(),
          reconnect_attempt: non_neg_integer()
        }

  @typedoc "Start option accepted by the checkpoint stream."
  @type option() ::
          {:enabled?, boolean()}
          | {:endpoint, String.t()}
          | {:pubsub, atom() | module()}
          | {:topic, String.t()}
          | {:stream_id, String.t()}
          | {:repo_module, module()}
          | {:sandbox_owner, pid()}
          | {:load_cursor_fun, (-> non_neg_integer() | nil)}
          | {:save_cursor_fun, (non_neg_integer() -> :ok | term())}
          | {:event_filter_fun, (map() -> boolean())}
          | {:flush_interval_ms, pos_integer()}
          | {:flush_count, pos_integer()}
          | {:reconnect_base_ms, pos_integer()}
          | {:reconnect_max_ms, pos_integer()}
          | {:connect_fun,
             (String.t(), non_neg_integer() | nil -> {:ok, term()} | {:error, term()})}
          | {:schedule_fun, (pid(), term(), non_neg_integer() -> term())}

  @type options() :: [option()]

  @doc "Returns a unique child spec so stream instances stay isolated in tests."
  @spec child_spec(options()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: {__MODULE__, System.unique_integer([:positive])},
      start: {__MODULE__, :start_link, [opts]},
      restart: :permanent,
      type: :worker
    }
  end

  @doc "Starts a checkpoint stream process."
  @spec start_link(options()) :: GenServer.on_start() | :ignore
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @impl true
  @doc false
  @spec init(options()) :: {:ok, state(), {:continue, :post_init}} | :ignore
  def init(opts) do
    enabled? =
      Keyword.get(opts, :enabled?, Application.get_env(:sigil, :start_grpc_stream, false))

    if enabled? do
      repo_module = Keyword.get(opts, :repo_module, Repo)
      sandbox_owner = Keyword.get(opts, :sandbox_owner)
      stream_id = Keyword.get(opts, :stream_id, @default_stream_id)

      load_cursor_fun =
        Keyword.get(opts, :load_cursor_fun, fn ->
          CursorStore.default_load_cursor(repo_module, stream_id)
        end)

      save_cursor_fun =
        Keyword.get(opts, :save_cursor_fun, fn cursor ->
          CursorStore.default_save_cursor(repo_module, stream_id, cursor)
        end)

      state = %{
        enabled?: true,
        endpoint: Keyword.get(opts, :endpoint, grpc_endpoint()),
        pubsub: Keyword.get(opts, :pubsub, @default_pubsub),
        topic: Keyword.get(opts, :topic, @default_topic),
        stream_id: stream_id,
        repo_module: repo_module,
        sandbox_owner: sandbox_owner,
        cursor: nil,
        last_flushed_cursor: nil,
        checkpoints_since_flush: 0,
        stream_ref: nil,
        reader_monitor_ref: nil,
        flush_timer_token: nil,
        flush_timer_handle: nil,
        reconnect_timer_token: nil,
        reconnect_timer_handle: nil,
        connect_fun: Keyword.get(opts, :connect_fun, Connector.default_connect_fun()),
        schedule_fun: Keyword.get(opts, :schedule_fun, &default_schedule/3),
        load_cursor_fun: load_cursor_fun,
        save_cursor_fun: save_cursor_fun,
        event_filter_fun: Keyword.get(opts, :event_filter_fun, &Codec.default_event_filter/1),
        flush_interval_ms: Keyword.get(opts, :flush_interval_ms, @default_flush_interval_ms),
        flush_count: Keyword.get(opts, :flush_count, @default_flush_count),
        reconnect_base_ms: Keyword.get(opts, :reconnect_base_ms, @default_reconnect_base_ms),
        reconnect_max_ms: Keyword.get(opts, :reconnect_max_ms, @default_reconnect_max_ms),
        reconnect_attempt: 0
      }

      {:ok, state, {:continue, :post_init}}
    else
      :ignore
    end
  end

  @impl true
  @doc false
  @spec handle_continue(:post_init, state()) :: {:noreply, state()}
  def handle_continue(:post_init, state) do
    :ok = CursorStore.maybe_allow_sandbox_owner(state.repo_module, state.sandbox_owner)

    cursor = state.load_cursor_fun.()

    next_state =
      state
      |> Map.put(:cursor, cursor)
      |> Map.put(:last_flushed_cursor, cursor)
      |> connect_and_schedule_flush()

    {:noreply, next_state}
  end

  @impl true
  @doc false
  @spec handle_info(term(), state()) :: {:noreply, state()}
  def handle_info({:checkpoint, checkpoint}, state),
    do: {:noreply, process_checkpoint(checkpoint, state)}

  @doc false
  def handle_info({:checkpoint, stream_ref, checkpoint}, %{stream_ref: stream_ref} = state),
    do: {:noreply, process_checkpoint(checkpoint, state)}

  @doc false
  def handle_info({:checkpoint, _stream_ref, _checkpoint}, state), do: {:noreply, state}

  @doc false
  def handle_info(:flush_cursor, state) do
    next_state =
      state
      |> clear_flush_timer()
      |> flush_cursor_if_dirty()
      |> schedule_flush_if_connected()

    {:noreply, next_state}
  end

  @doc false
  def handle_info({:flush_cursor, timer_token}, %{flush_timer_token: timer_token} = state) do
    next_state =
      state
      |> clear_flush_timer()
      |> flush_cursor_if_dirty()
      |> schedule_flush_if_connected()

    {:noreply, next_state}
  end

  @doc false
  def handle_info({:flush_cursor, _timer_token}, state), do: {:noreply, state}

  @doc false
  def handle_info(:reconnect, state) do
    next_state =
      state
      |> clear_reconnect_timer()
      |> connect_and_schedule_flush()

    {:noreply, next_state}
  end

  @doc false
  def handle_info({:reconnect, timer_token}, %{reconnect_timer_token: timer_token} = state) do
    next_state =
      state
      |> clear_reconnect_timer()
      |> connect_and_schedule_flush()

    {:noreply, next_state}
  end

  @doc false
  def handle_info({:reconnect, _timer_token}, state), do: {:noreply, state}

  @doc false
  def handle_info({:stream_closed, stream_ref, reason}, %{stream_ref: stream_ref} = state) do
    Logger.warning("gRPC stream closed: #{inspect(reason)}")

    next_state =
      state
      |> clear_flush_timer()
      |> shutdown_reader()
      |> flush_cursor_if_dirty()
      |> schedule_reconnect()

    {:noreply, next_state}
  end

  @doc false
  def handle_info({:stream_closed, _stream_ref, _reason}, state), do: {:noreply, state}

  @doc false
  def handle_info(
        {:DOWN, monitor_ref, :process, stream_ref, reason},
        %{reader_monitor_ref: monitor_ref, stream_ref: stream_ref} = state
      ) do
    next_state =
      case reason do
        :normal ->
          clear_reader_monitor(state)

        _other ->
          state
          |> clear_flush_timer()
          |> shutdown_reader()
          |> flush_cursor_if_dirty()
          |> schedule_reconnect()
      end

    {:noreply, next_state}
  end

  @doc false
  def handle_info({:DOWN, _monitor_ref, :process, _stream_ref, _reason}, state),
    do: {:noreply, state}

  @doc false
  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  @doc false
  @spec terminate(term(), state()) :: :ok
  def terminate(_reason, state) do
    state
    |> clear_flush_timer()
    |> clear_reconnect_timer()
    |> shutdown_reader()
    |> flush_cursor_if_dirty()

    :ok
  end

  @spec connect_and_schedule_flush(state()) :: state()
  defp connect_and_schedule_flush(state) do
    state
    |> connect_stream()
    |> schedule_flush_if_connected()
  end

  @spec connect_stream(state()) :: state()
  defp connect_stream(state) do
    state =
      state
      |> clear_reconnect_timer()
      |> shutdown_reader()

    case state.connect_fun.(state.endpoint, state.cursor) do
      {:ok, %{stream_ref: stream_ref, monitor_ref: monitor_ref}} ->
        %{state | stream_ref: stream_ref, reader_monitor_ref: monitor_ref, reconnect_attempt: 0}

      {:ok, stream_ref} ->
        %{state | stream_ref: stream_ref, reconnect_attempt: 0}

      {:error, reason} ->
        Logger.warning("gRPC stream connect failed: #{inspect(reason)}")
        schedule_reconnect(%{state | stream_ref: nil})
    end
  end

  @spec process_checkpoint(map(), state()) :: state()
  defp process_checkpoint(
         %{"sequenceNumber" => sequence_number, "transactions" => transactions},
         state
       )
       when is_integer(sequence_number) and is_list(transactions) do
    :ok =
      Codec.broadcast_checkpoint_events(
        state.pubsub,
        state.topic,
        state.event_filter_fun,
        transactions,
        sequence_number
      )

    next_state = %{
      state
      | cursor: sequence_number,
        checkpoints_since_flush: state.checkpoints_since_flush + 1
    }

    if next_state.checkpoints_since_flush >= next_state.flush_count do
      flush_cursor_if_dirty(next_state)
    else
      next_state
    end
  end

  defp process_checkpoint(checkpoint, state) do
    Logger.warning("Skipping malformed checkpoint payload: #{inspect(checkpoint)}")
    state
  end

  @spec flush_cursor_if_dirty(state()) :: state()
  defp flush_cursor_if_dirty(%{cursor: cursor, last_flushed_cursor: last_flushed_cursor} = state)
       when is_integer(cursor) and cursor != last_flushed_cursor do
    case state.save_cursor_fun.(cursor) do
      :ok ->
        %{state | last_flushed_cursor: cursor, checkpoints_since_flush: 0}

      {:error, reason} ->
        Logger.warning("Failed to persist checkpoint cursor #{cursor}: #{inspect(reason)}")
        state

      other ->
        Logger.warning("Unexpected cursor persistence result for #{cursor}: #{inspect(other)}")
        state
    end
  end

  defp flush_cursor_if_dirty(state), do: state

  @spec schedule_flush_if_connected(state()) :: state()
  defp schedule_flush_if_connected(%{stream_ref: nil} = state), do: clear_flush_timer(state)
  defp schedule_flush_if_connected(state), do: schedule_flush(state)

  @spec schedule_flush(state()) :: state()
  defp schedule_flush(state) do
    state = clear_flush_timer(state)
    timer_token = make_ref()
    timer_message = {:flush_cursor, timer_token}
    timer_handle = state.schedule_fun.(self(), timer_message, state.flush_interval_ms)

    %{state | flush_timer_token: timer_token, flush_timer_handle: timer_handle}
  end

  @spec clear_flush_timer(state()) :: state()
  defp clear_flush_timer(%{flush_timer_token: nil} = state),
    do: %{state | flush_timer_handle: nil}

  defp clear_flush_timer(state) do
    cancel_timer(state.flush_timer_handle)
    %{state | flush_timer_token: nil, flush_timer_handle: nil}
  end

  @spec schedule_reconnect(state()) :: state()
  defp schedule_reconnect(state) do
    state = clear_reconnect_timer(state)
    delay_ms = reconnect_delay_ms(state)
    timer_token = make_ref()
    timer_message = {:reconnect, timer_token}
    timer_handle = state.schedule_fun.(self(), timer_message, delay_ms)

    %{
      state
      | reconnect_attempt: state.reconnect_attempt + 1,
        reconnect_timer_token: timer_token,
        reconnect_timer_handle: timer_handle
    }
  end

  @spec clear_reconnect_timer(state()) :: state()
  defp clear_reconnect_timer(%{reconnect_timer_token: nil} = state),
    do: %{state | reconnect_timer_handle: nil}

  defp clear_reconnect_timer(state) do
    cancel_timer(state.reconnect_timer_handle)
    %{state | reconnect_timer_token: nil, reconnect_timer_handle: nil}
  end

  @spec reconnect_delay_ms(state()) :: pos_integer()
  defp reconnect_delay_ms(state) do
    multiplier = :math.pow(2, state.reconnect_attempt) |> trunc()
    min(state.reconnect_base_ms * max(multiplier, 1), state.reconnect_max_ms)
  end

  @spec clear_reader_monitor(state()) :: state()
  defp clear_reader_monitor(%{reader_monitor_ref: nil} = state), do: state

  defp clear_reader_monitor(state) do
    Process.demonitor(state.reader_monitor_ref, [:flush])
    %{state | reader_monitor_ref: nil}
  end

  @spec shutdown_reader(state()) :: state()
  defp shutdown_reader(%{stream_ref: stream_ref} = state) when is_pid(stream_ref) do
    if Process.alive?(stream_ref) do
      Process.exit(stream_ref, :shutdown)
    end

    state
    |> clear_reader_monitor()
    |> Map.put(:stream_ref, nil)
  end

  defp shutdown_reader(state), do: clear_reader_monitor(%{state | stream_ref: nil})

  @spec cancel_timer(term()) :: :ok
  defp cancel_timer(timer_handle) when is_reference(timer_handle) do
    _cancelled = Process.cancel_timer(timer_handle)
    :ok
  end

  defp cancel_timer(_timer_handle), do: :ok

  @spec grpc_endpoint() :: String.t()
  defp grpc_endpoint do
    Application.get_env(:sigil, :grpc_endpoint, @default_endpoint)
  end

  @spec default_schedule(pid(), term(), non_neg_integer()) :: reference()
  defp default_schedule(pid, message, delay_ms), do: Process.send_after(pid, message, delay_ms)
end
