defmodule Sigil.GameState.Poller do
  @moduledoc """
  Polls cached assemblies on an interval and refreshes them through the assemblies context.
  """

  use GenServer

  require Logger

  alias Sigil.Assemblies
  alias Sigil.Sui.Client

  @default_interval_ms 30_000
  @default_pubsub Sigil.PubSub

  @typedoc "Runtime state for a linked state poller."
  @type state() :: %{
          assembly_ids: [String.t()],
          tables: Assemblies.tables(),
          pubsub: atom() | module(),
          interval_ms: pos_integer(),
          req_options: Client.request_opts(),
          sync_fun: function()
        }

  @typedoc "Options accepted by the linked state poller."
  @type option() ::
          {:assembly_ids, [String.t()]}
          | {:tables, Assemblies.tables()}
          | {:pubsub, atom() | module()}
          | {:interval_ms, pos_integer()}
          | {:req_options, Client.request_opts()}
          | {:sync_fun, function()}

  @type options() :: [option()]

  @doc """
  Returns a unique child spec so multiple pollers can run concurrently.
  """
  @spec child_spec(options()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: {__MODULE__, System.unique_integer([:positive])},
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  @doc """
  Starts a linked poller for the provided assembly ids.
  """
  @spec start_link(options()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc """
  Stops a running poller.
  """
  @spec stop(pid()) :: :ok
  def stop(poller_pid) when is_pid(poller_pid) do
    GenServer.stop(poller_pid)
  end

  @doc """
  Replaces the list of assembly ids used by future poll cycles.
  """
  @spec update_assembly_ids(pid(), [String.t()]) :: :ok
  def update_assembly_ids(poller_pid, assembly_ids)
      when is_pid(poller_pid) and is_list(assembly_ids) do
    GenServer.call(poller_pid, {:update_assembly_ids, assembly_ids})
  end

  @doc false
  @impl true
  @spec init(options()) :: {:ok, state()}
  def init(opts) do
    state = %{
      assembly_ids: Keyword.get(opts, :assembly_ids, []),
      tables: Keyword.fetch!(opts, :tables),
      pubsub: Keyword.get(opts, :pubsub, @default_pubsub),
      interval_ms: Keyword.get(opts, :interval_ms, @default_interval_ms),
      req_options: Keyword.get(opts, :req_options, []),
      sync_fun: Keyword.get(opts, :sync_fun, &Assemblies.sync_assembly/2)
    }

    schedule_poll(state.interval_ms)
    {:ok, state}
  end

  @doc false
  @impl true
  @spec handle_call({:update_assembly_ids, [String.t()]}, GenServer.from(), state()) ::
          {:reply, :ok, state()}
  def handle_call({:update_assembly_ids, assembly_ids}, _from, state) do
    {:reply, :ok, %{state | assembly_ids: assembly_ids}}
  end

  @doc false
  @impl true
  @spec handle_info(:poll, state()) :: {:noreply, state()}
  def handle_info(:poll, state) do
    Enum.each(state.assembly_ids, &sync_assembly(&1, state))
    schedule_poll(state.interval_ms)
    {:noreply, state}
  end

  @spec sync_assembly(String.t(), state()) :: :ok
  defp sync_assembly(assembly_id, state) do
    opts = [tables: state.tables, pubsub: state.pubsub, req_options: state.req_options]

    try do
      case state.sync_fun.(assembly_id, opts) do
        {:ok, _assembly} ->
          :ok

        {:error, reason} ->
          Logger.warning("state poll failed for #{assembly_id}: #{inspect(reason)}")
      end
    rescue
      error ->
        Logger.warning("state poll crashed for #{assembly_id}: #{Exception.message(error)}")
    end
  end

  @spec schedule_poll(pos_integer()) :: reference()
  defp schedule_poll(interval_ms) do
    Process.send_after(self(), :poll, interval_ms)
  end
end
