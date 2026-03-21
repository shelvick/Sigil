defmodule Sigil.GateIndexer do
  @moduledoc """
  Periodically indexes on-chain gates into the cache-backed gate network table.
  """

  use GenServer

  require Logger

  alias Sigil.Cache
  alias Sigil.Sui.Client
  alias Sigil.Sui.Types.Gate

  @sui_client Application.compile_env!(:sigil, :sui_client)
  @default_interval_ms 60_000
  @default_pubsub Sigil.PubSub
  @resolve_retry_ms 500
  @gate_network_topic "gate_network"

  @typedoc "Runtime state for the gate indexer process."
  @type state() :: %{
          tables: %{atom() => Cache.table_id()} | nil,
          pubsub: atom() | module(),
          interval_ms: pos_integer(),
          req_options: Client.request_opts(),
          resolve_tables: (-> %{atom() => Cache.table_id()} | nil)
        }

  @typedoc "Single start option for the gate indexer."
  @type option() ::
          {:tables, %{atom() => Cache.table_id()}}
          | {:pubsub, atom() | module()}
          | {:interval_ms, pos_integer()}
          | {:req_options, Client.request_opts()}
          | {:mox_owner, pid()}
          | {:resolve_tables, (-> %{atom() => Cache.table_id()} | nil)}

  @type options() :: [option()]
  @type topology() :: %{String.t() => MapSet.t(String.t())}
  @type location_index() :: %{binary() => MapSet.t(String.t())}

  @doc "Returns a unique child spec so tests can start isolated indexers."
  @spec child_spec(options()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: {__MODULE__, System.unique_integer([:positive])},
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  @doc "Starts a linked gate indexer process."
  @spec start_link(options()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc "Builds a bidirectional adjacency map from linked gates."
  @spec build_topology([Gate.t()]) :: topology()
  def build_topology(gates) when is_list(gates) do
    Enum.reduce(gates, %{}, fn
      %Gate{id: gate_id, linked_gate_id: linked_gate_id}, acc when is_binary(linked_gate_id) ->
        acc
        |> Map.update(gate_id, MapSet.new([linked_gate_id]), &MapSet.put(&1, linked_gate_id))
        |> Map.update(linked_gate_id, MapSet.new([gate_id]), &MapSet.put(&1, gate_id))

      %Gate{}, acc ->
        acc
    end)
  end

  @doc "Builds a location-to-gate-id index from indexed gates."
  @spec build_location_index([Gate.t()]) :: location_index()
  def build_location_index(gates) when is_list(gates) do
    Enum.reduce(gates, %{}, fn %Gate{id: gate_id, location: %{location_hash: location_hash}},
                               acc ->
      Map.update(acc, location_hash, MapSet.new([gate_id]), &MapSet.put(&1, gate_id))
    end)
  end

  @doc "Lists all cached gates from the gate network table."
  @spec list_gates(keyword()) :: [Gate.t()]
  def list_gates(opts) when is_list(opts) do
    case gate_table(opts) do
      nil -> []
      table -> table |> Cache.all() |> Enum.filter(&match?(%Gate{}, &1))
    end
  end

  @doc "Returns a cached gate by id."
  @spec get_gate(String.t(), keyword()) :: Gate.t() | nil
  def get_gate(gate_id, opts) when is_binary(gate_id) and is_list(opts) do
    case gate_table(opts) do
      nil -> nil
      table -> Cache.get(table, gate_id)
    end
  end

  @doc "Returns the cached gate topology graph."
  @spec get_topology(keyword()) :: topology()
  def get_topology(opts) when is_list(opts) do
    case gate_table(opts) do
      nil -> %{}
      table -> Cache.get(table, :topology) || %{}
    end
  end

  @doc "Returns the cached gates present at a location hash."
  @spec gates_at_location(binary(), keyword()) :: [Gate.t()]
  def gates_at_location(location_hash, opts) when is_binary(location_hash) and is_list(opts) do
    case gate_table(opts) do
      nil ->
        []

      table ->
        table
        |> Cache.get(:location_index)
        |> case do
          %{^location_hash => gate_ids} ->
            gate_ids
            |> MapSet.to_list()
            |> Enum.map(&Cache.get(table, &1))
            |> Enum.filter(&match?(%Gate{}, &1))

          _other ->
            []
        end
    end
  end

  @doc false
  @impl true
  @spec init(options()) :: {:ok, state()}
  def init(opts) do
    :ok = maybe_allow_mock_owner(opts)

    state = %{
      tables: Keyword.get(opts, :tables),
      pubsub: Keyword.get(opts, :pubsub, @default_pubsub),
      interval_ms: Keyword.get(opts, :interval_ms, @default_interval_ms),
      req_options: Keyword.get(opts, :req_options, []),
      resolve_tables: Keyword.get(opts, :resolve_tables, &default_resolve_tables/0)
    }

    send(self(), :resolve_and_scan)
    {:ok, state}
  end

  @doc false
  @impl true
  @spec handle_info(:resolve_and_scan | :scan, state()) :: {:noreply, state()}
  def handle_info(:resolve_and_scan, state) do
    case resolve_gate_tables(state) do
      {:ok, tables} ->
        {:noreply, scan(%{state | tables: tables})}

      :error ->
        Process.send_after(self(), :resolve_and_scan, @resolve_retry_ms)
        {:noreply, state}
    end
  end

  @doc false
  @impl true
  def handle_info(:scan, state) do
    {:noreply, scan(state)}
  end

  @spec scan(state()) :: state()
  defp scan(%{tables: nil} = state) do
    Process.send_after(self(), :resolve_and_scan, @resolve_retry_ms)
    state
  end

  defp scan(state) do
    next_state =
      case fetch_all_gates(state.req_options) do
        {:ok, gates} ->
          persist_scan(gates, state)

        {:error, reason} ->
          Logger.warning("gate index scan failed: #{inspect(reason)}")
          state
      end

    schedule_scan(next_state.interval_ms)
    next_state
  end

  @spec fetch_all_gates(Client.request_opts()) ::
          {:ok, [Gate.t()]} | {:error, Client.error_reason()}
  defp fetch_all_gates(req_options) do
    fetch_gates_acc(nil, req_options, [])
  end

  @spec fetch_gates_acc(String.t() | nil, Client.request_opts(), [Gate.t()]) ::
          {:ok, [Gate.t()]} | {:error, Client.error_reason()}
  defp fetch_gates_acc(cursor, req_options, acc) do
    filters = gate_filters(cursor)

    with {:ok, %{data: gates_json, has_next_page: has_next_page, end_cursor: end_cursor}} <-
           @sui_client.get_objects(filters, req_options) do
      gates = parse_gates(gates_json)
      acc = Enum.reverse(gates) ++ acc

      if has_next_page and is_binary(end_cursor) do
        fetch_gates_acc(end_cursor, req_options, acc)
      else
        {:ok, Enum.reverse(acc)}
      end
    end
  end

  @spec parse_gates([map()]) :: [Gate.t()]
  defp parse_gates(gates_json) when is_list(gates_json) do
    Enum.reduce(gates_json, [], fn gate_json, acc ->
      case parse_gate(gate_json) do
        {:ok, gate} -> [gate | acc]
        :error -> acc
      end
    end)
  end

  @spec parse_gate(map()) :: {:ok, Gate.t()} | :error
  defp parse_gate(gate_json) when is_map(gate_json) do
    {:ok, Gate.from_json(gate_json)}
  rescue
    error ->
      Logger.warning("skipping malformed gate payload: #{Exception.message(error)}")
      :error
  end

  @spec persist_scan([Gate.t()], state()) :: state()
  defp persist_scan(gates, %{tables: tables} = state) do
    gate_table = Map.fetch!(tables, :gate_network)
    topology = build_topology(gates)
    location_index = build_location_index(gates)
    previous_gate_ids = cached_gate_ids(gate_table)
    new_gate_ids = MapSet.new(Enum.map(gates, & &1.id))
    removed_gate_ids = MapSet.difference(previous_gate_ids, new_gate_ids)
    added_gate_ids = MapSet.difference(new_gate_ids, previous_gate_ids)

    Enum.each(removed_gate_ids, &Cache.delete(gate_table, &1))
    Enum.each(gates, &Cache.put(gate_table, &1.id, &1))
    Cache.put(gate_table, :topology, topology)
    Cache.put(gate_table, :location_index, location_index)

    :ok =
      Phoenix.PubSub.broadcast(state.pubsub, @gate_network_topic, {
        :gates_updated,
        %{
          count: length(gates),
          added: MapSet.size(added_gate_ids),
          removed: MapSet.size(removed_gate_ids)
        }
      })

    state
  end

  @spec cached_gate_ids(Cache.table_id()) :: MapSet.t(String.t())
  defp cached_gate_ids(gate_table) do
    gate_table
    |> :ets.tab2list()
    |> Enum.reduce(MapSet.new(), fn
      {gate_id, %Gate{}}, acc when is_binary(gate_id) -> MapSet.put(acc, gate_id)
      {_key, _value}, acc -> acc
    end)
  end

  @spec resolve_gate_tables(state()) :: {:ok, %{atom() => Cache.table_id()}} | :error
  defp resolve_gate_tables(%{tables: %{gate_network: gate_network} = tables}) do
    case :ets.info(gate_network) do
      :undefined -> :error
      _info -> {:ok, tables}
    end
  end

  defp resolve_gate_tables(%{resolve_tables: resolve_tables}) do
    case resolve_tables.() do
      %{gate_network: gate_network} = tables when not is_nil(gate_network) ->
        case :ets.info(gate_network) do
          :undefined -> :error
          _info -> {:ok, tables}
        end

      _other ->
        :error
    end
  end

  @spec default_resolve_tables() :: %{atom() => Cache.table_id()} | nil
  defp default_resolve_tables do
    case Process.whereis(Sigil.Supervisor) do
      pid when is_pid(pid) ->
        pid
        |> Supervisor.which_children()
        |> Enum.find_value(fn
          {Sigil.Cache, cache_pid, _kind, _modules} when is_pid(cache_pid) ->
            Cache.tables(cache_pid)

          _other ->
            nil
        end)

      _other ->
        nil
    end
  end

  @spec gate_filters(String.t() | nil) :: Client.object_filter()
  defp gate_filters(nil), do: [type: gate_type()]
  defp gate_filters(cursor), do: [type: gate_type(), cursor: cursor]

  @spec gate_type() :: String.t()
  defp gate_type do
    "#{world_package_id()}::gate::Gate"
  end

  @spec world_package_id() :: String.t()
  defp world_package_id do
    world = Application.fetch_env!(:sigil, :eve_world)
    worlds = Application.fetch_env!(:sigil, :eve_worlds)
    %{package_id: package_id} = Map.fetch!(worlds, world)
    package_id
  end

  @spec gate_table(keyword()) :: Cache.table_id() | nil
  defp gate_table(opts) do
    case opts |> Keyword.get(:tables, %{}) |> Map.get(:gate_network) do
      nil -> nil
      table -> if :ets.info(table) == :undefined, do: nil, else: table
    end
  end

  @spec maybe_allow_mock_owner(options()) :: :ok
  defp maybe_allow_mock_owner(opts) do
    owner = Keyword.get(opts, :mox_owner)
    mox = Module.concat([Mox])

    cond do
      owner in [nil, self()] ->
        :ok

      not Code.ensure_loaded?(mox) ->
        :ok

      not function_exported?(mox, :allow, 3) ->
        :ok

      not String.ends_with?(Atom.to_string(@sui_client), "Mock") ->
        :ok

      true ->
        mox.allow(@sui_client, owner, self())
        :ok
    end
  end

  @spec schedule_scan(pos_integer()) :: reference()
  defp schedule_scan(interval_ms) do
    Process.send_after(self(), :scan, interval_ms)
  end
end
