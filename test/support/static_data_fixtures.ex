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

  @spec temp_dir(String.t()) :: String.t()
  def temp_dir(prefix) do
    Path.join([
      System.tmp_dir!(),
      "sigil_tests",
      prefix <> "_" <> Integer.to_string(System.unique_integer([:positive]))
    ])
  end

  @spec ensure_tmp_dir!(String.t()) :: String.t()
  def ensure_tmp_dir!(prefix) do
    dir = temp_dir(prefix)
    File.mkdir_p!(dir)
    dir
  end

  @spec write_application_probe_config!(String.t(), keyword()) :: String.t()
  def write_application_probe_config!(config_dir, opts) do
    start_static_data = Keyword.get(opts, :start_static_data, false)
    static_data_dir = Keyword.fetch!(opts, :static_data_dir)
    world_client = Keyword.fetch!(opts, :world_client)
    config_path = Path.join(config_dir, "application_probe_config.exs")

    File.write!(
      config_path,
      """
      import Config

      config :sigil, :start_static_data, #{inspect(start_static_data)}
      config :sigil, :static_data_dir, #{inspect(static_data_dir)}
      config :sigil, :world_client, #{inspect(world_client)}
      """
    )

    config_path
  end

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
      ["--no-compile"] ++
        if Keyword.get(opts, :no_start, false), do: ["--no-start"], else: []

    ["do", "loadconfig", Path.expand(config_path), "+", "run"] ++ run_flags ++ ["-e", script]
  end

  @spec write_dets_fixture!(String.t(), static_data()) :: :ok
  def write_dets_fixture!(dets_dir, data) do
    File.mkdir_p!(dets_dir)
    write_rows!(dets_path(dets_dir, :solar_systems), data.solar_systems)
    write_rows!(dets_path(dets_dir, :item_types), data.item_types)
    write_rows!(dets_path(dets_dir, :constellations), data.constellations)
  end

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

  @spec updated_test_data() :: static_data()
  def updated_test_data do
    %{
      solar_systems: [solar_system_struct(%{id: 30_000_003, name: "C 9000"})],
      item_types: [item_type_struct(%{id: 72_246, name: "Reactive Plating"})],
      constellations: [constellation_struct(%{id: 20_000_003, name: "20000003"})]
    }
  end

  @spec solar_system_struct(map()) :: SolarSystem.t()
  def solar_system_struct(overrides \\ %{}) do
    struct!(SolarSystem, Map.merge(base_solar_system(), overrides))
  end

  @spec item_type_struct(map()) :: ItemType.t()
  def item_type_struct(overrides \\ %{}) do
    struct!(ItemType, Map.merge(base_item_type(), overrides))
  end

  @spec constellation_struct(map()) :: Constellation.t()
  def constellation_struct(overrides \\ %{}) do
    struct!(Constellation, Map.merge(base_constellation(), overrides))
  end

  @spec solar_system_records() :: [map()]
  def solar_system_records do
    sample_test_data()
    |> Map.fetch!(:solar_systems)
    |> Enum.map(&solar_system_json/1)
  end

  @spec item_type_records() :: [map()]
  def item_type_records do
    sample_test_data()
    |> Map.fetch!(:item_types)
    |> Enum.map(&item_type_json/1)
  end

  @spec constellation_records() :: [map()]
  def constellation_records do
    sample_test_data()
    |> Map.fetch!(:constellations)
    |> Enum.map(&constellation_json/1)
  end

  @spec updated_solar_system_records() :: [map()]
  def updated_solar_system_records do
    updated_test_data()
    |> Map.fetch!(:solar_systems)
    |> Enum.map(&solar_system_json/1)
  end

  @spec updated_item_type_records() :: [map()]
  def updated_item_type_records do
    updated_test_data()
    |> Map.fetch!(:item_types)
    |> Enum.map(&item_type_json/1)
  end

  @spec updated_constellation_records() :: [map()]
  def updated_constellation_records do
    updated_test_data()
    |> Map.fetch!(:constellations)
    |> Enum.map(&constellation_json/1)
  end

  @doc "Delegates to `DetsFile.dets_path/2` for test assertions on file paths."
  @spec dets_path(String.t(), atom()) :: String.t()
  def dets_path(dir, table_name), do: DetsFile.dets_path(dir, table_name)

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
    {:ok, dets_ref} = Sigil.StaticData.DetsFile.open_file(path)

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
