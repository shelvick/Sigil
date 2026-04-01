defmodule Sigil.StaticDataTestFixtures do
  @moduledoc false

  alias Sigil.StaticData.Constellation
  alias Sigil.StaticData.DetsFile
  alias Sigil.StaticData.ItemType
  alias Sigil.StaticData.SolarSystem

  @type static_data() :: %{
          solar_systems: [SolarSystem.t()],
          item_types: [ItemType.t()],
          constellations: [Constellation.t()]
        }

  @doc "Builds a unique temp directory path for a test probe without creating it."
  @spec temp_dir(String.t()) :: String.t()
  def temp_dir(prefix) do
    Path.join([
      System.tmp_dir!(),
      "sigil_tests",
      prefix <> "_" <> Integer.to_string(System.unique_integer([:positive]))
    ])
  end

  @doc "Creates and returns a unique temp directory for a test probe."
  @spec ensure_tmp_dir!(String.t()) :: String.t()
  def ensure_tmp_dir!(prefix) do
    dir = temp_dir(prefix)
    File.mkdir_p!(dir)
    dir
  end

  @doc "Writes a config file for spawned application probe subprocesses."
  @spec write_application_probe_config!(String.t(), keyword()) :: String.t()
  def write_application_probe_config!(config_dir, opts) do
    start_static_data = Keyword.get(opts, :start_static_data, false)
    start_gate_indexer = Keyword.get(opts, :start_gate_indexer, false)
    start_monitor_supervisor = Keyword.get(opts, :start_monitor_supervisor, false)
    start_assembly_event_router = Keyword.get(opts, :start_assembly_event_router, false)
    start_alert_engine = Keyword.get(opts, :start_alert_engine, false)
    start_repo = Keyword.get(opts, :start_repo, false)
    start_grpc_stream = Keyword.get(opts, :start_grpc_stream, false)
    start_reputation_engine = Keyword.get(opts, :start_reputation_engine, false)
    monitor_registry = Keyword.get(opts, :monitor_registry, nil)
    monitor_registries = Keyword.get(opts, :monitor_registries, %{})
    active_worlds = Keyword.get(opts, :active_worlds, ["test"])
    eve_world = Keyword.get(opts, :eve_world, List.first(active_worlds) || "test")
    eve_worlds = Keyword.get(opts, :eve_worlds)
    grpc_endpoint = Keyword.get(opts, :grpc_endpoint, "127.0.0.1:1")
    grpc_connector = Keyword.get(opts, :grpc_connector, nil)
    static_data_dir = Keyword.fetch!(opts, :static_data_dir)
    world_client = Keyword.fetch!(opts, :world_client)
    config_path = Path.join(config_dir, "application_probe_config.exs")

    eve_worlds_config =
      case eve_worlds do
        worlds when is_map(worlds) -> "config :sigil, :eve_worlds, #{inspect(worlds)}\n"
        _other -> ""
      end

    File.write!(
      config_path,
      """
      import Config

      config :sigil, :start_static_data, #{inspect(start_static_data)}
      config :sigil, :start_gate_indexer, #{inspect(start_gate_indexer)}
      config :sigil, :start_monitor_supervisor, #{inspect(start_monitor_supervisor)}
      config :sigil, :start_assembly_event_router, #{inspect(start_assembly_event_router)}
      config :sigil, :start_alert_engine, #{inspect(start_alert_engine)}
      config :sigil, :start_repo, #{inspect(start_repo)}
      config :sigil, :start_grpc_stream, #{inspect(start_grpc_stream)}
      config :sigil, :start_reputation_engine, #{inspect(start_reputation_engine)}
      config :sigil, :monitor_registry, #{inspect(monitor_registry)}
      config :sigil, :monitor_registries, #{inspect(monitor_registries)}
      config :sigil, :eve_world, #{inspect(eve_world)}
      config :sigil, :active_worlds, #{inspect(active_worlds)}
      #{eve_worlds_config}config :sigil, :grpc_endpoint, #{inspect(grpc_endpoint)}
      config :sigil, :grpc_connector, #{inspect(grpc_connector)}
      config :sigil, :static_data_dir, #{inspect(static_data_dir)}
      config :sigil, :world_client, #{inspect(world_client)}
      """
    )

    config_path
  end

  @doc "Writes a config file for spawned diplomacy probe subprocesses."
  @spec write_diplomacy_probe_config!(String.t(), keyword()) :: String.t()
  def write_diplomacy_probe_config!(config_dir, opts) do
    gas_price = Keyword.get(opts, :reference_gas_price, 1_000)
    world_client = Keyword.get(opts, :world_client, Sigil.DiplomacyTestWorldClient)
    config_path = Path.join(config_dir, "diplomacy_probe_config.exs")

    File.write!(
      config_path,
      """
      import Config

      config :sigil, :world_client, #{inspect(world_client)}
      config :sigil, :reference_gas_price, #{inspect(gas_price)}
      """
    )

    config_path
  end

  @doc "Writes a config file for spawned populate_static_data probe subprocesses."
  @spec write_populate_static_data_config!(String.t(), String.t()) :: String.t()
  def write_populate_static_data_config!(config_dir, output_dir) do
    config_path = Path.join(config_dir, "populate_static_data_config.exs")

    File.write!(
      config_path,
      """
      import Config

      config :sigil, :static_data_dir, #{inspect(output_dir)}
      config :sigil, :world_client, Sigil.StaticData.WorldClientMock
      """
    )

    config_path
  end

  @doc "Builds `mix run` arguments that load a test config file first."
  @spec mix_run_args(String.t(), String.t(), keyword()) :: [String.t()]
  def mix_run_args(config_path, script, opts \\ []) do
    run_flags =
      ["--no-compile", "--no-deps-check", "--no-archives-check"] ++
        if Keyword.get(opts, :no_start, false), do: ["--no-start"], else: []

    ["do", "loadconfig", Path.expand(config_path), "+", "run"] ++ run_flags ++ ["-e", script]
  end

  @doc "Returns isolated Hex env vars for spawned mix subprocesses."
  @spec mix_subprocess_env(String.t()) :: [{String.t(), String.t()}]
  def mix_subprocess_env(prefix) do
    base_dir = ensure_tmp_dir!(prefix)
    hex_home = Path.join(base_dir, "hex_home")
    File.mkdir_p!(hex_home)

    [
      {"HEX_HOME", hex_home},
      {"ELIXIR_CLI_NO_VALIDATE_COMPILE_ENV", "1"}
    ]
  end

  @doc "Writes DETS fixture files for static-data subprocess tests."
  @spec write_dets_fixture!(String.t(), static_data()) :: :ok
  def write_dets_fixture!(dets_dir, data) do
    File.mkdir_p!(dets_dir)
    write_rows!(dets_path(dets_dir, :solar_systems), data.solar_systems)
    write_rows!(dets_path(dets_dir, :item_types), data.item_types)
    write_rows!(dets_path(dets_dir, :constellations), data.constellations)
  end

  @doc "Returns canonical static-data fixture structs used by tests."
  @spec sample_test_data() :: static_data()
  def sample_test_data do
    %{
      solar_systems: [
        solar_system_struct(),
        solar_system_struct(%{id: 30_000_002, name: "B 31337"})
      ],
      item_types: [item_type_struct(), item_type_struct(%{id: 72_245, name: "Ancient Relic"})],
      constellations: [
        constellation_struct(),
        constellation_struct(%{id: 20_000_002, name: "20000002"})
      ]
    }
  end

  @doc "Returns an alternate static-data fixture set for update scenarios."
  @spec updated_test_data() :: static_data()
  def updated_test_data do
    %{
      solar_systems: [solar_system_struct(%{id: 30_000_003, name: "C 9000"})],
      item_types: [item_type_struct(%{id: 72_246, name: "Reactive Plating"})],
      constellations: [constellation_struct(%{id: 20_000_003, name: "20000003"})]
    }
  end

  @doc "Builds a solar-system fixture struct with optional field overrides."
  @spec solar_system_struct(map()) :: SolarSystem.t()
  def solar_system_struct(overrides \\ %{}) do
    struct!(SolarSystem, Map.merge(base_solar_system(), overrides))
  end

  @doc "Builds an item-type fixture struct with optional field overrides."
  @spec item_type_struct(map()) :: ItemType.t()
  def item_type_struct(overrides \\ %{}) do
    struct!(ItemType, Map.merge(base_item_type(), overrides))
  end

  @doc "Builds a constellation fixture struct with optional field overrides."
  @spec constellation_struct(map()) :: Constellation.t()
  def constellation_struct(overrides \\ %{}) do
    struct!(Constellation, Map.merge(base_constellation(), overrides))
  end

  @doc "Returns solar system fixture rows encoded as World API-style maps."
  @spec solar_system_records() :: [map()]
  def solar_system_records do
    sample_test_data()
    |> Map.fetch!(:solar_systems)
    |> Enum.map(&solar_system_json/1)
  end

  @doc "Returns item type fixture rows encoded as World API-style maps."
  @spec item_type_records() :: [map()]
  def item_type_records do
    sample_test_data()
    |> Map.fetch!(:item_types)
    |> Enum.map(&item_type_json/1)
  end

  @doc "Returns constellation fixture rows encoded as World API-style maps."
  @spec constellation_records() :: [map()]
  def constellation_records do
    sample_test_data()
    |> Map.fetch!(:constellations)
    |> Enum.map(&constellation_json/1)
  end

  @doc "Returns updated solar system fixture rows for refresh scenarios."
  @spec updated_solar_system_records() :: [map()]
  def updated_solar_system_records do
    updated_test_data()
    |> Map.fetch!(:solar_systems)
    |> Enum.map(&solar_system_json/1)
  end

  @doc "Returns updated item type fixture rows for refresh scenarios."
  @spec updated_item_type_records() :: [map()]
  def updated_item_type_records do
    updated_test_data()
    |> Map.fetch!(:item_types)
    |> Enum.map(&item_type_json/1)
  end

  @doc "Returns updated constellation fixture rows for refresh scenarios."
  @spec updated_constellation_records() :: [map()]
  def updated_constellation_records do
    updated_test_data()
    |> Map.fetch!(:constellations)
    |> Enum.map(&constellation_json/1)
  end

  @doc "Delegates to `DetsFile.dets_path/2` for test assertions on file paths."
  @spec dets_path(String.t(), atom()) :: String.t()
  def dets_path(dir, table_name), do: DetsFile.dets_path(dir, table_name)

  @doc "Encodes a solar system fixture struct as a World API-style map."
  @spec solar_system_json(SolarSystem.t()) :: map()
  def solar_system_json(%SolarSystem{} = solar_system) do
    %{
      "id" => solar_system.id,
      "name" => solar_system.name,
      "constellationId" => solar_system.constellation_id,
      "regionId" => solar_system.region_id,
      "location" => %{
        "x" => solar_system.x,
        "y" => solar_system.y,
        "z" => solar_system.z
      }
    }
  end

  @doc "Encodes an item type fixture struct as a World API-style map."
  @spec item_type_json(ItemType.t()) :: map()
  def item_type_json(%ItemType{} = item_type) do
    %{
      "id" => item_type.id,
      "name" => item_type.name,
      "description" => item_type.description,
      "mass" => item_type.mass,
      "radius" => item_type.radius,
      "volume" => item_type.volume,
      "portionSize" => item_type.portion_size,
      "groupName" => item_type.group_name,
      "groupId" => item_type.group_id,
      "categoryName" => item_type.category_name,
      "categoryId" => item_type.category_id,
      "iconUrl" => item_type.icon_url
    }
  end

  @doc "Encodes a constellation fixture struct as a World API-style map."
  @spec constellation_json(Constellation.t()) :: map()
  def constellation_json(%Constellation{} = constellation) do
    %{
      "id" => constellation.id,
      "name" => constellation.name,
      "regionId" => constellation.region_id,
      "location" => %{
        "x" => constellation.x,
        "y" => constellation.y,
        "z" => constellation.z
      },
      "solarSystems" => []
    }
  end

  defp write_rows!(path, rows) do
    {:ok, dets_ref} = DetsFile.open_file(path)

    :ok =
      rows
      |> Enum.map(fn row -> {row.id, row} end)
      |> then(&:dets.insert(dets_ref, &1))

    :ok = :dets.sync(dets_ref)
    :ok = :dets.close(dets_ref)
  end

  defp base_solar_system do
    %{
      id: 30_000_001,
      name: "A 2560",
      constellation_id: 20_000_001,
      region_id: 10_000_001,
      x: 1_111,
      y: 2_222,
      z: 3_333
    }
  end

  defp base_item_type do
    %{
      id: 72_244,
      name: "Feral Data",
      description: "Recovered datacore from frontier ruins",
      mass: 0.1,
      radius: 1.0,
      volume: 12.5,
      portion_size: 1,
      group_name: "Hull Repair Unit",
      group_id: 0,
      category_name: "Module",
      category_id: 7,
      icon_url: "https://images.example.test/72244.png"
    }
  end

  defp base_constellation do
    %{
      id: 20_000_001,
      name: "20000001",
      region_id: 10_000_001,
      x: 4_444,
      y: 5_555,
      z: 6_666
    }
  end
end
