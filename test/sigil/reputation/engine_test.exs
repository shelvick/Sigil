defmodule Sigil.Reputation.EngineTest do
  @moduledoc """
  Covers the packet 5 reputation engine contract.
  """

  use Sigil.DataCase, async: true

  @compile {:no_warn_undefined, Sigil.Reputation.Engine}

  alias Sigil.Cache
  alias Sigil.Repo
  alias Sigil.Reputation.ReputationScore
  alias Sigil.Sui.Types.{AssemblyStatus, Character, Gate, Location, TenantItemId}

  @base_now ~U[2026-03-28 12:00:00Z]

  setup %{sandbox_owner: sandbox_owner} do
    cache_pid =
      start_supervised!(
        {Cache,
         tables: [:reputation, :assemblies, :accounts, :characters, :gate_network, :standings]}
      )

    pubsub = unique_pubsub_name()
    start_supervised!({Phoenix.PubSub, name: pubsub})
    :ok = Phoenix.PubSub.subscribe(pubsub, Sigil.Worlds.topic("test", "reputation"))

    {:ok, tables: Cache.tables(cache_pid), pubsub: pubsub, sandbox_owner: sandbox_owner}
  end

  test "kill event computes score delta from standings", %{
    tables: tables,
    pubsub: pubsub,
    sandbox_owner: sandbox_owner
  } do
    put_character!(tables, "0xkiller", 200)
    put_character!(tables, "0xvictim", 100)
    put_standing!(tables, 100, 200, 0)

    _engine = start_engine!(tables: tables, pubsub: pubsub, sandbox_owner: sandbox_owner)

    Phoenix.PubSub.broadcast(pubsub, Sigil.Worlds.topic("test", "chain_events"), {
      :chain_event,
      :killmail_created,
      killmail_raw("0xkiller", "0xvictim"),
      101
    })

    assert_receive {:reputation_updated, payload}, 1_000
    assert payload.tribe_id == 100
    assert payload.target_tribe_id == 200
    assert payload.score == -50
  end

  test "kill event applies aggressor multiplier", %{
    tables: tables,
    pubsub: pubsub,
    sandbox_owner: sandbox_owner
  } do
    put_character!(tables, "0xkiller", 200)
    put_character!(tables, "0xvictim", 100)
    put_standing!(tables, 100, 200, 0)

    _engine =
      start_engine!(
        tables: tables,
        pubsub: pubsub,
        sandbox_owner: sandbox_owner,
        now_fun: fn -> @base_now end
      )

    Phoenix.PubSub.broadcast(pubsub, Sigil.Worlds.topic("test", "chain_events"), {
      :chain_event,
      :priority_list_updated,
      priority_list_raw("0xturret", "0xkiller"),
      102
    })

    Phoenix.PubSub.broadcast(pubsub, Sigil.Worlds.topic("test", "chain_events"), {
      :chain_event,
      :killmail_created,
      killmail_raw("0xkiller", "0xvictim"),
      103
    })

    assert_receive {:reputation_updated, payload}, 1_000
    assert payload.score == -150
  end

  test "kill event applies grid multiplier from last_gate", %{
    tables: tables,
    pubsub: pubsub,
    sandbox_owner: sandbox_owner
  } do
    put_character!(tables, "0xkiller", 200)
    put_character!(tables, "0xvictim", 100)
    put_standing!(tables, 100, 200, 0)
    put_gate_owner!(tables, "0xgate-a", "0xowner-cap-a", "0xowner-a", 100)

    _engine = start_engine!(tables: tables, pubsub: pubsub, sandbox_owner: sandbox_owner)

    Phoenix.PubSub.broadcast(pubsub, Sigil.Worlds.topic("test", "chain_events"), {
      :chain_event,
      :jump,
      jump_raw("0xvictim", "0xgate-a", "0xgate-b"),
      104
    })

    Phoenix.PubSub.broadcast(pubsub, Sigil.Worlds.topic("test", "chain_events"), {
      :chain_event,
      :killmail_created,
      killmail_raw("0xkiller", "0xvictim"),
      105
    })

    assert_receive {:reputation_updated, payload}, 1_000
    assert payload.score == -100
  end

  test "jump event updates last_gate and jump score", %{
    tables: tables,
    pubsub: pubsub,
    sandbox_owner: sandbox_owner
  } do
    put_character!(tables, "0xpilot", 200)
    put_gate_owner!(tables, "0xgate-a", "0xowner-cap-a", "0xowner-a", 100)

    _engine = start_engine!(tables: tables, pubsub: pubsub, sandbox_owner: sandbox_owner)

    Phoenix.PubSub.broadcast(pubsub, Sigil.Worlds.topic("test", "chain_events"), {
      :chain_event,
      :jump,
      jump_raw("0xpilot", "0xgate-a", "0xgate-b"),
      106
    })

    assert_receive {:reputation_updated, payload}, 1_000
    assert payload.tribe_id == 100
    assert payload.target_tribe_id == 200
    assert payload.score == 5
    assert Cache.get(tables.reputation, {:last_gate, "0xpilot"}) == 100
  end

  test "priority_list event stores aggressor timestamp", %{
    tables: tables,
    pubsub: pubsub,
    sandbox_owner: sandbox_owner
  } do
    put_character!(tables, "0xaggressor", 333)

    engine =
      start_engine!(
        tables: tables,
        pubsub: pubsub,
        sandbox_owner: sandbox_owner,
        now_fun: fn -> @base_now end
      )

    Phoenix.PubSub.broadcast(pubsub, Sigil.Worlds.topic("test", "chain_events"), {
      :chain_event,
      :priority_list_updated,
      priority_list_raw("0xturret", "0xaggressor"),
      107
    })

    state = Sigil.Reputation.Engine.get_state(engine)
    assert is_map_key(state.aggressor_flags, 333)
  end

  test "expired aggressor flag does not apply multiplier", %{
    tables: tables,
    pubsub: pubsub,
    sandbox_owner: sandbox_owner
  } do
    put_character!(tables, "0xkiller", 200)
    put_character!(tables, "0xvictim", 100)
    put_standing!(tables, 100, 200, 0)

    clock = start_supervised!({Agent, fn -> @base_now end})

    now_fun = fn -> Agent.get(clock, & &1) end

    engine =
      start_engine!(
        tables: tables,
        pubsub: pubsub,
        sandbox_owner: sandbox_owner,
        now_fun: now_fun
      )

    send(engine, {
      :chain_event,
      :priority_list_updated,
      priority_list_raw("0xturret", "0xkiller"),
      108
    })

    state_after_priority = Sigil.Reputation.Engine.get_state(engine)
    assert is_map_key(state_after_priority.aggressor_flags, 200)

    Agent.update(clock, fn now -> DateTime.add(now, 31 * 60, :second) end)

    Phoenix.PubSub.broadcast(pubsub, Sigil.Worlds.topic("test", "chain_events"), {
      :chain_event,
      :killmail_created,
      killmail_raw("0xkiller", "0xvictim"),
      109
    })

    assert_receive {:reputation_updated, payload}, 1_000
    assert payload.score == -50
  end

  test "jump then kill feeds grid multiplier", %{
    tables: tables,
    pubsub: pubsub,
    sandbox_owner: sandbox_owner
  } do
    put_character!(tables, "0xkiller", 200)
    put_character!(tables, "0xvictim", 100)
    put_standing!(tables, 100, 200, 0)
    put_gate_owner!(tables, "0xgate-a", "0xowner-cap-a", "0xowner-a", 100)

    _engine = start_engine!(tables: tables, pubsub: pubsub, sandbox_owner: sandbox_owner)

    Phoenix.PubSub.broadcast(pubsub, Sigil.Worlds.topic("test", "chain_events"), {
      :chain_event,
      :jump,
      jump_raw("0xvictim", "0xgate-a", "0xgate-b"),
      110
    })

    Phoenix.PubSub.broadcast(pubsub, Sigil.Worlds.topic("test", "chain_events"), {
      :chain_event,
      :killmail_created,
      killmail_raw("0xkiller", "0xvictim"),
      111
    })

    assert_receive {:reputation_updated, payload}, 1_000
    assert payload.score == -100
  end

  test "decay tick reduces scores toward zero", %{
    tables: tables,
    pubsub: pubsub,
    sandbox_owner: sandbox_owner
  } do
    put_score!(tables, 100, 200, 900)

    engine = start_engine!(tables: tables, pubsub: pubsub, sandbox_owner: sandbox_owner)

    send(engine, :decay_tick)
    _state = Sigil.Reputation.Engine.get_state(engine)

    updated = Cache.get(tables.reputation, {:reputation_score, 100, 200})
    assert updated.score < 900
    assert updated.score > 0
  end

  test "threshold crossing triggers oracle submit", %{
    tables: tables,
    pubsub: pubsub,
    sandbox_owner: sandbox_owner
  } do
    put_character!(tables, "0xkiller", 200)
    put_character!(tables, "0xvictim", 100)
    put_standing!(tables, 100, 200, 0)
    put_active_custodian!(tables, 100, "0xleader")
    put_score!(tables, 100, 200, -180)

    parent = self()

    _engine =
      start_engine!(
        tables: tables,
        pubsub: pubsub,
        sandbox_owner: sandbox_owner,
        signer_keypair: <<1, 2, 3>>,
        submit_fn: fn args ->
          send(parent, {:oracle_submit_called, args})
          {:ok, :submitted}
        end
      )

    Phoenix.PubSub.broadcast(pubsub, Sigil.Worlds.topic("test", "chain_events"), {
      :chain_event,
      :killmail_created,
      killmail_raw("0xkiller", "0xvictim"),
      112
    })

    assert_receive {:oracle_submit_called, args}, 1_000
    assert args.target_tribe_id == 200
  end

  test "pinned pair skips oracle submission", %{
    tables: tables,
    pubsub: pubsub,
    sandbox_owner: sandbox_owner
  } do
    put_character!(tables, "0xkiller", 200)
    put_character!(tables, "0xvictim", 100)
    put_standing!(tables, 100, 200, 0)
    put_active_custodian!(tables, 100, "0xleader")
    put_score!(tables, 100, 200, -180, pinned: true, pinned_standing: 2)

    parent = self()

    _engine =
      start_engine!(
        tables: tables,
        pubsub: pubsub,
        sandbox_owner: sandbox_owner,
        signer_keypair: <<1, 2, 3>>,
        submit_fn: fn args ->
          send(parent, {:oracle_submit_called, args})
          {:ok, :submitted}
        end
      )

    Phoenix.PubSub.broadcast(pubsub, Sigil.Worlds.topic("test", "chain_events"), {
      :chain_event,
      :killmail_created,
      killmail_raw("0xkiller", "0xvictim"),
      113
    })

    assert_receive {:reputation_updated, _payload}, 1_000
    refute_receive {:oracle_submit_called, _args}, 200
  end

  test "decay tick includes transitive adjustment", %{
    tables: tables,
    pubsub: pubsub,
    sandbox_owner: sandbox_owner
  } do
    put_score!(tables, 100, 500, 0)
    put_standing!(tables, 100, 200, 4)
    put_standing!(tables, 100, 300, 0)
    put_standing!(tables, 200, 500, 4)
    put_standing!(tables, 300, 500, 0)

    engine = start_engine!(tables: tables, pubsub: pubsub, sandbox_owner: sandbox_owner)

    send(engine, :decay_tick)
    _state = Sigil.Reputation.Engine.get_state(engine)

    updated = Cache.get(tables.reputation, {:reputation_score, 100, 500})
    assert updated.score != 0
  end

  test "engine loads scores from database on startup", %{
    tables: tables,
    pubsub: pubsub,
    sandbox_owner: sandbox_owner
  } do
    insert_score_row!(source_tribe_id: 100, target_tribe_id: 200, score: 321)

    _engine = start_engine!(tables: tables, pubsub: pubsub, sandbox_owner: sandbox_owner)

    loaded = Cache.get(tables.reputation, {:reputation_score, 100, 200})
    assert loaded.score == 321
  end

  test "flush_state persists dirty scores", %{
    tables: tables,
    pubsub: pubsub,
    sandbox_owner: sandbox_owner
  } do
    put_character!(tables, "0xpilot", 200)
    put_gate_owner!(tables, "0xgate-a", "0xowner-cap-a", "0xowner-a", 100)

    engine = start_engine!(tables: tables, pubsub: pubsub, sandbox_owner: sandbox_owner)

    send(engine, {
      :chain_event,
      :jump,
      jump_raw("0xpilot", "0xgate-a", "0xgate-b"),
      114
    })

    _state_after_jump = Sigil.Reputation.Engine.get_state(engine)

    send(engine, :flush_state)
    _state_after_flush = Sigil.Reputation.Engine.get_state(engine)

    assert Repo.get_by!(ReputationScore, source_tribe_id: 100, target_tribe_id: 200).score == 5
  end

  test "score changes broadcast expected payload", %{
    tables: tables,
    pubsub: pubsub,
    sandbox_owner: sandbox_owner
  } do
    put_character!(tables, "0xpilot", 200)
    put_gate_owner!(tables, "0xgate-a", "0xowner-cap-a", "0xowner-a", 100)

    _engine = start_engine!(tables: tables, pubsub: pubsub, sandbox_owner: sandbox_owner)

    Phoenix.PubSub.broadcast(pubsub, Sigil.Worlds.topic("test", "chain_events"), {
      :chain_event,
      :jump,
      jump_raw("0xpilot", "0xgate-a", "0xgate-b"),
      115
    })

    assert_receive {:reputation_updated, payload}, 1_000
    assert payload.tribe_id == 100
    assert payload.target_tribe_id == 200
    assert payload.old_score == 0
    assert payload.score == 5
    assert is_atom(payload.old_tier)
    assert is_atom(payload.new_tier)
  end

  test "engine returns ignore when disabled", %{tables: tables, pubsub: pubsub} do
    assert :ignore =
             Sigil.Reputation.Engine.start_link(tables: tables, pubsub: pubsub, enabled: false)
  end

  test "kill event with unknown tribe is skipped", %{
    tables: tables,
    pubsub: pubsub,
    sandbox_owner: sandbox_owner
  } do
    put_character!(tables, "0xvictim", 100)

    engine = start_engine!(tables: tables, pubsub: pubsub, sandbox_owner: sandbox_owner)

    send(engine, {
      :chain_event,
      :killmail_created,
      killmail_raw("0xmissing", "0xvictim"),
      116
    })

    _state_after_event = Sigil.Reputation.Engine.get_state(engine)

    refute_receive {:reputation_updated, _payload}, 200
    assert Cache.get(tables.reputation, {:reputation_score, 100, 200}) == nil
  end

  test "same-tribe kill produces no score change", %{
    tables: tables,
    pubsub: pubsub,
    sandbox_owner: sandbox_owner
  } do
    put_character!(tables, "0xkiller", 100)
    put_character!(tables, "0xvictim", 100)

    engine = start_engine!(tables: tables, pubsub: pubsub, sandbox_owner: sandbox_owner)

    send(engine, {
      :chain_event,
      :killmail_created,
      killmail_raw("0xkiller", "0xvictim"),
      117
    })

    _state_after_event = Sigil.Reputation.Engine.get_state(engine)

    refute_receive {:reputation_updated, _payload}, 200
    assert Cache.get(tables.reputation, {:reputation_score, 100, 100}) == nil
  end

  @tag :acceptance
  test "kill event updates score and submits oracle", %{
    tables: tables,
    pubsub: pubsub,
    sandbox_owner: sandbox_owner
  } do
    put_character!(tables, "0xkiller", 200)
    put_character!(tables, "0xvictim", 100)
    put_standing!(tables, 100, 200, 0)
    put_active_custodian!(tables, 100, "0xleader")
    put_score!(tables, 100, 200, -180)

    parent = self()

    engine =
      start_engine!(
        tables: tables,
        pubsub: pubsub,
        sandbox_owner: sandbox_owner,
        signer_keypair: <<1, 2, 3>>,
        submit_fn: fn args ->
          send(parent, {:oracle_submit_called, args})
          {:ok, :submitted}
        end
      )

    Phoenix.PubSub.broadcast(pubsub, Sigil.Worlds.topic("test", "chain_events"), {
      :chain_event,
      :killmail_created,
      killmail_raw("0xkiller", "0xvictim"),
      118
    })

    assert_receive {:reputation_updated, payload}, 1_000
    assert_receive {:oracle_submit_called, args}, 1_000

    send(engine, :flush_state)
    _state = Sigil.Reputation.Engine.get_state(engine)

    persisted = Repo.get_by!(ReputationScore, source_tribe_id: 100, target_tribe_id: 200)

    assert payload.tribe_id == 100
    assert payload.target_tribe_id == 200
    assert payload.new_tier == args.standing
    assert persisted.score == payload.score
    refute payload.score == payload.old_score
    refute is_nil(payload.account_address)
  end

  defp start_engine!(opts) do
    {:ok, engine} =
      Sigil.Reputation.Engine.start_link(
        Keyword.merge(
          [
            decay_interval_ms: 86_400_000,
            flush_interval_ms: 86_400_000,
            enabled: true,
            now_fun: fn -> @base_now end
          ],
          opts
        )
      )

    _state = Sigil.Reputation.Engine.get_state(engine)

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

  defp put_character!(tables, character_id, tribe_id) do
    Cache.put(
      tables.characters,
      character_id,
      %Character{
        id: character_id,
        key: %TenantItemId{item_id: positive_integer(character_id), tenant: "test-tenant"},
        tribe_id: tribe_id,
        character_address: character_id,
        metadata: nil,
        owner_cap_id: character_id <> "-owner-cap"
      }
    )
  end

  defp put_gate_owner!(tables, gate_id, owner_cap_id, owner_address, owner_tribe_id) do
    gate = %Gate{
      id: gate_id,
      key: %TenantItemId{item_id: positive_integer(gate_id), tenant: "test-tenant"},
      owner_cap_id: owner_cap_id,
      type_id: 501,
      linked_gate_id: nil,
      status: %AssemblyStatus{status: :online},
      location: %Location{location_hash: :binary.copy(<<7>>, 32)},
      energy_source_id: nil,
      metadata: nil,
      extension: nil
    }

    Cache.put(tables.gate_network, gate_id, gate)
    Cache.put(tables.assemblies, gate_id, {owner_address, gate})
    Cache.put(tables.assemblies, owner_cap_id, {owner_address, gate})
    Cache.put(tables.accounts, owner_address, %{address: owner_address, tribe_id: owner_tribe_id})
  end

  defp put_standing!(tables, source_tribe_id, target_tribe_id, standing) do
    Cache.put(tables.standings, {:tribe_standing, source_tribe_id, target_tribe_id}, standing)
  end

  defp put_active_custodian!(tables, source_tribe_id, current_leader) do
    Cache.put(tables.standings, {:active_custodian, source_tribe_id}, %{
      object_id: "0xcustodian-#{source_tribe_id}",
      initial_shared_version: 1,
      tribe_id: source_tribe_id,
      current_leader: current_leader
    })
  end

  defp put_score!(tables, source_tribe_id, target_tribe_id, score, opts \\ []) do
    now = Keyword.get(opts, :now, @base_now)

    Cache.put(
      tables.reputation,
      {:reputation_score, source_tribe_id, target_tribe_id},
      %ReputationScore{
        source_tribe_id: source_tribe_id,
        target_tribe_id: target_tribe_id,
        score: score,
        pinned: Keyword.get(opts, :pinned, false),
        pinned_standing: Keyword.get(opts, :pinned_standing),
        last_event_at: now,
        last_decay_at: now,
        tier_thresholds: %{
          hostile_max: -700,
          unfriendly_max: -200,
          friendly_min: 200,
          allied_min: 700
        }
      }
    )
  end

  defp insert_score_row!(overrides) do
    attrs =
      Map.merge(
        %{
          source_tribe_id: 100,
          target_tribe_id: 200,
          score: 0,
          pinned: false,
          pinned_standing: nil,
          last_event_at: @base_now,
          last_decay_at: @base_now,
          tier_thresholds: %{
            hostile_max: -700,
            unfriendly_max: -200,
            friendly_min: 200,
            allied_min: 700
          }
        },
        Enum.into(overrides, %{})
      )

    %ReputationScore{}
    |> ReputationScore.changeset(attrs)
    |> Repo.insert!()
  end

  defp killmail_raw(killer_character_id, victim_character_id) do
    %{
      "killer" => killer_character_id,
      "victim" => victim_character_id,
      "loss_type" => "ship",
      "solar_system" => "0xsolar"
    }
  end

  defp jump_raw(character_id, source_gate_id, destination_gate_id) do
    %{
      "character" => character_id,
      "source_gate" => source_gate_id,
      "destination_gate" => destination_gate_id
    }
  end

  defp priority_list_raw(turret_id, aggressor_character_id) do
    %{
      "turret" => turret_id,
      "aggressor" => aggressor_character_id
    }
  end

  defp positive_integer(seed) do
    seed
    |> :erlang.phash2(9_999_999)
    |> max(1)
  end

  defp unique_pubsub_name do
    :"reputation_engine_pubsub_#{System.unique_integer([:positive])}"
  end
end
