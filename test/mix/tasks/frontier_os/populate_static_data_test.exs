defmodule Mix.Tasks.FrontierOs.PopulateStaticDataTest do
  @moduledoc """
  Covers the packet 3 static data population task contract from the approved spec.
  """

  use ExUnit.Case, async: true

  @moduletag timeout: 300_000

  alias FrontierOS.StaticDataTestFixtures, as: Fixtures

  setup do
    config_dir = Fixtures.ensure_tmp_dir!("populate_static_data_config")
    # Use a path that does NOT pre-exist — the task must create it
    output_dir = Fixtures.temp_dir("populate_static_data_output")

    on_exit(fn ->
      File.rm_rf(config_dir)
      File.rm_rf(output_dir)
    end)

    {:ok, config_dir: config_dir, output_dir: output_dir}
  end

  @tag :acceptance
  test "mix frontier_os.populate_static_data reports successful population to the user", %{
    config_dir: config_dir,
    output_dir: output_dir
  } do
    result =
      run_mix_populate_task!(config_dir, output_dir, [], :success)

    assert result.status == 0, result.output
    assert result.output =~ "FrontierOS Static Data Population"
    assert result.output =~ "Fetching item types..."

    assert result.output =~
             "Item Types: OK (2 records, #{Fixtures.dets_path(output_dir, :item_types)})"

    assert result.output =~ "Fetching solar systems..."

    assert result.output =~
             "Solar Systems: OK (2 records, #{Fixtures.dets_path(output_dir, :solar_systems)})"

    assert result.output =~ "Fetching constellations..."

    assert result.output =~
             "Constellations: OK (2 records, #{Fixtures.dets_path(output_dir, :constellations)})"

    assert result.output =~ "Done. 3/3 types populated successfully."
    refute result.output =~ "FAILED"
    refute result.output =~ "Unknown type"
    assert File.exists?(Fixtures.dets_path(output_dir, :item_types))
    assert File.exists?(Fixtures.dets_path(output_dir, :solar_systems))
    assert File.exists?(Fixtures.dets_path(output_dir, :constellations))
  end

  @tag :acceptance
  test "mix frontier_os.populate_static_data reports invalid --only values to the user", %{
    config_dir: config_dir,
    output_dir: output_dir
  } do
    result =
      run_mix_populate_task!(
        config_dir,
        output_dir,
        ["--only", "invalid_name"],
        :success
      )

    assert result.status != 0
    assert result.output =~ "Unknown type: invalid_name"
    assert result.output =~ "Valid: types, solar_systems, constellations"
    refute result.output =~ "Item Types: OK"
    refute result.output =~ "Done."
  end

  test "populates all three DETS files from WorldClient", %{
    config_dir: config_dir,
    output_dir: output_dir
  } do
    result =
      run_populate_task!(config_dir, output_dir, [], :success)

    assert result.status == 0, result.output
    assert File.exists?(Fixtures.dets_path(output_dir, :item_types))
    assert File.exists?(Fixtures.dets_path(output_dir, :solar_systems))
    assert File.exists?(Fixtures.dets_path(output_dir, :constellations))
  end

  test "--only flag restricts population to specified types", %{
    config_dir: config_dir,
    output_dir: output_dir
  } do
    result =
      run_populate_task!(
        config_dir,
        output_dir,
        ["--only", "types"],
        :success
      )

    assert result.status == 0, result.output
    assert File.exists?(Fixtures.dets_path(output_dir, :item_types))
    refute File.exists?(Fixtures.dets_path(output_dir, :solar_systems))
    refute File.exists?(Fixtures.dets_path(output_dir, :constellations))
  end

  test "--only accepts comma-separated list of types", %{
    config_dir: config_dir,
    output_dir: output_dir
  } do
    result =
      run_populate_task!(
        config_dir,
        output_dir,
        ["--only", "types,constellations"],
        :success
      )

    assert result.status == 0, result.output
    assert File.exists?(Fixtures.dets_path(output_dir, :item_types))
    assert File.exists?(Fixtures.dets_path(output_dir, :constellations))
    refute File.exists?(Fixtures.dets_path(output_dir, :solar_systems))
  end

  test "invalid --only value prints error with valid options", %{
    config_dir: config_dir,
    output_dir: output_dir
  } do
    result =
      run_populate_task!(
        config_dir,
        output_dir,
        ["--only", "invalid_name"],
        :success
      )

    assert result.status != 0
    assert result.output =~ "Unknown type: invalid_name"
    assert result.output =~ "Valid: types, solar_systems, constellations"
  end

  test "DETS files contain correctly parsed struct tuples", %{
    config_dir: config_dir,
    output_dir: output_dir
  } do
    result =
      run_populate_task!(config_dir, output_dir, [], :success)

    assert result.status == 0, result.output

    assert [{72_244, %FrontierOS.StaticData.ItemType{name: "Feral Data"}}] =
             read_dets!(Fixtures.dets_path(output_dir, :item_types), 72_244)

    assert [{30_000_001, %FrontierOS.StaticData.SolarSystem{name: "A 2560"}}] =
             read_dets!(Fixtures.dets_path(output_dir, :solar_systems), 30_000_001)

    assert [{20_000_001, %FrontierOS.StaticData.Constellation{name: "20000001"}}] =
             read_dets!(Fixtures.dets_path(output_dir, :constellations), 20_000_001)
  end

  test "re-running task overwrites existing DETS data", %{
    config_dir: config_dir,
    output_dir: output_dir
  } do
    first_result =
      run_populate_task!(config_dir, output_dir, [], :success)

    second_result =
      run_populate_task!(config_dir, output_dir, [], :updated)

    assert first_result.status == 0, first_result.output
    assert second_result.status == 0, second_result.output

    assert [{72_246, item_type}] = read_all_dets!(Fixtures.dets_path(output_dir, :item_types))
    assert item_type.name == "Reactive Plating"

    refute Enum.any?(read_all_dets!(Fixtures.dets_path(output_dir, :item_types)), fn {id,
                                                                                      _item_type} ->
             id == 72_244
           end)
  end

  @tag :acceptance
  test "mix frontier_os.populate_static_data reports partial failures", %{
    config_dir: config_dir,
    output_dir: output_dir
  } do
    result =
      run_mix_populate_task!(
        config_dir,
        output_dir,
        [],
        :partial_failure
      )

    assert result.status == 0, result.output
    assert File.exists?(Fixtures.dets_path(output_dir, :item_types))
    assert File.exists?(Fixtures.dets_path(output_dir, :constellations))
    refute File.exists?(Fixtures.dets_path(output_dir, :solar_systems))

    assert result.output =~
             "Item Types: OK (2 records, #{Fixtures.dets_path(output_dir, :item_types)})"

    assert result.output =~ "Solar Systems: FAILED (:timeout)"

    assert result.output =~
             "Constellations: OK (2 records, #{Fixtures.dets_path(output_dir, :constellations)})"

    assert result.output =~ "Done. 2/3 types populated successfully."
    assert result.output =~ "Run with --only solar_systems to retry failed types."
    refute result.output =~ "Done. 3/3 types populated successfully."
  end

  test "creates output directory if it does not exist", %{
    config_dir: config_dir,
    output_dir: output_dir
  } do
    refute File.exists?(output_dir)

    result =
      run_populate_task!(config_dir, output_dir, [], :success)

    assert result.status == 0, result.output
    assert File.dir?(output_dir)
    assert File.exists?(Fixtures.dets_path(output_dir, :item_types))
    assert File.exists?(Fixtures.dets_path(output_dir, :solar_systems))
    assert File.exists?(Fixtures.dets_path(output_dir, :constellations))
  end

  defp run_populate_task!(config_dir, output_dir, args, mock_scenario) do
    config_path = Fixtures.write_populate_static_data_config!(config_dir, output_dir)
    mock_script = world_client_setup_script(mock_scenario)

    script = """
    import Hammox

    {:ok, _mox_apps} = Application.ensure_all_started(:mox)
    Mox.set_mox_global()

    #{mock_script}

    Mix.Tasks.FrontierOs.PopulateStaticData.run(#{inspect(args)})
    """

    {output, status} =
      System.cmd("mix", Fixtures.mix_run_args(config_path, script, no_start: true),
        cd: project_root(),
        env: [{"MIX_ENV", "test"}],
        stderr_to_stdout: true
      )

    %{output: output, status: status}
  end

  defp run_mix_populate_task!(config_dir, output_dir, args, mock_scenario) do
    config_path = Fixtures.write_populate_static_data_config!(config_dir, output_dir)
    mock_script = world_client_setup_script(mock_scenario)

    {output, status} =
      System.cmd(
        "mix",
        [
          "do",
          "loadconfig",
          config_path,
          "+",
          "run",
          "--no-compile",
          "-e",
          mock_script,
          "+",
          "frontier_os.populate_static_data"
          | args
        ],
        cd: project_root(),
        env: [{"MIX_ENV", "test"}],
        stderr_to_stdout: true
      )

    %{output: output, status: status}
  end

  defp world_client_setup_script(:success) do
    """
    import Hammox

    {:ok, _mox_apps} = Application.ensure_all_started(:mox)
    Mox.set_mox_global()

    stub(FrontierOS.StaticData.WorldClientMock, :fetch_types, fn _opts ->
      {:ok, FrontierOS.StaticDataTestFixtures.item_type_records()}
    end)

    stub(FrontierOS.StaticData.WorldClientMock, :fetch_solar_systems, fn _opts ->
      {:ok, FrontierOS.StaticDataTestFixtures.solar_system_records()}
    end)

    stub(FrontierOS.StaticData.WorldClientMock, :fetch_constellations, fn _opts ->
      {:ok, FrontierOS.StaticDataTestFixtures.constellation_records()}
    end)
    """
  end

  defp world_client_setup_script(:updated) do
    """
    import Hammox

    {:ok, _mox_apps} = Application.ensure_all_started(:mox)
    Mox.set_mox_global()

    stub(FrontierOS.StaticData.WorldClientMock, :fetch_types, fn _opts ->
      {:ok, FrontierOS.StaticDataTestFixtures.updated_item_type_records()}
    end)

    stub(FrontierOS.StaticData.WorldClientMock, :fetch_solar_systems, fn _opts ->
      {:ok, FrontierOS.StaticDataTestFixtures.updated_solar_system_records()}
    end)

    stub(FrontierOS.StaticData.WorldClientMock, :fetch_constellations, fn _opts ->
      {:ok, FrontierOS.StaticDataTestFixtures.updated_constellation_records()}
    end)
    """
  end

  defp world_client_setup_script(:partial_failure) do
    """
    import Hammox

    {:ok, _mox_apps} = Application.ensure_all_started(:mox)
    Mox.set_mox_global()

    stub(FrontierOS.StaticData.WorldClientMock, :fetch_types, fn _opts ->
      {:ok, FrontierOS.StaticDataTestFixtures.item_type_records()}
    end)

    stub(FrontierOS.StaticData.WorldClientMock, :fetch_solar_systems, fn _opts ->
      {:error, :timeout}
    end)

    stub(FrontierOS.StaticData.WorldClientMock, :fetch_constellations, fn _opts ->
      {:ok, FrontierOS.StaticDataTestFixtures.constellation_records()}
    end)
    """
  end

  defp project_root do
    Path.expand("../../../..", __DIR__)
  end

  defp read_all_dets!(path) do
    {:ok, dets_ref} = FrontierOS.StaticData.DetsFile.open_file(path)

    rows =
      :dets.foldl(fn row, acc -> [row | acc] end, [], dets_ref)
      |> Enum.sort_by(&elem(&1, 0))

    :ok = :dets.close(dets_ref)
    rows
  end

  defp read_dets!(path, key) do
    {:ok, dets_ref} = FrontierOS.StaticData.DetsFile.open_file(path)
    rows = :dets.lookup(dets_ref, key)
    :ok = :dets.close(dets_ref)
    rows
  end
end
