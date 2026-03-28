defmodule Sigil.Reputation.EventParserTest do
  @moduledoc """
  Covers the packet 3 chain event parser contract from the approved spec.
  """

  use ExUnit.Case, async: true

  @compile {:no_warn_undefined, Sigil.Reputation.EventParser}

  alias Sigil.Accounts.Account
  alias Sigil.Cache
  alias Sigil.Reputation.EventParser
  alias Sigil.Sui.Types.{AssemblyStatus, Character, Gate, Location, TenantItemId, Turret}

  @timestamp ~U[2026-03-27 12:00:00Z]
  @checkpoint_seq 77

  setup do
    cache_pid =
      start_supervised!({Cache, tables: [:characters, :assemblies, :gate_network, :accounts]})

    {:ok, tables: Cache.tables(cache_pid)}
  end

  @tag :acceptance
  test "parsing a killmail event produces killer and victim tribe attribution for scoring", %{
    tables: tables
  } do
    Cache.put(tables.characters, "0xkiller", character_fixture("0xkiller", 314))
    Cache.put(tables.characters, "0xvictim", character_fixture("0xvictim", 271))

    assert {:ok, event} =
             EventParser.parse_event(
               :killmail_created,
               killmail_raw("0xkiller", "0xvictim"),
               parse_opts(tables)
             )

    assert event.__struct__ == Sigil.Reputation.Events.KillmailEvent
    assert event.killer_character_id == "0xkiller"
    assert event.victim_character_id == "0xvictim"
    assert event.killer_tribe_id == 314
    assert event.victim_tribe_id == 271
    assert event.loss_type == "ship"
    assert event.timestamp == @timestamp
    assert event.checkpoint_seq == @checkpoint_seq
    refute is_nil(event.killer_tribe_id)
    refute is_nil(event.victim_tribe_id)
  end

  test "parses jump event with character and gate tribe resolution", %{tables: tables} do
    Cache.put(tables.characters, "0xpilot", character_fixture("0xpilot", 314))
    put_gate_owner(tables, gate_fixture("0xsource-gate", "0xowner-cap", 444), "0xowner", 444)

    assert {:ok, event} =
             EventParser.parse_event(
               :jump,
               jump_raw("0xpilot", "0xsource-gate", "0xdestination-gate"),
               parse_opts(tables)
             )

    assert event.__struct__ == Sigil.Reputation.Events.JumpEvent
    assert event.character_id == "0xpilot"
    assert event.character_tribe_id == 314
    assert event.source_gate_id == "0xsource-gate"
    assert event.source_gate_owner_tribe_id == 444
    assert event.destination_gate_id == "0xdestination-gate"
    assert event.timestamp == @timestamp
    assert event.checkpoint_seq == @checkpoint_seq
  end

  test "parses priority list event as aggressor event with tribe resolution", %{tables: tables} do
    Cache.put(tables.characters, "0xaggressor", character_fixture("0xaggressor", 909))
    put_turret_owner(tables, turret_fixture("0xturret", "0xturret-cap"), "0xturret-owner", 808)

    assert {:ok, event} =
             EventParser.parse_event(
               :priority_list_updated,
               priority_list_raw("0xturret", "0xaggressor"),
               parse_opts(tables)
             )

    assert event.__struct__ == Sigil.Reputation.Events.AggressorEvent
    assert event.turret_id == "0xturret"
    assert event.turret_owner_tribe_id == 808
    assert event.aggressor_character_id == "0xaggressor"
    assert event.aggressor_tribe_id == 909
    assert event.timestamp == @timestamp
    assert event.checkpoint_seq == @checkpoint_seq
  end

  test "sets tribe_id to nil when character not found in ETS", %{tables: tables} do
    Cache.put(tables.characters, "0xvictim", character_fixture("0xvictim", 271))

    assert {:ok, event} =
             EventParser.parse_event(
               :killmail_created,
               killmail_raw("0xmissing-killer", "0xvictim"),
               parse_opts(tables)
             )

    assert event.killer_tribe_id == nil
    assert event.victim_tribe_id == 271
  end

  test "sets gate owner tribe_id to nil when gate not found in ETS", %{tables: tables} do
    Cache.put(tables.characters, "0xpilot", character_fixture("0xpilot", 314))

    assert {:ok, event} =
             EventParser.parse_event(
               :jump,
               jump_raw("0xpilot", "0xunknown-gate", "0xdestination-gate"),
               parse_opts(tables)
             )

    assert event.character_tribe_id == 314
    assert event.source_gate_owner_tribe_id == nil
  end

  test "sets turret owner tribe_id to nil when turret not found in ETS", %{tables: tables} do
    Cache.put(tables.characters, "0xaggressor", character_fixture("0xaggressor", 909))

    assert {:ok, event} =
             EventParser.parse_event(
               :priority_list_updated,
               priority_list_raw("0xmissing-turret", "0xaggressor"),
               parse_opts(tables)
             )

    assert event.aggressor_tribe_id == 909
    assert event.turret_owner_tribe_id == nil
  end

  test "returns error for nil raw event data", %{tables: tables} do
    assert {:error, :nil_event_data} =
             EventParser.parse_event(:killmail_created, nil, parse_opts(tables))
  end

  test "returns error for missing required field in raw event data", %{tables: tables} do
    assert {:error, {:missing_field, :killer}} =
             EventParser.parse_event(
               :killmail_created,
               %{
                 "victim" => "0xvictim",
                 "loss_type" => "ship"
               },
               parse_opts(tables)
             )
  end

  test "returns error for invalid optional solar system field", %{tables: tables} do
    assert {:error, {:invalid_field, :solar_system}} =
             EventParser.parse_event(
               :killmail_created,
               %{
                 "killer" => "0xkiller",
                 "victim" => "0xvictim",
                 "loss_type" => "ship",
                 "solar_system" => 123
               },
               parse_opts(tables)
             )
  end

  test "returns error for unknown event type", %{tables: tables} do
    assert {:error, {:unknown_event_type, :unknown_event}} =
             EventParser.parse_event(:unknown_event, %{"ignored" => true}, parse_opts(tables))
  end

  test "batch parsing skips failed events and returns successful ones in order", %{tables: tables} do
    Cache.put(tables.characters, "0xkiller", character_fixture("0xkiller", 314))
    Cache.put(tables.characters, "0xvictim", character_fixture("0xvictim", 271))
    Cache.put(tables.characters, "0xpilot", character_fixture("0xpilot", 808))
    put_gate_owner(tables, gate_fixture("0xsource-gate", "0xowner-cap", 444), "0xowner", 444)

    parsed_events =
      EventParser.parse_checkpoint_events(
        [
          {:killmail_created, killmail_raw("0xkiller", "0xvictim"), 11},
          {:killmail_created, %{"victim" => "0xvictim"}, 12},
          {:jump, jump_raw("0xpilot", "0xsource-gate", "0xdestination-gate"), 13}
        ],
        tables: tables,
        now_fun: fn -> @timestamp end
      )

    assert Enum.map(parsed_events, & &1.__struct__) == [
             Sigil.Reputation.Events.KillmailEvent,
             Sigil.Reputation.Events.JumpEvent
           ]

    assert Enum.map(parsed_events, & &1.checkpoint_seq) == [11, 13]
  end

  test "parse_checkpoint_events with empty list returns empty list", %{tables: tables} do
    assert EventParser.parse_checkpoint_events([], tables: tables, now_fun: fn -> @timestamp end) ==
             []
  end

  test "batch parsing returns empty list when every event fails", %{tables: tables} do
    assert EventParser.parse_checkpoint_events(
             [
               {:killmail_created, %{"victim" => "0xvictim"}, 11},
               {:unknown_event, %{"ignored" => true}, 12}
             ],
             tables: tables,
             now_fun: fn -> @timestamp end
           ) == []
  end

  test "parse functions do not modify ETS tables or produce side effects", %{tables: tables} do
    Cache.put(tables.characters, "0xkiller", character_fixture("0xkiller", 314))
    Cache.put(tables.characters, "0xvictim", character_fixture("0xvictim", 271))
    put_gate_owner(tables, gate_fixture("0xsource-gate", "0xowner-cap", 444), "0xowner", 444)
    put_turret_owner(tables, turret_fixture("0xturret", "0xturret-cap"), "0xturret-owner", 808)

    snapshot_before = table_snapshot(tables)
    {:message_queue_len, mailbox_before} = Process.info(self(), :message_queue_len)

    assert {:ok, _killmail} =
             EventParser.parse_event(
               :killmail_created,
               killmail_raw("0xkiller", "0xvictim"),
               parse_opts(tables)
             )

    assert {:ok, _jump} =
             EventParser.parse_event(
               :jump,
               jump_raw("0xkiller", "0xsource-gate", "0xdestination-gate"),
               parse_opts(tables)
             )

    assert {:ok, _aggressor} =
             EventParser.parse_event(
               :priority_list_updated,
               priority_list_raw("0xturret", "0xkiller"),
               parse_opts(tables)
             )

    assert table_snapshot(tables) == snapshot_before
    assert Process.info(self(), :message_queue_len) == {:message_queue_len, mailbox_before}
  end

  defp parse_opts(tables) do
    [tables: tables, checkpoint_seq: @checkpoint_seq, now_fun: fn -> @timestamp end]
  end

  defp put_gate_owner(tables, gate, owner_address, owner_tribe_id) do
    Cache.put(tables.gate_network, gate.id, gate)
    Cache.put(tables.assemblies, gate.id, {owner_address, gate})
    Cache.put(tables.assemblies, gate.owner_cap_id, {owner_address, gate})
    Cache.put(tables.accounts, owner_address, account_fixture(owner_address, owner_tribe_id))
  end

  defp put_turret_owner(tables, turret, owner_address, owner_tribe_id) do
    Cache.put(tables.assemblies, turret.id, {owner_address, turret})
    Cache.put(tables.assemblies, turret.owner_cap_id, {owner_address, turret})
    Cache.put(tables.accounts, owner_address, account_fixture(owner_address, owner_tribe_id))
  end

  defp table_snapshot(tables) do
    Enum.into(tables, %{}, fn {name, table} ->
      {name, MapSet.new(:ets.tab2list(table))}
    end)
  end

  defp character_fixture(id, tribe_id) do
    struct!(Character,
      id: id,
      key: tenant_item_id(id),
      tribe_id: tribe_id,
      character_address: "#{id}-address",
      metadata: nil,
      owner_cap_id: "#{id}-owner-cap"
    )
  end

  defp gate_fixture(id, owner_cap_id, type_id) do
    struct!(Gate,
      id: id,
      key: tenant_item_id(id),
      owner_cap_id: owner_cap_id,
      type_id: type_id,
      linked_gate_id: nil,
      status: %AssemblyStatus{status: :online},
      location: %Location{location_hash: location_hash(1)},
      energy_source_id: nil,
      metadata: nil,
      extension: nil
    )
  end

  defp turret_fixture(id, owner_cap_id) do
    struct!(Turret,
      id: id,
      key: tenant_item_id(id),
      owner_cap_id: owner_cap_id,
      type_id: 73,
      status: %AssemblyStatus{status: :online},
      location: %Location{location_hash: location_hash(2)},
      energy_source_id: nil,
      metadata: nil,
      extension: nil
    )
  end

  defp account_fixture(address, tribe_id) do
    struct!(Account, address: address, characters: [], tribe_id: tribe_id)
  end

  defp tenant_item_id(seed) do
    struct!(TenantItemId, item_id: positive_integer(seed), tenant: "test-tenant")
  end

  defp positive_integer(seed) do
    seed
    |> :erlang.phash2(9_999_999)
    |> max(1)
  end

  defp location_hash(byte) do
    :binary.copy(<<byte>>, 32)
  end

  defp killmail_raw(killer_id, victim_id) do
    %{
      "killer" => killer_id,
      "victim" => victim_id,
      "solar_system" => "0xsystem-1",
      "loss_type" => "ship"
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
end
