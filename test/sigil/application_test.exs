defmodule Sigil.ApplicationTest do
  @moduledoc """
  Captures the application supervision-tree contract.
  """

  use ExUnit.Case, async: true

  alias Sigil.Cache
  alias Sigil.StaticDataTestFixtures, as: Fixtures

  @default_monitor_registry Sigil.GameState.MonitorRegistry
  @stillness_world "stillness"
  @utopia_world "utopia"
  @multi_worlds [@stillness_world, @utopia_world]
  @stillness_monitor_registry Sigil.GameState.MonitorRegistry.Stillness
  @utopia_monitor_registry Sigil.GameState.MonitorRegistry.Utopia
  @multi_world_monitor_registries %{
    @stillness_world => @stillness_monitor_registry,
    @utopia_world => @utopia_monitor_registry
  }
  @multi_world_eve_worlds %{
    @stillness_world => %{
      package_id: "0x28b497559d65ab320d9da4613bf2498d5946b2c0ae3597ccfda3072ce127448c",
      sigil_package_id: "0x06ce9d6bed77615383575cc7eba4883d32769b30cd5df00561e38434a59611a1",
      graphql_url: "https://graphql.testnet.sui.io/graphql",
      rpc_url: "https://fullnode.testnet.sui.io:443"
    },
    @utopia_world => %{
      package_id: "0xd12a70c74c1e759445d6f209b01d43d860e97fcf2ef72ccbbd00afd828043f75",
      sigil_package_id: "0x06ce9d6bed77615383575cc7eba4883d32769b30cd5df00561e38434a59611a1",
      graphql_url: "https://graphql.testnet.sui.io/graphql",
      rpc_url: "https://fullnode.testnet.sui.io:443"
    }
  }

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

  test "starts world-scoped workers when multiple worlds are active" do
    snapshot =
      configured_application_snapshot!(
        active_worlds: @multi_worlds,
        eve_world: @stillness_world,
        eve_worlds: @multi_world_eve_worlds,
        monitor_registry: nil,
        monitor_registries: @multi_world_monitor_registries,
        start_gate_indexer: true,
        start_monitor_supervisor: true,
        start_alert_engine: true,
        start_grpc_stream: true,
        start_assembly_event_router: true,
        start_reputation_engine: true
      )

    assert inspect({Sigil.Cache, @stillness_world}) in snapshot.child_ids
    assert inspect({Sigil.Cache, @utopia_world}) in snapshot.child_ids

    assert inspect({Sigil.GateIndexer, @stillness_world}) in snapshot.child_ids
    assert inspect({Sigil.GateIndexer, @utopia_world}) in snapshot.child_ids

    assert inspect({Sigil.GameState.MonitorSupervisor, @stillness_world}) in snapshot.child_ids
    assert inspect({Sigil.GameState.MonitorSupervisor, @utopia_world}) in snapshot.child_ids

    assert inspect({Sigil.Alerts.Engine, @stillness_world}) in snapshot.child_ids
    assert inspect({Sigil.Alerts.Engine, @utopia_world}) in snapshot.child_ids

    assert inspect({Sigil.Sui.GrpcStream, @stillness_world}) in snapshot.child_ids
    assert inspect({Sigil.Sui.GrpcStream, @utopia_world}) in snapshot.child_ids

    assert inspect({Sigil.GameState.AssemblyEventRouter, @stillness_world}) in snapshot.child_ids
    assert inspect({Sigil.GameState.AssemblyEventRouter, @utopia_world}) in snapshot.child_ids

    assert inspect({Sigil.Reputation.Engine, @stillness_world}) in snapshot.child_ids
    assert inspect({Sigil.Reputation.Engine, @utopia_world}) in snapshot.child_ids

    assert inspect({:monitor_registry, @stillness_world, @stillness_monitor_registry}) in snapshot.child_ids

    assert inspect({:monitor_registry, @utopia_world, @utopia_monitor_registry}) in snapshot.child_ids

    refute inspect(Sigil.Cache) in snapshot.child_ids
    refute inspect(Sigil.GateIndexer) in snapshot.child_ids
    refute inspect(Sigil.GameState.MonitorSupervisor) in snapshot.child_ids
    refute inspect(Sigil.Alerts.Engine) in snapshot.child_ids
    refute inspect(Sigil.Sui.GrpcStream) in snapshot.child_ids
    refute inspect(Sigil.GameState.AssemblyEventRouter) in snapshot.child_ids
    refute inspect(Sigil.Reputation.Engine) in snapshot.child_ids
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

  test "supervision tree includes GrpcStream when enabled" do
    snapshot = configured_application_snapshot!(start_grpc_stream: true)

    assert snapshot.grpc_stream_running
    assert inspect(Sigil.Sui.GrpcStream) in snapshot.child_ids
  end

  test "assembly_event_router starts after monitor registry when enabled" do
    snapshot =
      configured_application_snapshot!(
        start_monitor_supervisor: true,
        start_assembly_event_router: true
      )

    assert snapshot.assembly_event_router_running
    assert inspect(Sigil.GameState.AssemblyEventRouter) in snapshot.child_ids

    # which_children returns reverse start order: higher index = started earlier
    assert snapshot.monitor_registry_index > snapshot.assembly_event_router_index
    assert snapshot.assembly_event_router_index > snapshot.endpoint_index
  end

  test "assembly_event_router starts after grpc_stream when both enabled" do
    snapshot =
      configured_application_snapshot!(
        start_monitor_supervisor: true,
        start_grpc_stream: true,
        start_assembly_event_router: true
      )

    assert snapshot.grpc_stream_running
    assert snapshot.assembly_event_router_running

    # which_children returns reverse start order: higher index = started earlier
    assert snapshot.grpc_stream_index > snapshot.assembly_event_router_index
  end

  test "assembly_event_router excluded when monitor supervisor is disabled" do
    snapshot =
      configured_application_snapshot!(
        start_monitor_supervisor: false,
        start_assembly_event_router: true
      )

    refute snapshot.assembly_event_router_running
    refute inspect(Sigil.GameState.AssemblyEventRouter) in snapshot.child_ids
  end

  test "assembly_event_router excluded when feature flag is false" do
    snapshot =
      configured_application_snapshot!(
        start_monitor_supervisor: true,
        start_assembly_event_router: false
      )

    refute snapshot.assembly_event_router_running
    refute inspect(Sigil.GameState.AssemblyEventRouter) in snapshot.child_ids
  end

  test "application cache includes reputation table" do
    tables = application_cache_tables!()
    reputation_table = Map.fetch!(tables, :reputation)

    assert :reputation in Map.keys(tables)
    assert :ets.info(reputation_table) != :undefined
  end

  test "supervision tree includes ReputationEngine when enabled" do
    snapshot = configured_application_snapshot!(start_reputation_engine: true)

    assert snapshot.reputation_engine_running
    assert inspect(Sigil.Reputation.Engine) in snapshot.child_ids
  end

  test "AlertEngine precedes GrpcStream and GrpcStream precedes Endpoint when enabled" do
    snapshot =
      configured_application_snapshot!(
        start_monitor_supervisor: true,
        start_alert_engine: true,
        start_grpc_stream: true
      )

    # which_children returns reverse start order: higher index = started earlier
    assert is_integer(snapshot.grpc_stream_index)
    assert snapshot.alert_engine_index > snapshot.grpc_stream_index
    assert snapshot.grpc_stream_index > snapshot.endpoint_index
  end

  test "GrpcStream precedes ReputationEngine and Endpoint" do
    snapshot =
      configured_application_snapshot!(
        start_grpc_stream: true,
        start_reputation_engine: true
      )

    # which_children returns reverse start order: higher index = started earlier
    assert is_integer(snapshot.grpc_stream_index)
    assert is_integer(snapshot.reputation_engine_index)
    assert snapshot.grpc_stream_index > snapshot.reputation_engine_index
    assert snapshot.reputation_engine_index > snapshot.endpoint_index
  end

  test "GrpcStream excluded when config is false" do
    enabled_snapshot = configured_application_snapshot!(start_grpc_stream: true)
    assert enabled_snapshot.grpc_stream_running

    disabled_snapshot = configured_application_snapshot!(start_grpc_stream: false)

    refute disabled_snapshot.grpc_stream_running
    refute inspect(Sigil.Sui.GrpcStream) in disabled_snapshot.child_ids
  end

  test "ReputationEngine excluded when config is false" do
    enabled_snapshot =
      configured_application_snapshot!(start_grpc_stream: true, start_reputation_engine: true)

    assert enabled_snapshot.reputation_engine_running

    disabled_snapshot =
      configured_application_snapshot!(start_grpc_stream: true, start_reputation_engine: false)

    refute disabled_snapshot.reputation_engine_running
    refute inspect(Sigil.Reputation.Engine) in disabled_snapshot.child_ids
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

  @tag :acceptance
  test "application starts with assembly event router wiring enabled" do
    snapshot =
      configured_application_snapshot!(
        start_monitor_supervisor: true,
        start_grpc_stream: true,
        start_assembly_event_router: true
      )

    assert snapshot.monitor_registry_running
    assert snapshot.monitor_supervisor_running
    assert snapshot.grpc_stream_running
    assert snapshot.assembly_event_router_running

    disabled_snapshot =
      configured_application_snapshot!(
        start_monitor_supervisor: true,
        start_grpc_stream: true,
        start_assembly_event_router: false
      )

    refute disabled_snapshot.assembly_event_router_running
    refute inspect(Sigil.GameState.AssemblyEventRouter) in disabled_snapshot.child_ids
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
        |> Keyword.put_new(:grpc_connector, Sigil.ApplicationTestGrpcConnector)
        |> Keyword.put_new(:monitor_registry, @default_monitor_registry)
        |> Keyword.put_new(:monitor_registries, %{})
        |> Keyword.put_new(:active_worlds, ["test"])
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
      grpc_stream_running:
        Enum.any?(children, fn
          {Sigil.Sui.GrpcStream, child_pid, _kind, _modules} ->
            is_pid(child_pid) and Process.alive?(child_pid)

          _other ->
            false
        end),
      reputation_engine_running:
        Enum.any?(children, fn
          {Sigil.Reputation.Engine, child_pid, _kind, _modules} ->
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
      assembly_event_router_running:
        Enum.any?(children, fn
          {Sigil.GameState.AssemblyEventRouter, child_pid, _kind, _modules} ->
            is_pid(child_pid) and Process.alive?(child_pid)

          _other ->
            false
        end),
      assembly_event_router_index:
        Enum.find_index(children, fn
          {Sigil.GameState.AssemblyEventRouter, child_pid, _kind, _modules} -> is_pid(child_pid)
          _other -> false
        end),
      alert_engine_index:
        Enum.find_index(children, fn
          {Sigil.Alerts.Engine, child_pid, _kind, _modules} -> is_pid(child_pid)
          _other -> false
        end),
      grpc_stream_index:
        Enum.find_index(children, fn
          {Sigil.Sui.GrpcStream, child_pid, _kind, _modules} -> is_pid(child_pid)
          _other -> false
        end),
      reputation_engine_index:
        Enum.find_index(children, fn
          {Sigil.Reputation.Engine, child_pid, _kind, _modules} -> is_pid(child_pid)
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
      grpc_stream_running: decoded["grpc_stream_running"],
      monitor_registry_running: decoded["monitor_registry_running"],
      monitor_registry_index: decoded["monitor_registry_index"],
      monitor_supervisor_running: decoded["monitor_supervisor_running"],
      monitor_supervisor_index: decoded["monitor_supervisor_index"],
      assembly_event_router_running: decoded["assembly_event_router_running"],
      assembly_event_router_index: decoded["assembly_event_router_index"],
      alert_engine_index: decoded["alert_engine_index"],
      grpc_stream_index: decoded["grpc_stream_index"],
      reputation_engine_running: decoded["reputation_engine_running"],
      reputation_engine_index: decoded["reputation_engine_index"],
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
