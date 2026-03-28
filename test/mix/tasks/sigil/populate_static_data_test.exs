defmodule Mix.Tasks.Sigil.PopulateStaticDataTest do
  @moduledoc """
  Covers the packet 3 static data population task contract from the approved spec.
  """

  use ExUnit.Case, async: true

  import Hammox

  alias Sigil.StaticData.WorldClientMock
  alias Sigil.StaticDataTestFixtures, as: Fixtures

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
  test "mix sigil.populate_static_data reports successful population to the user", %{
    config_dir: config_dir,
    output_dir: output_dir
  } do
    result =
      run_mix_populate_task!(
        config_dir,
        output_dir,
        [],
        :success
      )

    assert result.status == 0, result.output
    assert File.exists?(Fixtures.dets_path(output_dir, :item_types))
    assert File.exists?(Fixtures.dets_path(output_dir, :solar_systems))
    assert File.exists?(Fixtures.dets_path(output_dir, :constellations))

    assert result.output =~
             "Item Types: OK (2 records, #{Fixtures.dets_path(output_dir, :item_types)})"

    assert result.output =~
             "Solar Systems: OK (2 records, #{Fixtures.dets_path(output_dir, :solar_systems)})"

    assert result.output =~
             "Constellations: OK (2 records, #{Fixtures.dets_path(output_dir, :constellations)})"

    assert result.output =~ "Done. 3/3 types populated successfully."
    refute result.output =~ "retry"
  end

  @tag :acceptance
  test "mix sigil.populate_static_data reports invalid --only values to the user", %{
    config_dir: config_dir,
    output_dir: output_dir
  } do
    result =
      run_mix_populate_task!(
        config_dir,
        output_dir,
        ["--only", "bogus_value"],
        :success
      )

    assert result.status != 0
    assert result.output =~ "Unknown type: bogus_value"
    assert result.output =~ "Valid: types, solar_systems, constellations"
    refute result.output =~ "Done."
  end

  test "populates all three DETS files from WorldClient", %{output_dir: output_dir} do
    stub_world_client!(:success)

    run_task!([], output_dir)

    assert File.exists?(Fixtures.dets_path(output_dir, :item_types))
    assert File.exists?(Fixtures.dets_path(output_dir, :solar_systems))
    assert File.exists?(Fixtures.dets_path(output_dir, :constellations))
  end

  test "--only flag restricts population to specified types", %{output_dir: output_dir} do
    stub_world_client!(:success)

    run_task!(["--only", "types"], output_dir)

    assert File.exists?(Fixtures.dets_path(output_dir, :item_types))
    refute File.exists?(Fixtures.dets_path(output_dir, :solar_systems))
    refute File.exists?(Fixtures.dets_path(output_dir, :constellations))
  end

  test "--only accepts comma-separated list of types", %{output_dir: output_dir} do
    stub_world_client!(:success)

    run_task!(["--only", "types,constellations"], output_dir)

    assert File.exists?(Fixtures.dets_path(output_dir, :item_types))
    assert File.exists?(Fixtures.dets_path(output_dir, :constellations))
    refute File.exists?(Fixtures.dets_path(output_dir, :solar_systems))
  end

  test "invalid --only value prints error with valid options", %{output_dir: output_dir} do
    stub_world_client!(:success)

    error =
      assert_raise Mix.Error, fn ->
        run_task!(["--only", "invalid_name"], output_dir)
      end

    assert error.message =~ "Unknown type: invalid_name"
    assert error.message =~ "Valid: types, solar_systems, constellations"
  end

  test "DETS files contain correctly parsed struct tuples", %{output_dir: output_dir} do
    stub_world_client!(:success)

    run_task!([], output_dir)

    assert [{72_244, %Sigil.StaticData.ItemType{name: "Feral Data"}}] =
             read_dets!(Fixtures.dets_path(output_dir, :item_types), 72_244)

    assert [{30_000_001, %Sigil.StaticData.SolarSystem{name: "A 2560"}}] =
             read_dets!(Fixtures.dets_path(output_dir, :solar_systems), 30_000_001)

    assert [{20_000_001, %Sigil.StaticData.Constellation{name: "20000001"}}] =
             read_dets!(Fixtures.dets_path(output_dir, :constellations), 20_000_001)
  end

  test "re-running task overwrites existing DETS data", %{output_dir: output_dir} do
    stub_world_client!(:success)
    run_task!([], output_dir)

    stub_world_client!(:updated)
    run_task!([], output_dir)

    assert [{72_246, item_type}] = read_all_dets!(Fixtures.dets_path(output_dir, :item_types))
    assert item_type.name == "Reactive Plating"

    refute Enum.any?(read_all_dets!(Fixtures.dets_path(output_dir, :item_types)), fn {id,
                                                                                      _item_type} ->
             id == 72_244
           end)
  end

  @tag :acceptance
  test "mix sigil.populate_static_data reports partial failures", %{
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

  test "creates output directory if it does not exist", %{output_dir: output_dir} do
    refute File.exists?(output_dir)

    stub_world_client!(:success)
    run_task!([], output_dir)

    assert File.dir?(output_dir)
    assert File.exists?(Fixtures.dets_path(output_dir, :item_types))
    assert File.exists?(Fixtures.dets_path(output_dir, :solar_systems))
    assert File.exists?(Fixtures.dets_path(output_dir, :constellations))
  end

  # ---------------------------------------------------------------------------
  # In-process helpers (no subprocess)
  # ---------------------------------------------------------------------------

  defp run_task!(args, output_dir) do
    ExUnit.CaptureIO.capture_io(fn ->
      Mix.Tasks.Sigil.PopulateStaticData.run(args,
        output_dir: output_dir,
        world_client: WorldClientMock
      )
    end)
  end

  defp stub_world_client!(:success) do
    stub(WorldClientMock, :fetch_types, fn _opts ->
      {:ok, Fixtures.item_type_records()}
    end)

    stub(WorldClientMock, :fetch_solar_systems, fn _opts ->
      {:ok, Fixtures.solar_system_records()}
    end)

    stub(WorldClientMock, :fetch_constellations, fn _opts ->
      {:ok, Fixtures.constellation_records()}
    end)
  end

  defp stub_world_client!(:updated) do
    stub(WorldClientMock, :fetch_types, fn _opts ->
      {:ok, Fixtures.updated_item_type_records()}
    end)

    stub(WorldClientMock, :fetch_solar_systems, fn _opts ->
      {:ok, Fixtures.updated_solar_system_records()}
    end)

    stub(WorldClientMock, :fetch_constellations, fn _opts ->
      {:ok, Fixtures.updated_constellation_records()}
    end)
  end

  # ---------------------------------------------------------------------------
  # Subprocess helpers (acceptance tests only)
  # ---------------------------------------------------------------------------

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
          "--no-deps-check",
          "--no-archives-check",
          "-e",
          mock_script,
          "+",
          "sigil.populate_static_data"
          | args
        ],
        cd: project_root(),
        env: [{"MIX_ENV", "test"}] ++ Fixtures.mix_subprocess_env("populate_static_data_mix"),
        stderr_to_stdout: true
      )

    %{output: output, status: status}
  end

  defp world_client_setup_script(:success) do
    """
    import Hammox

    {:ok, _mox_apps} = Application.ensure_all_started(:mox)
    Mox.set_mox_global()

    stub(Sigil.StaticData.WorldClientMock, :fetch_types, fn _opts ->
      {:ok, Sigil.StaticDataTestFixtures.item_type_records()}
    end)

    stub(Sigil.StaticData.WorldClientMock, :fetch_solar_systems, fn _opts ->
      {:ok, Sigil.StaticDataTestFixtures.solar_system_records()}
    end)

    stub(Sigil.StaticData.WorldClientMock, :fetch_constellations, fn _opts ->
      {:ok, Sigil.StaticDataTestFixtures.constellation_records()}
    end)
    """
  end

  defp world_client_setup_script(:partial_failure) do
    """
    import Hammox

    {:ok, _mox_apps} = Application.ensure_all_started(:mox)
    Mox.set_mox_global()

    stub(Sigil.StaticData.WorldClientMock, :fetch_types, fn _opts ->
      {:ok, Sigil.StaticDataTestFixtures.item_type_records()}
    end)

    stub(Sigil.StaticData.WorldClientMock, :fetch_solar_systems, fn _opts ->
      {:error, :timeout}
    end)

    stub(Sigil.StaticData.WorldClientMock, :fetch_constellations, fn _opts ->
      {:ok, Sigil.StaticDataTestFixtures.constellation_records()}
    end)
    """
  end

  defp project_root do
    Path.expand("../../../..", __DIR__)
  end

  defp read_all_dets!(path) do
    {:ok, dets_ref} = Sigil.StaticData.DetsFile.open_file(path)

    rows =
      :dets.foldl(fn row, acc -> [row | acc] end, [], dets_ref)
      |> Enum.sort_by(&elem(&1, 0))

    :ok = :dets.close(dets_ref)
    rows
  end

  defp read_dets!(path, key) do
    {:ok, dets_ref} = Sigil.StaticData.DetsFile.open_file(path)
    rows = :dets.lookup(dets_ref, key)
    :ok = :dets.close(dets_ref)
    rows
  end
end
