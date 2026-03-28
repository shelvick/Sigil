defmodule Sigil.ApplicationTest do
  @moduledoc """
  Captures the application supervision-tree contract.
  """

  use ExUnit.Case, async: true

  alias Sigil.Cache
  alias Sigil.StaticDataTestFixtures, as: Fixtures

  @default_monitor_registry Sigil.GameState.MonitorRegistry

  test "application starts all required children" do
    snapshot = running_application_snapshot!()

    assert inspect(SigilWeb.Telemetry) in snapshot.child_ids
    assert inspect(Sigil.Repo) in snapshot.child_ids
    assert inspect(Phoenix.PubSub.Supervisor) in snapshot.child_ids
    assert inspect(Sigil.Cache) in snapshot.child_ids
    assert inspect(SigilWeb.Endpoint) in snapshot.child_ids
  end

  test "supervision tree includes Cache process" do
    snapshot = running_application_snapshot!()

    assert inspect(Sigil.Cache) in snapshot.child_ids
  end

  test "StaticData and GateIndexer start when config flags enabled" do
    enabled = configured_application_snapshot!(start_static_data: true, start_gate_indexer: true)

    assert enabled.static_data_running
    assert enabled.static_data_resolved
    assert enabled.gate_indexer_running
    assert enabled.gate_network_table_valid
  end

  test "CacheResolver finds StaticData pid when enabled" do
    snapshot = configured_application_snapshot!(start_static_data: true)

    assert snapshot.static_data_running
    assert snapshot.static_data_resolved
  end

  test "StaticData and GateIndexer absent when config flags disabled" do
    disabled =
      configured_application_snapshot!(start_static_data: false, start_gate_indexer: false)

    assert inspect(Sigil.Cache) in disabled.child_ids
    refute disabled.static_data_running
    refute inspect(Sigil.StaticData) in disabled.child_ids
    refute disabled.gate_indexer_running
    refute inspect(Sigil.GateIndexer) in disabled.child_ids
  end

  test "Cache child precedes Endpoint in supervision tree" do
    snapshot = running_application_snapshot!()
    child_ids_in_start_order = Enum.reverse(snapshot.child_ids)

    assert index_of(child_ids_in_start_order, inspect(Sigil.Cache)) <
             index_of(child_ids_in_start_order, inspect(SigilWeb.Endpoint))
  end

  test "supervision tree includes MonitorRegistry when enabled" do
    snapshot = configured_application_snapshot!(start_monitor_supervisor: true)

    assert snapshot.monitor_registry_running
  end

  test "supervision tree includes MonitorSupervisor when enabled" do
    snapshot = configured_application_snapshot!(start_monitor_supervisor: true)

    assert snapshot.monitor_supervisor_running
  end

  test "MonitorSupervisor excluded when config is false" do
    snapshot = configured_application_snapshot!(start_monitor_supervisor: false)

    refute snapshot.monitor_registry_running
    refute snapshot.monitor_supervisor_running
    refute inspect(@default_monitor_registry) in snapshot.child_ids
    refute inspect(Sigil.GameState.MonitorSupervisor) in snapshot.child_ids
  end

  test "MonitorSupervisor precedes Endpoint in supervision tree" do
    snapshot = configured_application_snapshot!(start_monitor_supervisor: true)
    child_ids_in_start_order = Enum.reverse(snapshot.child_ids)

    assert index_of(child_ids_in_start_order, inspect(@default_monitor_registry)) <
             index_of(child_ids_in_start_order, inspect(SigilWeb.Endpoint))

    assert index_of(child_ids_in_start_order, inspect(Sigil.GameState.MonitorSupervisor)) <
             index_of(child_ids_in_start_order, inspect(SigilWeb.Endpoint))
  end

  test "supervision tree includes AlertEngine when enabled" do
    snapshot =
      configured_application_snapshot!(start_monitor_supervisor: false, start_alert_engine: true)

    assert snapshot.alert_engine_running
    assert inspect(Sigil.Alerts.Engine) in snapshot.child_ids
  end

  test "MonitorRegistry and MonitorSupervisor precede AlertEngine when enabled" do
    snapshot =
      configured_application_snapshot!(start_monitor_supervisor: true, start_alert_engine: true)

    # which_children returns reverse start order: higher index = started earlier
    assert is_integer(snapshot.alert_engine_index)
    assert snapshot.monitor_registry_index > snapshot.alert_engine_index
    assert snapshot.monitor_supervisor_index > snapshot.alert_engine_index
  end

  test "AlertEngine precedes Endpoint when enabled" do
    snapshot =
      configured_application_snapshot!(start_monitor_supervisor: true, start_alert_engine: true)

    # which_children returns reverse start order: higher index = started earlier
    assert is_integer(snapshot.alert_engine_index)
    assert snapshot.alert_engine_index > snapshot.endpoint_index
  end

  test "Cache includes gate_network table" do
    tables = application_cache_tables!()
    gate_network_table = Map.fetch!(tables, :gate_network)

    assert :gate_network in Map.keys(tables)
    assert :ets.info(gate_network_table) != :undefined
  end

  test "AlertEngine excluded when config is false" do
    # First verify the enabled case works (ensures this test fails when feature is missing)
    enabled_snapshot =
      configured_application_snapshot!(start_monitor_supervisor: true, start_alert_engine: true)

    assert enabled_snapshot.alert_engine_running

    # Then verify the disabled case excludes it
    disabled_snapshot =
      configured_application_snapshot!(start_monitor_supervisor: true, start_alert_engine: false)

    refute disabled_snapshot.alert_engine_running
    refute inspect(Sigil.Alerts.Engine) in disabled_snapshot.child_ids
  end

  test "Cache includes intel table" do
    tables = application_cache_tables!()
    intel_table = Map.fetch!(tables, :intel)

    assert :intel in Map.keys(tables)
    assert :ets.info(intel_table) != :undefined
  end

  test "application cache includes nonce table" do
    children = Supervisor.which_children(Sigil.Supervisor)

    {_id, cache_pid, _kind, _modules} =
      Enum.find(children, fn
        {Sigil.Cache, pid, _kind, _modules} -> is_pid(pid)
        _other -> false
      end)

    tables = Cache.tables(cache_pid)
    assert :nonces in Map.keys(tables)
  end

  test "Cache includes intel_market table" do
    tables = application_cache_tables!()
    intel_market_table = Map.fetch!(tables, :intel_market)

    assert :intel_market in Map.keys(tables)
    assert :ets.info(intel_market_table) != :undefined
  end

  defp configured_application_snapshot!(opts) do
    config_dir = temp_dir!("application_probe")
    static_data_dir = temp_dir!("application_probe_static_data")

    config_path =
      Fixtures.write_application_probe_config!(
        config_dir,
        opts
        |> Keyword.put(:static_data_dir, static_data_dir)
        |> Keyword.put(:world_client, Sigil.ApplicationTestWorldClient)
        |> Keyword.put_new(:monitor_registry, @default_monitor_registry)
      )

    script = """
    {:ok, _apps} = Application.ensure_all_started(:sigil)
    children = Supervisor.which_children(Sigil.Supervisor)

    gate_indexer_running =
      Enum.any?(children, fn
        {Sigil.GateIndexer, child_pid, _kind, _modules} ->
          is_pid(child_pid) and Process.alive?(child_pid)

        _other ->
          false
      end)

    cache_tables =
      case Enum.find(children, fn
             {Sigil.Cache, child_pid, _kind, _modules} -> is_pid(child_pid)
             _other -> false
           end) do
        {Sigil.Cache, child_pid, _kind, _modules} -> Sigil.Cache.tables(child_pid)
        nil -> %{}
      end

    gate_network_table_valid =
      case Map.get(cache_tables, :gate_network) do
        nil -> false
        tid -> :ets.info(tid) != :undefined
      end

    children = Supervisor.which_children(Sigil.Supervisor)
    monitor_registry = Application.get_env(:sigil, :monitor_registry)

    static_data_pid =
      case Enum.find(children, fn
             {Sigil.StaticData, child_pid, _kind, _modules} -> is_pid(child_pid)
             _other -> false
           end) do
        {Sigil.StaticData, child_pid, _kind, _modules} -> child_pid
        nil -> nil
      end

    snapshot = %{
      child_ids:
        Enum.map(children, fn {id, _child_pid, _kind, _modules} -> inspect(id) end),
      static_data_running:
        Enum.any?(children, fn
          {Sigil.StaticData, child_pid, _kind, _modules} ->
            is_pid(child_pid) and Process.alive?(child_pid)

          _other ->
            false
        end),
      static_data_resolved:
        is_pid(static_data_pid) and SigilWeb.CacheResolver.application_static_data() == static_data_pid,
      gate_indexer_running: gate_indexer_running,
      gate_network_table_valid: gate_network_table_valid,
      alert_engine_running:
        Enum.any?(children, fn
          {Sigil.Alerts.Engine, child_pid, _kind, _modules} ->
            is_pid(child_pid) and Process.alive?(child_pid)

          _other ->
            false
        end),
      monitor_registry_running:
        Enum.any?(children, fn
          {^monitor_registry, child_pid, _kind, _modules} ->
            is_pid(child_pid) and Process.alive?(child_pid)

          _other ->
            false
        end),
      monitor_registry_index:
        Enum.find_index(children, fn
          {^monitor_registry, child_pid, _kind, _modules} -> is_pid(child_pid)
          _other -> false
        end),
      monitor_supervisor_running:
        Enum.any?(children, fn
          {Sigil.GameState.MonitorSupervisor, child_pid, _kind, _modules} ->
            is_pid(child_pid) and Process.alive?(child_pid)

          _other ->
            false
        end),
      monitor_supervisor_index:
        Enum.find_index(children, fn
          {Sigil.GameState.MonitorSupervisor, child_pid, _kind, _modules} -> is_pid(child_pid)
          _other -> false
        end),
      alert_engine_index:
        Enum.find_index(children, fn
          {Sigil.Alerts.Engine, child_pid, _kind, _modules} -> is_pid(child_pid)
          _other -> false
        end),
      endpoint_index:
        Enum.find_index(children, fn
          {SigilWeb.Endpoint, child_pid, _kind, _modules} -> is_pid(child_pid)
          _other -> false
        end)
    }

    IO.write("__SNAPSHOT_START__" <> Jason.encode!(snapshot) <> "__SNAPSHOT_END__")
    Application.stop(:sigil)
    """

    {output, status} =
      Task.async(fn ->
        System.cmd("mix", Fixtures.mix_run_args(config_path, script, no_start: true),
          cd: project_root(),
          env:
            [{"MIX_ENV", "test"}] ++
              Fixtures.mix_subprocess_env("application_probe_mix"),
          stderr_to_stdout: true
        )
      end)
      |> Task.await(120_000)

    assert status == 0, output

    decoded =
      output
      |> extract_json!()
      |> Jason.decode!()

    %{
      child_ids: decoded["child_ids"],
      static_data_running: decoded["static_data_running"],
      static_data_resolved: decoded["static_data_resolved"],
      gate_indexer_running: decoded["gate_indexer_running"],
      gate_network_table_valid: decoded["gate_network_table_valid"],
      alert_engine_running: decoded["alert_engine_running"],
      monitor_registry_running: decoded["monitor_registry_running"],
      monitor_registry_index: decoded["monitor_registry_index"],
      monitor_supervisor_running: decoded["monitor_supervisor_running"],
      monitor_supervisor_index: decoded["monitor_supervisor_index"],
      alert_engine_index: decoded["alert_engine_index"],
      endpoint_index: decoded["endpoint_index"]
    }
  end

  defp running_application_snapshot! do
    children = Supervisor.which_children(Sigil.Supervisor)

    %{
      child_ids: Enum.map(children, fn {id, _child_pid, _kind, _modules} -> inspect(id) end),
      static_data_running:
        Enum.any?(children, fn
          {Sigil.StaticData, child_pid, _kind, _modules} ->
            is_pid(child_pid) and Process.alive?(child_pid)

          _other ->
            false
        end)
    }
  end

  defp application_cache_tables! do
    {Sigil.Cache, cache_pid, _kind, _modules} =
      Supervisor.which_children(Sigil.Supervisor)
      |> Enum.find(fn
        {Sigil.Cache, pid, _kind, _modules} -> is_pid(pid)
        _other -> false
      end)

    Cache.tables(cache_pid)
  end

  defp temp_dir!(prefix) do
    dir = Fixtures.ensure_tmp_dir!(prefix)
    on_exit(fn -> File.rm_rf(dir) end)
    dir
  end

  defp project_root do
    Path.expand("../..", __DIR__)
  end

  defp extract_json!(output) do
    case Regex.run(~r/__SNAPSHOT_START__(\{.*\})__SNAPSHOT_END__/s, output,
           capture: :all_but_first
         ) do
      [json] -> json
      _other -> raise ExUnit.AssertionError, message: output
    end
  end

  defp index_of(items, item), do: Enum.find_index(items, &(&1 == item))
end
