defmodule Sigil.StaticDataTest do
  @moduledoc """
  Covers the packet 3 static data store contract from the approved spec.
  """

  use ExUnit.Case, async: true

  import Hammox

  @compile {:no_warn_undefined, Sigil.StaticData}

  alias Sigil.StaticData
  alias Sigil.StaticData.Constellation
  alias Sigil.StaticData.ItemType
  alias Sigil.StaticData.SolarSystem
  alias Sigil.StaticData.WorldClientMock
  alias Sigil.StaticDataTestFixtures, as: Fixtures

  setup :set_mox_from_context
  setup :verify_on_exit!

  describe "read API via test_data" do
    test "get_solar_system/2 returns struct for existing ID" do
      pid = start_static_data!(test_data: Fixtures.sample_test_data())

      assert %SolarSystem{id: 30_000_001, name: "A 2560"} =
               StaticData.get_solar_system(pid, 30_000_001)
    end

    test "get_solar_system/2 returns nil for unknown ID" do
      pid = start_static_data!(test_data: Fixtures.sample_test_data())

      assert StaticData.get_solar_system(pid, -1) == nil
    end

    test "list_solar_systems/1 returns all stored solar systems" do
      pid = start_static_data!(test_data: Fixtures.sample_test_data())

      assert pid
             |> StaticData.list_solar_systems()
             |> Enum.map(& &1.id)
             |> Enum.sort() == [30_000_001, 30_000_002]
    end

    test "search_solar_systems finds systems by name prefix" do
      pid =
        start_static_data!(
          test_data: %{
            solar_systems: [
              Fixtures.solar_system_struct(%{id: 30_000_001, name: "A 2560"}),
              Fixtures.solar_system_struct(%{id: 30_000_002, name: "A 2561"}),
              Fixtures.solar_system_struct(%{id: 30_000_003, name: "B 31337"})
            ]
          }
        )

      assert pid
             |> StaticData.search_solar_systems("A 25")
             |> Enum.map(& &1.name) == ["A 2560", "A 2561"]
    end

    test "search_solar_systems respects limit parameter" do
      pid =
        start_static_data!(
          test_data: %{
            solar_systems: [
              Fixtures.solar_system_struct(%{id: 30_000_011, name: "A 2500"}),
              Fixtures.solar_system_struct(%{id: 30_000_012, name: "A 2510"}),
              Fixtures.solar_system_struct(%{id: 30_000_013, name: "A 2520"})
            ]
          }
        )

      assert pid
             |> StaticData.search_solar_systems("A 25", 2)
             |> Enum.map(& &1.name) == ["A 2500", "A 2510"]
    end

    test "search_solar_systems returns empty list for no matches" do
      pid = start_static_data!(test_data: Fixtures.sample_test_data())

      assert StaticData.search_solar_systems(pid, "Z 9999") == []
    end

    test "search_solar_systems is case-insensitive" do
      pid = start_static_data!(test_data: Fixtures.sample_test_data())

      assert pid
             |> StaticData.search_solar_systems("a 25")
             |> Enum.map(& &1.name) == ["A 2560"]
    end

    test "get_solar_system_by_name returns unique exact match" do
      pid = start_static_data!(test_data: Fixtures.sample_test_data())

      assert %SolarSystem{id: 30_000_001, name: "A 2560"} =
               StaticData.get_solar_system_by_name(pid, "a 2560")
    end

    test "get_solar_system_by_name returns nil for unknown or ambiguous name" do
      pid =
        start_static_data!(
          test_data: %{
            solar_systems: [
              Fixtures.solar_system_struct(%{id: 30_000_021, name: "A 2560"}),
              Fixtures.solar_system_struct(%{id: 30_000_022, name: "a 2560"}),
              Fixtures.solar_system_struct(%{id: 30_000_023, name: "B 31337"})
            ]
          }
        )

      assert StaticData.get_solar_system_by_name(pid, "Z 9999") == nil
      assert StaticData.get_solar_system_by_name(pid, "A 2560") == nil
    end

    test "get_item_type/2 returns struct for existing ID" do
      pid = start_static_data!(test_data: Fixtures.sample_test_data())

      assert %ItemType{id: 72_244, name: "Feral Data"} =
               StaticData.get_item_type(pid, 72_244)
    end

    test "get_item_type/2 returns nil for unknown ID" do
      pid = start_static_data!(test_data: Fixtures.sample_test_data())

      assert StaticData.get_item_type(pid, -1) == nil
    end

    test "list_item_types/1 returns all stored item types" do
      pid = start_static_data!(test_data: Fixtures.sample_test_data())

      assert pid
             |> StaticData.list_item_types()
             |> Enum.map(& &1.id)
             |> Enum.sort() == [72_244, 72_245]
    end

    test "get_constellation/2 returns struct for existing ID" do
      pid = start_static_data!(test_data: Fixtures.sample_test_data())

      assert %Constellation{id: 20_000_001, name: "20000001"} =
               StaticData.get_constellation(pid, 20_000_001)
    end

    test "get_constellation/2 returns nil for unknown ID" do
      pid = start_static_data!(test_data: Fixtures.sample_test_data())

      assert StaticData.get_constellation(pid, -1) == nil
    end

    test "list_constellations/1 returns all stored constellations" do
      pid = start_static_data!(test_data: Fixtures.sample_test_data())

      assert pid
             |> StaticData.list_constellations()
             |> Enum.map(& &1.id)
             |> Enum.sort() == [20_000_001, 20_000_002]
    end

    test "test_data option loads from in-memory data without DETS" do
      dets_dir = temp_dir!("static_data_bypass")
      pid = start_static_data!(dets_dir: dets_dir, test_data: Fixtures.sample_test_data())

      assert %SolarSystem{id: 30_000_001} = StaticData.get_solar_system(pid, 30_000_001)
      refute File.exists?(Fixtures.dets_path(dets_dir, :solar_systems))
      refute File.exists?(Fixtures.dets_path(dets_dir, :item_types))
      refute File.exists?(Fixtures.dets_path(dets_dir, :constellations))
    end

    test "tables/1 returns map of table references" do
      pid = start_static_data!(test_data: Fixtures.sample_test_data())
      tables = StaticData.tables(pid)

      assert Map.keys(tables) |> Enum.sort() == [:constellations, :item_types, :solar_systems]

      assert Enum.all?(tables, fn {_name, tid} ->
               is_reference(tid) and :set == :ets.info(tid, :type)
             end)
    end

    test "separate StaticData instances have isolated data" do
      left_pid =
        start_static_data!(
          test_data: %{
            solar_systems: [Fixtures.solar_system_struct(%{id: 30_000_101, name: "Left"})],
            item_types: [Fixtures.item_type_struct(%{id: 72_301, name: "Left Item"})],
            constellations: [
              Fixtures.constellation_struct(%{id: 20_000_101, name: "Left Constellation"})
            ]
          }
        )

      right_pid =
        start_static_data!(
          test_data: %{
            solar_systems: [Fixtures.solar_system_struct(%{id: 30_000_202, name: "Right"})],
            item_types: [Fixtures.item_type_struct(%{id: 72_302, name: "Right Item"})],
            constellations: [
              Fixtures.constellation_struct(%{id: 20_000_202, name: "Right Constellation"})
            ]
          }
        )

      assert %SolarSystem{name: "Left"} = StaticData.get_solar_system(left_pid, 30_000_101)
      assert StaticData.get_solar_system(left_pid, 30_000_202) == nil
      assert %SolarSystem{name: "Right"} = StaticData.get_solar_system(right_pid, 30_000_202)
      assert StaticData.get_solar_system(right_pid, 30_000_101) == nil
    end
  end

  describe "DETS loading and auto-fetch" do
    test "loads data from DETS files into ETS on startup" do
      dets_dir = temp_dir!("static_data_loads")
      Fixtures.write_dets_fixture!(dets_dir, Fixtures.sample_test_data())

      pid = start_static_data!(dets_dir: dets_dir)

      assert %SolarSystem{id: 30_000_001} = StaticData.get_solar_system(pid, 30_000_001)
      assert %ItemType{id: 72_244} = StaticData.get_item_type(pid, 72_244)
      assert %Constellation{id: 20_000_001} = StaticData.get_constellation(pid, 20_000_001)
    end

    test "DETS tables are closed after init completes" do
      dets_dir = temp_dir!("static_data_dets_closed")
      Fixtures.write_dets_fixture!(dets_dir, Fixtures.sample_test_data())

      pid = start_static_data!(dets_dir: dets_dir)
      _tables = StaticData.tables(pid)

      open_tables_for_dir =
        :dets.all()
        |> Enum.filter(fn table_name ->
          table_name
          |> :dets.info(:filename)
          |> dets_path_in_dir?(dets_dir)
        end)

      assert open_tables_for_dir == []
    end

    test "ETS tables are destroyed when GenServer stops" do
      pid = start_static_data!(test_data: Fixtures.sample_test_data())
      tid = Map.fetch!(StaticData.tables(pid), :solar_systems)
      monitor_ref = Process.monitor(pid)

      assert :ok = GenServer.stop(pid, :normal, :infinity)

      assert_receive {:DOWN, ^monitor_ref, :process, ^pid, reason}
      assert clean_shutdown?(reason)

      assert_raise ArgumentError, fn ->
        :ets.lookup(tid, 30_000_001)
      end
    end

    test "auto-fetches from WorldClient when DETS files are missing" do
      dets_dir = temp_dir!("static_data_auto_fetch")
      stub_world_client!(:success)

      pid =
        start_static_data!(
          dets_dir: dets_dir,
          world_client: WorldClientMock
        )

      assert %SolarSystem{id: 30_000_001} = StaticData.get_solar_system(pid, 30_000_001)
      assert File.exists?(Fixtures.dets_path(dets_dir, :solar_systems))
      assert File.exists?(Fixtures.dets_path(dets_dir, :item_types))
      assert File.exists?(Fixtures.dets_path(dets_dir, :constellations))
    end

    test "auto-fetch creates DETS files that persist for future starts" do
      dets_dir = temp_dir!("static_data_persisted")
      stub_world_client!(:success)

      first_pid =
        start_static_data!(
          dets_dir: dets_dir,
          world_client: WorldClientMock
        )

      assert %ItemType{id: 72_244, name: "Feral Data"} =
               StaticData.get_item_type(first_pid, 72_244)

      assert :ok = GenServer.stop(first_pid, :normal, :infinity)

      second_pid = start_static_data!(dets_dir: dets_dir)

      assert %ItemType{id: 72_244, name: "Feral Data"} =
               StaticData.get_item_type(second_pid, 72_244)
    end

    test "starts with empty tables when auto-fetch fails" do
      dets_dir = temp_dir!("static_data_fetch_failure")
      stub_world_client!(:failure)

      pid =
        start_static_data!(
          dets_dir: dets_dir,
          world_client: WorldClientMock
        )

      assert StaticData.list_solar_systems(pid) == []
      assert StaticData.list_item_types(pid) == []
      assert StaticData.list_constellations(pid) == []
    end
  end

  defp start_static_data!(opts) do
    start_supervised!({StaticData, opts})
  end

  defp temp_dir!(prefix) do
    dir = Fixtures.ensure_tmp_dir!(prefix)
    on_exit(fn -> File.rm_rf(dir) end)
    dir
  end

  defp stub_world_client!(:success) do
    stub(WorldClientMock, :fetch_types, fn _opts -> {:ok, Fixtures.item_type_records()} end)

    stub(WorldClientMock, :fetch_solar_systems, fn _opts ->
      {:ok, Fixtures.solar_system_records()}
    end)

    stub(WorldClientMock, :fetch_constellations, fn _opts ->
      {:ok, Fixtures.constellation_records()}
    end)
  end

  defp stub_world_client!(:failure) do
    stub(WorldClientMock, :fetch_types, fn _opts -> {:error, :timeout} end)
    stub(WorldClientMock, :fetch_solar_systems, fn _opts -> {:error, :timeout} end)
    stub(WorldClientMock, :fetch_constellations, fn _opts -> {:error, :timeout} end)
  end

  @spec dets_path_in_dir?(term(), String.t()) :: boolean()
  defp dets_path_in_dir?(filename, dir) when is_list(filename) do
    expanded_dir = Path.expand(dir) <> "/"

    filename
    |> List.to_string()
    |> Path.expand()
    |> String.starts_with?(expanded_dir)
  end

  defp dets_path_in_dir?(_filename, _dir), do: false

  defp clean_shutdown?(:normal), do: true
  defp clean_shutdown?(:shutdown), do: true
  defp clean_shutdown?({:shutdown, _reason}), do: true
  defp clean_shutdown?(:noproc), do: true
  defp clean_shutdown?(_reason), do: false
end
