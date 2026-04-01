defmodule Sigil.StaticData do
  @moduledoc """
  DETS-backed static data store loaded into process-owned ETS tables.
  """

  use GenServer

  require Logger

  alias Sigil.StaticData.Constellation
  alias Sigil.StaticData.DetsFile
  alias Sigil.StaticData.ItemType
  alias Sigil.StaticData.SolarSystem
  alias Sigil.Worlds
  @table_names [:solar_systems, :item_types, :constellations]

  @table_metadata %{
    solar_systems: %{fetch: :fetch_solar_systems, parser: &SolarSystem.from_json/1},
    item_types: %{fetch: :fetch_types, parser: &ItemType.from_json/1},
    constellations: %{fetch: :fetch_constellations, parser: &Constellation.from_json/1}
  }

  @typedoc "ETS table identifier returned by `:ets.new/2`."
  @type table_id() :: :ets.tid()

  @typedoc "Supported static data table names."
  @type table_name() :: :solar_systems | :item_types | :constellations

  @typedoc "Static data rows loaded directly for tests."
  @type test_data() :: %{
          optional(:solar_systems) => [SolarSystem.t()],
          optional(:item_types) => [ItemType.t()],
          optional(:constellations) => [Constellation.t()]
        }

  @typedoc "GenServer state for static data tables."
  @type state() :: %{
          tables: %{table_name() => table_id()},
          ready?: boolean(),
          pending_callers: [GenServer.from()],
          load_opts: [option()]
        }

  @typedoc "Options accepted by `start_link/1`."
  @type option() ::
          {:dets_dir, String.t()}
          | {:world_client, module()}
          | {:test_data, test_data()}
          | {:mox_owner, pid()}
          | {:world, Worlds.world_name()}

  @doc "Returns a unique child spec so tests can start multiple isolated instances."
  @spec child_spec([option()]) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: {__MODULE__, System.unique_integer([:positive])},
      start: {__MODULE__, :start_link, [normalize_start_opts(opts)]}
    }
  end

  @doc "Starts a static data store process."
  @spec start_link([option()]) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, normalize_start_opts(opts))
  end

  @doc "Returns the ETS tables owned by the static data process."
  @spec tables(pid()) :: %{table_name() => table_id()}
  def tables(pid) do
    GenServer.call(pid, :tables)
  end

  @doc "Fetches a solar system by id."
  @spec get_solar_system(pid(), integer()) :: SolarSystem.t() | nil
  def get_solar_system(pid, id) do
    get_record(pid, :solar_systems, id)
  end

  @doc "Lists all solar systems."
  @spec list_solar_systems(pid()) :: [SolarSystem.t()]
  def list_solar_systems(pid) do
    list_records(pid, :solar_systems)
  end

  @doc "Searches solar systems by case-insensitive name prefix."
  @spec search_solar_systems(pid(), String.t(), pos_integer()) :: [SolarSystem.t()]
  def search_solar_systems(pid, query, limit \\ 20)

  def search_solar_systems(pid, query, limit)
      when is_binary(query) and is_integer(limit) and limit > 0 do
    normalized_query = String.downcase(query)

    pid
    |> tables()
    |> Map.fetch!(:solar_systems)
    |> matching_solar_systems(fn %{name: name} ->
      String.starts_with?(String.downcase(name), normalized_query)
    end)
    |> Enum.take(limit)
  end

  @doc "Returns a solar system when exactly one case-insensitive exact-name match exists."
  @spec get_solar_system_by_name(pid(), String.t()) :: SolarSystem.t() | nil
  def get_solar_system_by_name(pid, name) when is_binary(name) do
    normalized_name = String.downcase(name)

    case pid
         |> tables()
         |> Map.fetch!(:solar_systems)
         |> matching_solar_systems(fn %{name: system_name} ->
           String.downcase(system_name) == normalized_name
         end) do
      [system] -> system
      _systems -> nil
    end
  end

  @doc "Fetches an item type by id."
  @spec get_item_type(pid(), integer()) :: ItemType.t() | nil
  def get_item_type(pid, id) do
    get_record(pid, :item_types, id)
  end

  @doc "Lists all item types."
  @spec list_item_types(pid()) :: [ItemType.t()]
  def list_item_types(pid) do
    list_records(pid, :item_types)
  end

  @doc "Fetches a constellation by id."
  @spec get_constellation(pid(), integer()) :: Constellation.t() | nil
  def get_constellation(pid, id) do
    get_record(pid, :constellations, id)
  end

  @doc "Lists all constellations."
  @spec list_constellations(pid()) :: [Constellation.t()]
  def list_constellations(pid) do
    list_records(pid, :constellations)
  end

  @impl true
  @spec init([option()]) :: {:ok, state(), {:continue, :load_tables}}
  def init(opts) do
    :ok = maybe_allow_mock_owner(opts)

    {:ok,
     %{
       tables: new_tables(),
       ready?: false,
       pending_callers: [],
       load_opts: opts
     }, {:continue, :load_tables}}
  end

  @impl true
  @spec handle_continue(:load_tables, state()) :: {:noreply, state()}
  def handle_continue(:load_tables, state) do
    :ok = populate_tables(state.load_opts, state.tables)
    reply_pending_callers(state.pending_callers, state.tables)

    {:noreply, %{state | ready?: true, pending_callers: [], load_opts: []}}
  end

  @impl true
  @spec handle_call(:tables, GenServer.from(), state()) ::
          {:reply, %{table_name() => table_id()}, state()} | {:noreply, state()}
  def handle_call(:tables, from, %{ready?: false} = state) do
    {:noreply, %{state | pending_callers: [from | state.pending_callers]}}
  end

  def handle_call(:tables, _from, state) do
    {:reply, state.tables, state}
  end

  @spec new_tables() :: %{table_name() => table_id()}
  defp new_tables do
    Enum.into(@table_names, %{}, fn table_name -> {table_name, new_table()} end)
  end

  @spec populate_tables([option()], %{table_name() => table_id()}) :: :ok
  defp populate_tables(opts, tables) do
    case Keyword.get(opts, :test_data) do
      nil -> load_runtime_tables(opts, tables)
      test_data -> load_test_tables(test_data, tables)
    end
  end

  @spec load_test_tables(test_data(), %{table_name() => table_id()}) :: :ok
  defp load_test_tables(test_data, tables) do
    Enum.each(@table_names, fn table_name ->
      tables
      |> Map.fetch!(table_name)
      |> insert_structs(Map.get(test_data, table_name, []))
    end)
  end

  @spec load_runtime_tables([option()], %{table_name() => table_id()}) :: :ok
  defp load_runtime_tables(opts, tables) do
    dets_dir = Keyword.get(opts, :dets_dir, default_dets_dir())

    world_client =
      Keyword.get(opts, :world_client, Application.fetch_env!(:sigil, :world_client))

    world_api_url = resolve_world_api_url(opts)

    Enum.each(@table_names, fn table_name ->
      tables
      |> Map.fetch!(table_name)
      |> load_table(
        DetsFile.dets_path(dets_dir, table_name),
        table_name,
        world_client,
        world_api_url
      )
    end)
  end

  @spec load_table(table_id(), String.t(), table_name(), module(), String.t() | nil) :: :ok
  defp load_table(tid, path, table_name, world_client, world_api_url) do
    case load_dets_into_ets(tid, path) do
      :ok ->
        :ok

      {:error, :missing} ->
        maybe_fetch_into_ets(tid, path, table_name, world_client, world_api_url)

      {:error, reason} ->
        Logger.warning("Static data DETS unavailable for #{table_name}: #{inspect(reason)}")
        maybe_fetch_into_ets(tid, path, table_name, world_client, world_api_url)
    end
  end

  @spec reply_pending_callers([GenServer.from()], %{table_name() => table_id()}) :: :ok
  defp reply_pending_callers(callers, tables) do
    Enum.each(callers, &GenServer.reply(&1, tables))
  end

  @spec maybe_fetch_into_ets(table_id(), String.t(), table_name(), module(), String.t() | nil) ::
          :ok
  defp maybe_fetch_into_ets(tid, path, table_name, world_client, world_api_url) do
    case fetch_and_write(path, table_name, world_client, world_api_url) do
      :ok ->
        case load_dets_into_ets(tid, path) do
          :ok ->
            :ok

          {:error, reason} ->
            Logger.warning("Failed to load static data for #{table_name}: #{inspect(reason)}")
            :ok
        end

      {:error, reason} ->
        Logger.warning("Failed to fetch static data for #{table_name}: #{inspect(reason)}")
        :ok
    end
  end

  @spec get_record(pid(), table_name(), integer()) :: term() | nil
  defp get_record(pid, table_name, id) do
    pid
    |> tables()
    |> Map.fetch!(table_name)
    |> lookup(id)
  end

  @spec list_records(pid(), table_name()) :: [term()]
  defp list_records(pid, table_name) do
    pid
    |> tables()
    |> Map.fetch!(table_name)
    |> all_rows()
  end

  @spec lookup(table_id(), integer()) :: term() | nil
  defp lookup(tid, id) do
    case :ets.lookup(tid, id) do
      [{^id, value}] -> value
      [] -> nil
    end
  end

  @spec all_rows(table_id()) :: [term()]
  defp all_rows(tid) do
    tid
    |> :ets.tab2list()
    |> Enum.map(fn {_id, value} -> value end)
  end

  @spec matching_solar_systems(table_id(), (SolarSystem.t() -> as_boolean(term()))) ::
          [SolarSystem.t()]
  defp matching_solar_systems(tid, matcher) do
    :ets.foldl(
      fn {_id, system}, acc ->
        if matcher.(system), do: [system | acc], else: acc
      end,
      [],
      tid
    )
    |> Enum.sort_by(&String.downcase(&1.name))
  end

  @spec new_table() :: table_id()
  defp new_table do
    :ets.new(__MODULE__, [:set, :public, read_concurrency: true])
  end

  @spec insert_structs(table_id(), [struct()]) :: :ok
  defp insert_structs(tid, structs) do
    rows = Enum.map(structs, fn struct -> {Map.fetch!(struct, :id), struct} end)

    case rows do
      [] ->
        :ok

      _rows ->
        true = :ets.insert(tid, rows)
        :ok
    end
  end

  @spec load_dets_into_ets(table_id(), String.t()) :: :ok | {:error, term()}
  defp load_dets_into_ets(tid, path) do
    if File.exists?(path) do
      case DetsFile.open_file(path) do
        {:ok, dets_ref} ->
          try do
            copy_dets_rows(dets_ref, tid)
          after
            :ok = :dets.close(dets_ref)
          end

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, :missing}
    end
  end

  @spec copy_dets_rows(atom(), table_id()) :: :ok | {:error, term()}
  defp copy_dets_rows(dets_ref, tid) do
    rows = :dets.foldl(fn row, acc -> [row | acc] end, [], dets_ref)

    case rows do
      [] ->
        :ok

      _rows ->
        true = :ets.insert(tid, rows)
        :ok
    end
  rescue
    error -> {:error, error}
  end

  @spec fetch_and_write(String.t(), table_name(), module(), String.t() | nil) ::
          :ok | {:error, term()}
  defp fetch_and_write(path, table_name, world_client, world_api_url) do
    case fetch_rows(table_name, world_client, world_api_url) do
      {:ok, rows} ->
        File.mkdir_p!(Path.dirname(path))
        DetsFile.write_rows!(path, rows)
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec fetch_rows(table_name(), module(), String.t() | nil) ::
          {:ok, [{integer(), struct()}]} | {:error, term()}
  defp fetch_rows(table_name, world_client, world_api_url) do
    meta = Map.fetch!(@table_metadata, table_name)
    opts = if world_api_url, do: [base_url: world_api_url], else: []

    case apply(world_client, meta.fetch, [opts]) do
      {:ok, records} when is_list(records) ->
        {:ok,
         Enum.map(records, fn record ->
           parsed = meta.parser.(record)
           {parsed.id, parsed}
         end)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec resolve_world_api_url([option()]) :: String.t() | nil
  defp resolve_world_api_url(opts) when is_list(opts) do
    opts
    |> Keyword.get(:world, Worlds.default_world())
    |> Worlds.world_api_url()
  end

  @spec default_dets_dir() :: String.t()
  defp default_dets_dir do
    Application.get_env(
      :sigil,
      :static_data_dir,
      Application.app_dir(:sigil, "priv/static_data")
    )
  end

  @spec normalize_start_opts([option()]) :: [option()]
  defp normalize_start_opts(opts) do
    if Keyword.has_key?(opts, :world_client) do
      Keyword.put_new(opts, :mox_owner, self())
    else
      opts
    end
  end

  @spec maybe_allow_mock_owner([option()]) :: :ok
  defp maybe_allow_mock_owner(opts) do
    owner = Keyword.get(opts, :mox_owner)

    world_client =
      Keyword.get(opts, :world_client, Application.fetch_env!(:sigil, :world_client))

    mox = Module.concat([Mox])

    cond do
      owner in [nil, self()] ->
        :ok

      not Code.ensure_loaded?(mox) ->
        :ok

      not function_exported?(mox, :allow, 3) ->
        :ok

      not String.ends_with?(Atom.to_string(world_client), "Mock") ->
        :ok

      true ->
        mox.allow(world_client, owner, self())
        :ok
    end
  end
end
