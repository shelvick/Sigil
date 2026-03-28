defmodule Sigil.Alerts.EngineTest.CapturingNotifier do
  @moduledoc """
  Test notifier that reports deliveries back to the calling test process.
  """

  @compile {:no_warn_undefined, Sigil.Alerts.Alert}

  @doc "Sends delivered alert details to the injected test process."
  @spec deliver(Sigil.Alerts.Alert.t(), map(), keyword()) :: :ok
  def deliver(alert, config, opts) do
    send(Keyword.fetch!(opts, :test_pid), {:notifier_called, alert, config})
    :ok
  end
end

defmodule Sigil.Alerts.EngineTest do
  @moduledoc """
  Captures the packet 2 alert engine contract.
  """

  use Sigil.DataCase, async: true

  @compile {:no_warn_undefined, Sigil.Alerts.Engine}
  @compile {:no_warn_undefined, Sigil.Alerts.WebhookNotifier.Discord}

  import Plug.Conn

  alias Sigil.Accounts.Account
  alias Sigil.Alerts
  alias Sigil.Alerts.Alert
  alias Sigil.Alerts.EngineTest.CapturingNotifier
  alias Sigil.Cache

  alias Sigil.Sui.Types.{
    AssemblyStatus,
    Fuel,
    Gate,
    Location,
    Metadata,
    NetworkNode,
    TenantItemId
  }

  setup do
    cache_pid = start_supervised!({Cache, tables: [:assemblies, :accounts]})
    pubsub = unique_pubsub_name()
    registry = unique_registry_name()

    start_supervised!({Phoenix.PubSub, name: pubsub})
    start_supervised!({Registry, keys: :unique, name: registry})

    {:ok, tables: Cache.tables(cache_pid), pubsub: pubsub, registry: registry}
  end

  test "engine starts and schedules discovery", %{
    tables: tables,
    pubsub: pubsub,
    registry: registry
  } do
    engine =
      start_engine!(
        pubsub: pubsub,
        registry: registry,
        tables: tables,
        discovery_interval_ms: 25,
        purge_interval_ms: 60_000
      )

    state = Sigil.Alerts.Engine.get_state(engine)

    assert Process.alive?(engine)
    assert state.pubsub == pubsub
    assert state.registry == registry
    assert state.tables == tables
    assert state.watched_ids == MapSet.new()
  end

  test "discovers monitors and subscribes to new topics", %{
    tables: tables,
    pubsub: pubsub,
    registry: registry
  } do
    parent = self()
    assembly = network_node_fixture(id: "assembly-discovery")
    owner = owner_address()
    tribe_id = 4242

    put_owner_context!(tables, assembly, owner, tribe_id)
    Registry.register(registry, assembly.id, nil)

    create_alert_fun = fn attrs, _opts ->
      send(parent, {:create_alert_called, attrs})
      {:ok, alert_struct(attrs)}
    end

    engine =
      start_engine!(
        pubsub: pubsub,
        registry: registry,
        tables: tables,
        create_alert_fun: create_alert_fun,
        dispatch_fun: fn _alert, _config, _notifier, _opts -> :ok end
      )

    discover!(engine)

    Phoenix.PubSub.broadcast(pubsub, "assembly:#{assembly.id}", {
      :assembly_monitor,
      assembly.id,
      fuel_low_payload(assembly)
    })

    assert_receive {:create_alert_called, attrs}, 1_000
    assert attrs.account_address == owner
    assert attrs.tribe_id == tribe_id
    assert attrs.type == "fuel_low"
  end

  test "subscribes when monitor lifecycle event arrives before first broadcast", %{
    tables: tables,
    pubsub: pubsub,
    registry: registry
  } do
    parent = self()
    assembly = network_node_fixture(id: "assembly-pre-discovery")
    owner = owner_address()

    put_owner_context!(tables, assembly, owner, 42)

    engine =
      start_engine!(
        pubsub: pubsub,
        registry: registry,
        tables: tables,
        create_alert_fun: fn attrs, _opts ->
          send(parent, {:create_alert_called, attrs.type})
          {:ok, alert_struct(attrs)}
        end,
        dispatch_fun: fn _alert, _config, _notifier, _opts -> :ok end
      )

    Registry.register(registry, assembly.id, nil)
    assembly_id = assembly.id
    :ok = Phoenix.PubSub.subscribe(pubsub, "monitors:lifecycle")
    Phoenix.PubSub.broadcast(pubsub, "monitors:lifecycle", {:monitor_started, assembly_id})
    assert_receive {:monitor_started, ^assembly_id}, 1_000
    _state = Sigil.Alerts.Engine.get_state(engine)

    Phoenix.PubSub.broadcast(pubsub, "assembly:#{assembly.id}", {
      :assembly_monitor,
      assembly.id,
      fuel_low_payload(assembly)
    })

    assert_receive {:create_alert_called, "fuel_low"}, 1_000
  end

  test "removes stale topic subscriptions during discovery", %{
    tables: tables,
    pubsub: pubsub,
    registry: registry
  } do
    parent = self()
    assembly = network_node_fixture(id: "assembly-stale")
    owner = owner_address()

    put_owner_context!(tables, assembly, owner, 4242)
    Registry.register(registry, assembly.id, nil)

    create_alert_fun = fn attrs, _opts ->
      send(parent, {:create_alert_called, attrs.type})
      {:ok, alert_struct(attrs)}
    end

    engine =
      start_engine!(
        pubsub: pubsub,
        registry: registry,
        tables: tables,
        create_alert_fun: create_alert_fun,
        dispatch_fun: fn _alert, _config, _notifier, _opts -> :ok end
      )

    discover!(engine)

    Phoenix.PubSub.broadcast(pubsub, "assembly:#{assembly.id}", {
      :assembly_monitor,
      assembly.id,
      fuel_low_payload(assembly)
    })

    assert_receive {:create_alert_called, "fuel_low"}, 1_000

    Registry.unregister(registry, assembly.id)
    discover!(engine)

    Phoenix.PubSub.broadcast(pubsub, "assembly:#{assembly.id}", {
      :assembly_monitor,
      assembly.id,
      fuel_low_payload(assembly)
    })

    refute_receive {:create_alert_called, _type}, 200
  end

  test "retries discovery when registry is unavailable", %{tables: tables, pubsub: pubsub} do
    parent = self()

    resolve_registry = fn ->
      send(parent, :resolve_registry_called)
      nil
    end

    engine =
      start_engine!(
        pubsub: pubsub,
        resolve_registry: resolve_registry,
        tables: tables,
        discovery_interval_ms: 25,
        purge_interval_ms: 60_000
      )

    assert_receive :resolve_registry_called, 1_000
    assert_receive :resolve_registry_called, 1_000

    state = Sigil.Alerts.Engine.get_state(engine)

    assert Process.alive?(engine)
    assert is_nil(state.registry)
    assert state.watched_ids == MapSet.new()
  end

  test "creates fuel_low alert below threshold", %{
    tables: tables,
    pubsub: pubsub,
    registry: registry
  } do
    parent = self()
    assembly = network_node_fixture(id: "assembly-fuel-low", fuel: fuel_fixture(quantity: 19))
    owner = owner_address()

    put_owner_context!(tables, assembly, owner, 42)

    create_alert_fun = fn attrs, _opts ->
      send(parent, {:create_alert_called, attrs})
      {:ok, alert_struct(attrs)}
    end

    engine =
      start_engine!(
        pubsub: pubsub,
        registry: registry,
        tables: tables,
        create_alert_fun: create_alert_fun,
        dispatch_fun: fn _alert, _config, _notifier, _opts -> :ok end
      )

    send(engine, {:assembly_monitor, assembly.id, fuel_low_payload(assembly)})

    assert_receive {:create_alert_called, attrs}, 1_000
    assert attrs.type == "fuel_low"
    assert attrs.severity == "warning"
    assert attrs.message == "Fuel at 19.0% (19/100 units)"
  end

  test "does not create fuel_low alert at or above threshold", %{
    tables: tables,
    pubsub: pubsub,
    registry: registry
  } do
    parent = self()
    assembly = network_node_fixture(id: "assembly-fuel-ok", fuel: fuel_fixture(quantity: 20))
    owner = owner_address()

    put_owner_context!(tables, assembly, owner, 42)

    engine =
      start_engine!(
        pubsub: pubsub,
        registry: registry,
        tables: tables,
        create_alert_fun: fn attrs, _opts ->
          send(parent, {:create_alert_called, attrs})
          {:ok, alert_struct(attrs)}
        end,
        dispatch_fun: fn _alert, _config, _notifier, _opts -> :ok end
      )

    send(engine, {:assembly_monitor, assembly.id, fuel_low_payload(assembly)})

    refute_receive {:create_alert_called, _attrs}, 200
  end

  test "creates fuel_critical alert using injected clock", %{
    tables: tables,
    pubsub: pubsub,
    registry: registry
  } do
    parent = self()
    now = ~U[2026-03-21 04:45:05Z]

    assembly =
      network_node_fixture(id: "assembly-fuel-critical", fuel: fuel_fixture(quantity: 10))

    owner = owner_address()

    put_owner_context!(tables, assembly, owner, 42)

    create_alert_fun = fn attrs, _opts ->
      send(parent, {:create_alert_called, attrs})
      {:ok, alert_struct(attrs)}
    end

    engine =
      start_engine!(
        pubsub: pubsub,
        registry: registry,
        tables: tables,
        now_fun: fn -> now end,
        create_alert_fun: create_alert_fun,
        dispatch_fun: fn _alert, _config, _notifier, _opts -> :ok end
      )

    send(engine, {
      :assembly_monitor,
      assembly.id,
      %{
        fuel_low_payload(assembly)
        | depletion: {:depletes_at, DateTime.add(now, 90 * 60, :second)}
      }
    })

    assert_receive {:create_alert_called, attrs}, 1_000
    assert attrs.type == "fuel_critical"
    assert attrs.severity == "critical"
    assert attrs.message == "Fuel depletes in 1h 30m"
  end

  test "creates assembly_offline alert on offline transition", %{
    tables: tables,
    pubsub: pubsub,
    registry: registry
  } do
    parent = self()
    assembly = gate_fixture(id: "assembly-offline")
    owner = owner_address()

    put_owner_context!(tables, assembly, owner, 42)

    create_alert_fun = fn attrs, _opts ->
      send(parent, {:create_alert_called, attrs})
      {:ok, alert_struct(attrs)}
    end

    engine =
      start_engine!(
        pubsub: pubsub,
        registry: registry,
        tables: tables,
        create_alert_fun: create_alert_fun,
        dispatch_fun: fn _alert, _config, _notifier, _opts -> :ok end
      )

    send(engine, {
      :assembly_monitor,
      assembly.id,
      %{
        fuel_low_payload(assembly)
        | changes: [{:status_changed, :online, :offline}],
          depletion: nil
      }
    })

    assert_receive {:create_alert_called, attrs}, 1_000
    assert attrs.type == "assembly_offline"
    assert attrs.message == "Assembly has gone offline"
    assert attrs.metadata.previous_status == :online
  end

  test "creates extension_changed alert on extension change", %{
    tables: tables,
    pubsub: pubsub,
    registry: registry
  } do
    parent = self()
    assembly = gate_fixture(id: "assembly-extension")
    owner = owner_address()

    put_owner_context!(tables, assembly, owner, 42)

    create_alert_fun = fn attrs, _opts ->
      send(parent, {:create_alert_called, attrs})
      {:ok, alert_struct(attrs)}
    end

    engine =
      start_engine!(
        pubsub: pubsub,
        registry: registry,
        tables: tables,
        create_alert_fun: create_alert_fun,
        dispatch_fun: fn _alert, _config, _notifier, _opts -> :ok end
      )

    send(engine, {
      :assembly_monitor,
      assembly.id,
      %{
        assembly: assembly,
        depletion: nil,
        changes: [{:extension_changed, nil, "0x2::frontier::GateExtension"}]
      }
    })

    assert_receive {:create_alert_called, attrs}, 1_000
    assert attrs.type == "extension_changed"
    assert attrs.severity == "info"
    assert attrs.metadata.old_extension == nil
    assert attrs.metadata.new_extension == "0x2::frontier::GateExtension"
  end

  test "skips alert creation when owner lookup is missing", %{
    tables: tables,
    pubsub: pubsub,
    registry: registry
  } do
    parent = self()
    assembly = network_node_fixture(id: "assembly-missing-owner")

    engine =
      start_engine!(
        pubsub: pubsub,
        registry: registry,
        tables: tables,
        create_alert_fun: fn attrs, _opts ->
          send(parent, {:create_alert_called, attrs})
          {:ok, alert_struct(attrs)}
        end,
        dispatch_fun: fn _alert, _config, _notifier, _opts -> :ok end
      )

    send(engine, {:assembly_monitor, assembly.id, fuel_low_payload(assembly)})

    refute_receive {:create_alert_called, _attrs}, 200
  end

  test "resolves account_address from assemblies cache", %{
    tables: tables,
    pubsub: pubsub,
    registry: registry
  } do
    parent = self()
    assembly = network_node_fixture(id: "assembly-owner-resolve")
    owner = "0xowner-for-r10"

    put_owner_context!(tables, assembly, owner, 42)

    create_alert_fun = fn attrs, _opts ->
      send(parent, {:alert_attrs, attrs})
      {:ok, alert_struct(attrs)}
    end

    engine =
      start_engine!(
        pubsub: pubsub,
        registry: registry,
        tables: tables,
        create_alert_fun: create_alert_fun,
        dispatch_fun: fn _alert, _config, _notifier, _opts -> :ok end
      )

    send(engine, {:assembly_monitor, assembly.id, fuel_low_payload(assembly)})

    assert_receive {:alert_attrs, attrs}, 1_000
    assert attrs.account_address == owner
  end

  test "resolves tribe_id from accounts cache", %{
    tables: tables,
    pubsub: pubsub,
    registry: registry
  } do
    parent = self()
    assembly = network_node_fixture(id: "assembly-tribe-resolve")
    owner = owner_address()
    tribe_id = 8888

    put_owner_context!(tables, assembly, owner, tribe_id)

    create_alert_fun = fn attrs, _opts ->
      send(parent, {:alert_attrs, attrs})
      {:ok, alert_struct(attrs)}
    end

    engine =
      start_engine!(
        pubsub: pubsub,
        registry: registry,
        tables: tables,
        create_alert_fun: create_alert_fun,
        dispatch_fun: fn _alert, _config, _notifier, _opts -> :ok end
      )

    send(engine, {:assembly_monitor, assembly.id, fuel_low_payload(assembly)})

    assert_receive {:alert_attrs, attrs}, 1_000
    assert attrs.tribe_id == tribe_id
  end

  test "dispatches webhook delivery asynchronously", %{
    tables: tables,
    pubsub: pubsub,
    registry: registry,
    sandbox_owner: sandbox_owner
  } do
    parent = self()
    assembly = network_node_fixture(id: "assembly-async-dispatch")
    owner = owner_address()
    tribe_id = 555
    stub_name = stub_name(:engine_default_dispatch)

    put_owner_context!(tables, assembly, owner, tribe_id)

    assert {:ok, _config} =
             Alerts.upsert_webhook_config(
               tribe_id,
               %{
                 "webhook_url" => "https://discord.example/webhooks/default-dispatch",
                 "service_type" => "discord",
                 "enabled" => true
               },
               []
             )

    Req.Test.expect(stub_name, fn conn ->
      payload = request_body(conn)
      [embed] = payload["embeds"]
      assert embed["title"] == "Fuel Low"
      send(parent, :default_dispatch_delivered)
      Req.Test.json(conn, %{"ok" => true})
    end)

    engine =
      start_engine!(
        pubsub: pubsub,
        registry: registry,
        tables: tables,
        sandbox_owner: sandbox_owner,
        notifier: Sigil.Alerts.WebhookNotifier.Discord,
        notifier_opts: [req_options: [plug: {Req.Test, stub_name}], delay_fun: fn _ms -> :ok end]
      )

    send(engine, {:assembly_monitor, assembly.id, fuel_low_payload(assembly)})

    assert_receive :default_dispatch_delivered, 5_000
    assert :ok = Req.Test.verify!(stub_name)
  end

  test "persists alert and skips webhook when config missing", %{
    tables: tables,
    pubsub: pubsub,
    registry: registry
  } do
    parent = self()
    assembly = network_node_fixture(id: "assembly-no-webhook")
    owner = owner_address()
    tribe_id = 6666

    put_owner_context!(tables, assembly, owner, tribe_id)

    engine =
      start_engine!(
        pubsub: pubsub,
        registry: registry,
        tables: tables,
        create_alert_fun: fn attrs, _opts ->
          send(parent, {:alert_created, attrs})
          {:ok, alert_struct(attrs)}
        end,
        get_webhook_config_fun: fn _tribe_id, _opts -> nil end,
        dispatch_fun: fn _alert, _config, _notifier, _opts ->
          send(parent, :dispatch_called)
        end
      )

    send(engine, {:assembly_monitor, assembly.id, fuel_low_payload(assembly)})

    assert_receive {:alert_created, attrs}, 1_000
    assert attrs.type == "fuel_low"
    refute_receive :dispatch_called, 200
  end

  test "does not dispatch webhook for duplicate or cooldown result", %{
    tables: tables,
    pubsub: pubsub,
    registry: registry
  } do
    parent = self()
    assembly = network_node_fixture(id: "assembly-dedup")
    owner = owner_address()

    put_owner_context!(tables, assembly, owner, 42)

    for result <- [{:ok, :duplicate}, {:ok, :cooldown}] do
      engine =
        start_engine!(
          pubsub: pubsub,
          registry: registry,
          tables: tables,
          create_alert_fun: fn _attrs, _opts -> result end,
          get_webhook_config_fun: fn _tribe_id, _opts ->
            send(parent, :get_webhook_config_called)
            webhook_config_struct(tribe_id: 42)
          end,
          dispatch_fun: fn _alert, _config, _notifier, _opts -> send(parent, :dispatch_called) end
        )

      send(engine, {:assembly_monitor, assembly.id, fuel_low_payload(assembly)})

      # Engine should short-circuit on duplicate/cooldown before reaching webhook lookup
      refute_receive :get_webhook_config_called, 200
      refute_receive :dispatch_called, 200
    end
  end

  test "retries discovery when tables are unavailable", %{pubsub: pubsub, registry: registry} do
    parent = self()

    resolve_tables = fn ->
      send(parent, :resolve_tables_called)
      nil
    end

    engine =
      start_engine!(
        pubsub: pubsub,
        registry: registry,
        resolve_tables: resolve_tables,
        discovery_interval_ms: 25,
        purge_interval_ms: 60_000
      )

    assert_receive :resolve_tables_called, 1_000
    assert_receive :resolve_tables_called, 1_000

    state = Sigil.Alerts.Engine.get_state(engine)

    assert Process.alive?(engine)
    assert is_nil(state.tables)
    assert state.watched_ids == MapSet.new()
  end

  test "uses injectable dispatch_fun for webhook delivery", %{
    tables: tables,
    pubsub: pubsub,
    registry: registry
  } do
    parent = self()
    assembly = network_node_fixture(id: "assembly-dispatch")
    owner = owner_address()
    tribe_id = 777

    put_owner_context!(tables, assembly, owner, tribe_id)

    create_alert_fun = fn attrs, _opts -> {:ok, alert_struct(attrs)} end

    get_webhook_config_fun = fn ^tribe_id, _opts ->
      webhook_config_struct(tribe_id: tribe_id)
    end

    dispatch_fun = fn alert, config, notifier, opts ->
      send(parent, {:dispatch_called, alert, config, notifier, opts})
      notifier.deliver(alert, config, opts)
    end

    engine =
      start_engine!(
        pubsub: pubsub,
        registry: registry,
        tables: tables,
        create_alert_fun: create_alert_fun,
        get_webhook_config_fun: get_webhook_config_fun,
        notifier: CapturingNotifier,
        notifier_opts: [test_pid: self()],
        dispatch_fun: dispatch_fun
      )

    send(engine, {:assembly_monitor, assembly.id, fuel_low_payload(assembly)})

    assert_receive {:dispatch_called, %Alert{} = alert, config, CapturingNotifier,
                    [test_pid: test_pid]},
                   1_000

    assert alert.type == "fuel_low"
    assert config.tribe_id == tribe_id
    assert test_pid == self()
    assert_receive {:notifier_called, %Alert{type: "fuel_low"}, ^config}, 1_000
  end

  test "periodic purge delegates to context", %{
    tables: tables,
    pubsub: pubsub,
    registry: registry,
    sandbox_owner: sandbox_owner
  } do
    old_alert =
      insert_alert!(%{
        "assembly_id" => "purge-old",
        "type" => "fuel_low",
        "status" => "dismissed",
        "dismissed_at" => DateTime.add(DateTime.utc_now(), -31 * 86_400, :second)
      })

    recent_alert =
      insert_alert!(%{
        "assembly_id" => "purge-recent",
        "type" => "fuel_critical",
        "status" => "dismissed",
        "dismissed_at" => DateTime.add(DateTime.utc_now(), -5 * 86_400, :second)
      })

    engine =
      start_engine!(
        pubsub: pubsub,
        registry: registry,
        tables: tables,
        sandbox_owner: sandbox_owner,
        purge_after_days: 30,
        purge_interval_ms: 60_000
      )

    send(engine, :purge_old_dismissed)
    _state = Sigil.Alerts.Engine.get_state(engine)

    refute Alerts.get_alert(old_alert.id, [])
    assert Alerts.get_alert(recent_alert.id, [])
  end

  @tag :acceptance
  test "monitor event persists alert and sends Discord notification", %{
    tables: tables,
    pubsub: pubsub,
    registry: registry,
    sandbox_owner: sandbox_owner
  } do
    parent = self()
    assembly = network_node_fixture(id: "assembly-acceptance", fuel: fuel_fixture(quantity: 10))
    owner = owner_address()
    tribe_id = 9_001
    stub_name = stub_name(:engine_acceptance)

    put_owner_context!(tables, assembly, owner, tribe_id)
    Registry.register(registry, assembly.id, nil)

    assert {:ok, _config} =
             Alerts.upsert_webhook_config(
               tribe_id,
               %{
                 "webhook_url" => "https://discord.example/webhooks/acceptance",
                 "service_type" => "discord",
                 "enabled" => true
               },
               []
             )

    Req.Test.expect(stub_name, fn conn ->
      payload = request_body(conn)
      [embed] = payload["embeds"]

      assert embed["title"] == "Fuel Low"
      assert embed["description"] == "Fuel at 10.0% (10/100 units)"
      refute embed["description"] =~ "N/A"
      refute embed["description"] =~ "error"
      send(parent, :webhook_received)

      Req.Test.json(conn, %{"ok" => true})
    end)

    engine =
      start_engine!(
        pubsub: pubsub,
        registry: registry,
        tables: tables,
        sandbox_owner: sandbox_owner,
        notifier: Sigil.Alerts.WebhookNotifier.Discord,
        notifier_opts: [req_options: [plug: {Req.Test, stub_name}], delay_fun: fn _ms -> :ok end],
        dispatch_fun: fn alert, config, notifier, opts ->
          notifier.deliver(alert, config, opts)
        end
      )

    discover!(engine)

    Phoenix.PubSub.broadcast(pubsub, "assembly:#{assembly.id}", {
      :assembly_monitor,
      assembly.id,
      fuel_low_payload(assembly)
    })

    assert_receive :webhook_received, 1_000

    alerts = Alerts.list_alerts([account_address: owner], [])
    assert length(alerts) == 1
    assert Enum.at(alerts, 0).type == "fuel_low"
    assert Enum.at(alerts, 0).tribe_id == tribe_id
    refute Enum.any?(alerts, &(&1.type == "assembly_offline"))
    assert :ok = Req.Test.verify!(stub_name)
  end

  test "creates reputation_threshold_crossed alert on tier change", %{
    tables: tables,
    pubsub: pubsub,
    registry: registry
  } do
    parent = self()
    account_address = owner_address()

    _engine =
      start_engine!(
        pubsub: pubsub,
        registry: registry,
        tables: tables,
        create_alert_fun: fn attrs, _opts ->
          send(parent, {:create_alert_called, attrs})
          {:ok, alert_struct(attrs)}
        end,
        dispatch_fun: fn _alert, _config, _notifier, _opts -> :ok end
      )

    Phoenix.PubSub.broadcast(pubsub, "reputation", {
      :reputation_updated,
      reputation_payload(account_address: account_address)
    })

    assert_receive {:create_alert_called, attrs}, 1_000
    assert attrs.type == "reputation_threshold_crossed"
    assert attrs.assembly_id == nil
    assert attrs.assembly_name == nil
    assert attrs.account_address == account_address
    assert attrs.tribe_id == 42
  end

  test "reputation alert severity is info for positive transitions", %{
    tables: tables,
    pubsub: pubsub,
    registry: registry
  } do
    parent = self()

    _engine =
      start_engine!(
        pubsub: pubsub,
        registry: registry,
        tables: tables,
        create_alert_fun: fn attrs, _opts ->
          send(parent, {:create_alert_called, attrs})
          {:ok, alert_struct(attrs)}
        end,
        dispatch_fun: fn _alert, _config, _notifier, _opts -> :ok end
      )

    Phoenix.PubSub.broadcast(pubsub, "reputation", {
      :reputation_updated,
      reputation_payload(old_tier: :neutral, new_tier: :friendly)
    })

    assert_receive {:create_alert_called, attrs}, 1_000
    assert attrs.severity == "info"
  end

  test "reputation alert severity is warning for single-step downgrades", %{
    tables: tables,
    pubsub: pubsub,
    registry: registry
  } do
    parent = self()

    _engine =
      start_engine!(
        pubsub: pubsub,
        registry: registry,
        tables: tables,
        create_alert_fun: fn attrs, _opts ->
          send(parent, {:create_alert_called, attrs})
          {:ok, alert_struct(attrs)}
        end,
        dispatch_fun: fn _alert, _config, _notifier, _opts -> :ok end
      )

    Phoenix.PubSub.broadcast(pubsub, "reputation", {
      :reputation_updated,
      reputation_payload(old_tier: :friendly, new_tier: :neutral)
    })

    assert_receive {:create_alert_called, attrs}, 1_000
    assert attrs.severity == "warning"
  end

  test "reputation alert severity is critical for hostile transitions", %{
    tables: tables,
    pubsub: pubsub,
    registry: registry
  } do
    parent = self()

    _engine =
      start_engine!(
        pubsub: pubsub,
        registry: registry,
        tables: tables,
        create_alert_fun: fn attrs, _opts ->
          send(parent, {:create_alert_called, attrs})
          {:ok, alert_struct(attrs)}
        end,
        dispatch_fun: fn _alert, _config, _notifier, _opts -> :ok end
      )

    Phoenix.PubSub.broadcast(pubsub, "reputation", {
      :reputation_updated,
      reputation_payload(old_tier: :friendly, new_tier: :hostile)
    })

    assert_receive {:create_alert_called, attrs}, 1_000
    assert attrs.severity == "critical"
  end

  test "dispatches webhook for reputation threshold alert", %{
    tables: tables,
    pubsub: pubsub,
    registry: registry
  } do
    parent = self()
    tribe_id = 4242

    _engine =
      start_engine!(
        pubsub: pubsub,
        registry: registry,
        tables: tables,
        create_alert_fun: fn attrs, _opts ->
          {:ok, alert_struct(attrs)}
        end,
        get_webhook_config_fun: fn ^tribe_id, _opts ->
          webhook_config_struct(tribe_id: tribe_id)
        end,
        notifier: CapturingNotifier,
        notifier_opts: [test_pid: self()],
        dispatch_fun: fn alert, config, notifier, opts ->
          send(parent, {:dispatch_called, alert, config, notifier, opts})
          notifier.deliver(alert, config, opts)
        end
      )

    Phoenix.PubSub.broadcast(pubsub, "reputation", {
      :reputation_updated,
      reputation_payload(tribe_id: tribe_id)
    })

    assert_receive {:dispatch_called, %Alert{} = alert, config, CapturingNotifier,
                    [test_pid: test_pid]},
                   1_000

    assert alert.type == "reputation_threshold_crossed"
    assert config.tribe_id == tribe_id
    assert test_pid == self()

    assert_receive {:notifier_called, %Alert{type: "reputation_threshold_crossed"}, ^config},
                   1_000
  end

  test "skips alert when reputation tier has not changed", %{
    tables: tables,
    pubsub: pubsub,
    registry: registry
  } do
    parent = self()

    _engine =
      start_engine!(
        pubsub: pubsub,
        registry: registry,
        tables: tables,
        create_alert_fun: fn attrs, _opts ->
          send(parent, {:create_alert_called, attrs})
          {:ok, alert_struct(attrs)}
        end,
        dispatch_fun: fn _alert, _config, _notifier, _opts -> :ok end
      )

    Phoenix.PubSub.broadcast(pubsub, "reputation", {
      :reputation_updated,
      reputation_payload(
        target_tribe_name: "Probe A",
        score: -101,
        old_tier: :neutral,
        new_tier: :unfriendly
      )
    })

    Phoenix.PubSub.broadcast(pubsub, "reputation", {
      :reputation_updated,
      reputation_payload(
        target_tribe_name: "Probe B",
        score: -202,
        old_tier: :neutral,
        new_tier: :neutral
      )
    })

    Phoenix.PubSub.broadcast(pubsub, "reputation", {
      :reputation_updated,
      reputation_payload(
        target_tribe_name: "Probe C",
        score: -303,
        old_tier: :friendly,
        new_tier: :unfriendly
      )
    })

    assert_receive {:create_alert_called, first_attrs}, 1_000
    assert first_attrs.message =~ "Probe A"
    assert first_attrs.metadata.score == -101

    assert_receive {:create_alert_called, second_attrs}, 1_000
    assert second_attrs.message =~ "Probe C"
    assert second_attrs.metadata.score == -303

    refute_receive {:create_alert_called, _attrs}, 200
  end

  test "reputation alert message includes tribe name and score", %{
    tables: tables,
    pubsub: pubsub,
    registry: registry
  } do
    parent = self()

    _engine =
      start_engine!(
        pubsub: pubsub,
        registry: registry,
        tables: tables,
        create_alert_fun: fn attrs, _opts ->
          send(parent, {:create_alert_called, attrs})
          {:ok, alert_struct(attrs)}
        end,
        dispatch_fun: fn _alert, _config, _notifier, _opts -> :ok end
      )

    Phoenix.PubSub.broadcast(pubsub, "reputation", {
      :reputation_updated,
      reputation_payload(target_tribe_name: "Wolf Pack", score: -145)
    })

    assert_receive {:create_alert_called, attrs}, 1_000
    assert attrs.message =~ "Wolf Pack"
    assert attrs.message =~ "changed from neutral to unfriendly"
    assert attrs.message =~ "(score: -145)"
    assert attrs.metadata.old_tier == "neutral"
    assert attrs.metadata.new_tier == "unfriendly"
    assert attrs.metadata.score == -145
    assert attrs.metadata.target_tribe_id == 77
  end

  @tag :acceptance
  test "reputation threshold event persists alert and sends Discord notification", %{
    tables: tables,
    pubsub: pubsub,
    registry: registry,
    sandbox_owner: sandbox_owner
  } do
    parent = self()
    owner = owner_address()
    tribe_id = 9_011
    stub_name = stub_name(:engine_reputation_acceptance)

    assert {:ok, _config} =
             Alerts.upsert_webhook_config(
               tribe_id,
               %{
                 "webhook_url" => "https://discord.example/webhooks/reputation-acceptance",
                 "service_type" => "discord",
                 "enabled" => true
               },
               []
             )

    Req.Test.expect(stub_name, fn conn ->
      payload = request_body(conn)
      [embed] = payload["embeds"]

      assert embed["title"] == "Reputation Threshold Crossed"
      assert embed["description"] =~ "Standing with Ghost Frogs changed from friendly to hostile"
      assert embed["description"] =~ "(score: -640)"
      refute embed["description"] =~ "N/A"
      refute embed["description"] =~ "error"
      send(parent, :reputation_webhook_received)

      Req.Test.json(conn, %{"ok" => true})
    end)

    _engine =
      start_engine!(
        pubsub: pubsub,
        registry: registry,
        tables: tables,
        sandbox_owner: sandbox_owner,
        notifier: Sigil.Alerts.WebhookNotifier.Discord,
        notifier_opts: [req_options: [plug: {Req.Test, stub_name}], delay_fun: fn _ms -> :ok end],
        dispatch_fun: fn alert, config, notifier, opts ->
          notifier.deliver(alert, config, opts)
        end
      )

    Phoenix.PubSub.broadcast(pubsub, "reputation", {
      :reputation_updated,
      reputation_payload(
        tribe_id: tribe_id,
        account_address: owner,
        old_tier: :friendly,
        new_tier: :hostile,
        score: -640,
        target_tribe_name: "Ghost Frogs"
      )
    })

    assert_receive :reputation_webhook_received, 1_000

    alerts = Alerts.list_alerts([account_address: owner], [])
    assert length(alerts) == 1
    assert Enum.at(alerts, 0).type == "reputation_threshold_crossed"
    assert Enum.at(alerts, 0).tribe_id == tribe_id
    assert Enum.at(alerts, 0).assembly_id == nil
    assert Enum.at(alerts, 0).message =~ "Ghost Frogs"
    assert Enum.at(alerts, 0).message =~ "(score: -640)"
    refute Enum.any?(alerts, &(&1.type == "fuel_low"))
    assert :ok = Req.Test.verify!(stub_name)
  end

  defp reputation_payload(overrides) do
    base = %{
      tribe_id: 42,
      target_tribe_id: 77,
      account_address: owner_address(),
      score: -250,
      old_tier: :neutral,
      new_tier: :unfriendly,
      target_tribe_name: "Ghost Frogs"
    }

    Enum.into(overrides, base)
  end

  defp start_engine!(opts) do
    {:ok, engine} =
      Sigil.Alerts.Engine.start_link(
        Keyword.merge(
          [purge_interval_ms: 86_400_000, discovery_interval_ms: 86_400_000],
          opts
        )
      )

    _state = Sigil.Alerts.Engine.get_state(engine)

    on_exit(fn ->
      if Process.alive?(engine) do
        try do
          GenServer.stop(engine, :normal, :infinity)
        catch
          :exit, _ -> :ok
        end
      end
    end)

    engine
  end

  defp discover!(engine) do
    send(engine, :discover_monitors)
    Sigil.Alerts.Engine.get_state(engine)
  end

  defp put_owner_context!(tables, assembly, owner_address, tribe_id) do
    Cache.put(tables.assemblies, assembly.id, {owner_address, assembly})

    Cache.put(
      tables.accounts,
      owner_address,
      %Account{address: owner_address, characters: [], tribe_id: tribe_id}
    )
  end

  defp fuel_low_payload(assembly) do
    %{assembly: assembly, depletion: nil, changes: []}
  end

  defp insert_alert!(overrides) do
    attrs =
      %{
        "type" => "fuel_low",
        "severity" => "warning",
        "status" => "new",
        "assembly_id" => "assembly-#{System.unique_integer([:positive])}",
        "assembly_name" => "Gate Alpha",
        "account_address" => owner_address(),
        "tribe_id" => 42,
        "message" => "Fuel is trending low",
        "metadata" => %{"source" => "engine"}
      }
      |> Map.merge(overrides)

    %Alert{}
    |> Alert.changeset(attrs)
    |> Sigil.Repo.insert!()
  end

  defp alert_struct(attrs) do
    timestamp = DateTime.utc_now()

    struct!(Alert, %{
      id: System.unique_integer([:positive]),
      type: attrs.type,
      severity: attrs.severity,
      status: "new",
      assembly_id: attrs.assembly_id,
      assembly_name: attrs.assembly_name,
      account_address: attrs.account_address,
      tribe_id: attrs.tribe_id,
      message: attrs.message,
      metadata: attrs.metadata,
      inserted_at: timestamp,
      updated_at: timestamp
    })
  end

  defp webhook_config_struct(overrides) do
    base = %{tribe_id: 42, webhook_url: "https://discord.example/webhooks/42", enabled: true}

    overrides
    |> Enum.into(base)
    |> then(&struct!(Sigil.Alerts.WebhookConfig, &1))
  end

  defp network_node_fixture(overrides) do
    base = %NetworkNode{
      id: "assembly-1",
      key: %TenantItemId{item_id: 7, tenant: "0xtenant"},
      owner_cap_id: "0xowner-cap",
      type_id: 501,
      status: %AssemblyStatus{status: :online},
      location: %Location{location_hash: :binary.copy(<<7>>, 32)},
      fuel: fuel_fixture(),
      energy_source: %{
        max_energy_production: 10_000,
        current_energy_production: 2_500,
        total_reserved_energy: 1_250
      },
      metadata: %Metadata{
        assembly_id: "metadata-1",
        name: "Gate Alpha",
        description: "Acceptance fixture",
        url: "https://example.test/assemblies/gate-alpha"
      },
      connected_assembly_ids: ["assembly-a", "assembly-b"]
    }

    Enum.reduce(overrides, base, fn {key, value}, assembly -> Map.put(assembly, key, value) end)
  end

  defp gate_fixture(overrides) do
    base = %Gate{
      id: "assembly-gate",
      key: %TenantItemId{item_id: 8, tenant: "0xtenant"},
      owner_cap_id: "0xgate-owner-cap",
      type_id: 9_001,
      linked_gate_id: nil,
      status: %AssemblyStatus{status: :online},
      location: %Location{location_hash: :binary.copy(<<8>>, 32)},
      energy_source_id: "0xenergy-source",
      metadata: %Metadata{
        assembly_id: "metadata-gate",
        name: "Gate Alpha",
        description: "Gate fixture",
        url: "https://example.test/gates/gate-alpha"
      },
      extension: nil
    }

    Enum.reduce(overrides, base, fn {key, value}, gate -> Map.put(gate, key, value) end)
  end

  defp fuel_fixture(overrides \\ []) do
    now = System.os_time(:millisecond)

    base = %Fuel{
      max_capacity: 100,
      burn_rate_in_ms: 1_000,
      type_id: 42,
      unit_volume: 2,
      quantity: 15,
      is_burning: true,
      previous_cycle_elapsed_time: 0,
      burn_start_time: now,
      last_updated: now
    }

    Enum.reduce(overrides, base, fn {key, value}, fuel -> Map.put(fuel, key, value) end)
  end

  defp owner_address do
    "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  end

  defp request_body(conn) do
    {:ok, body, _conn} = read_body(conn)
    Jason.decode!(body)
  end

  defp unique_pubsub_name do
    :"alert_engine_pubsub_#{System.unique_integer([:positive])}"
  end

  defp unique_registry_name do
    :"alert_engine_registry_#{System.unique_integer([:positive])}"
  end

  defp stub_name(prefix), do: {prefix, System.unique_integer([:positive])}
end
