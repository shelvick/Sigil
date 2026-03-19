defmodule Sigil.DiplomacyTest do
  @moduledoc """
  Covers the packet 2 diplomacy context contract from the approved spec.
  """

  use ExUnit.Case, async: true

  import Hammox

  alias Sigil.{Cache, Diplomacy}
  alias Sigil.StaticDataTestFixtures, as: Fixtures
  alias Sigil.Sui.{TransactionBuilder, TxDiplomacy}

  @standings_package_id "0x06ce9d6bed77615383575cc7eba4883d32769b30cd5df00561e38434a59611a1"
  @standings_table_type "#{@standings_package_id}::standings_table::StandingsTable"

  setup :verify_on_exit!

  setup do
    cache_pid = start_supervised!({Cache, tables: [:standings]})
    pubsub = unique_pubsub_name()

    start_supervised!({Phoenix.PubSub, name: pubsub})
    :ok = Phoenix.PubSub.subscribe(pubsub, "diplomacy")

    {:ok, tables: Cache.tables(cache_pid), pubsub: pubsub, sender: sender_address()}
  end

  describe "discover_tables/2" do
    test "discover_tables returns tables owned by address", %{
      tables: tables,
      pubsub: pubsub,
      sender: sender
    } do
      table_one = table_object_json(table_id(0x11), sender, 17)
      table_two = table_object_json(table_id(0x22), sender, 23)

      expect(Sigil.Sui.ClientMock, :get_objects, fn [type: @standings_table_type], [] ->
        {:ok, page([table_one, table_two])}
      end)

      assert {:ok, tables_found} =
               Diplomacy.discover_tables(sender, tables: tables, pubsub: pubsub)

      assert Enum.map(tables_found, & &1.object_id) == [table_id(0x11), table_id(0x22)]
      assert Enum.map(tables_found, & &1.initial_shared_version) == [17, 23]
      assert Enum.map(tables_found, & &1.owner) == [sender, sender]
      assert Enum.all?(tables_found, &(byte_size(&1.object_id_bytes) == 32))
      assert_receive {:table_discovered, ^tables_found}
    end

    test "discover_tables returns empty list when no tables exist", %{
      tables: tables,
      pubsub: pubsub,
      sender: sender
    } do
      expect(Sigil.Sui.ClientMock, :get_objects, fn [type: @standings_table_type], [] ->
        {:ok, page([])}
      end)

      assert Diplomacy.discover_tables(sender, tables: tables, pubsub: pubsub) == {:ok, []}
      assert_receive {:table_discovered, []}
    end

    test "discover_tables auto-selects single table as active", %{
      tables: tables,
      pubsub: pubsub,
      sender: sender
    } do
      table = table_object_json(table_id(0x33), sender, 41)

      expect(Sigil.Sui.ClientMock, :get_objects, fn [type: @standings_table_type], [] ->
        {:ok, page([table])}
      end)

      assert {:ok, [active_table]} =
               Diplomacy.discover_tables(sender, tables: tables, pubsub: pubsub, sender: sender)

      assert Diplomacy.get_active_table(tables: tables, sender: sender) == active_table
    end

    test "discover_tables returns multiple tables without auto-selecting", %{
      tables: tables,
      pubsub: pubsub,
      sender: sender
    } do
      expect(Sigil.Sui.ClientMock, :get_objects, fn [type: @standings_table_type], [] ->
        {:ok,
         page([
           table_object_json(table_id(0x44), sender, 9),
           table_object_json(table_id(0x55), sender, 10)
         ])}
      end)

      assert {:ok, [_first, _second]} =
               Diplomacy.discover_tables(sender, tables: tables, pubsub: pubsub, sender: sender)

      assert Diplomacy.get_active_table(tables: tables, sender: sender) == nil
    end
  end

  describe "standings reads" do
    test "get_standing returns cached standing for known tribe", %{tables: tables} do
      Cache.put(tables.standings, {:tribe_standing, 42}, 0)

      assert Diplomacy.get_standing(42, tables: tables) == :hostile
    end

    test "get_standing returns neutral for unknown tribe", %{tables: tables} do
      assert Diplomacy.get_standing(777, tables: tables) == :neutral
    end

    test "list_standings returns all cached tribe standings", %{tables: tables} do
      Cache.put(tables.standings, {:tribe_standing, 314}, 4)
      Cache.put(tables.standings, {:tribe_standing, 271}, 1)

      standings =
        Diplomacy.list_standings(tables: tables)
        |> Enum.sort_by(& &1.tribe_id)

      assert standings == [
               %{tribe_id: 271, standing: :unfriendly},
               %{tribe_id: 314, standing: :allied}
             ]
    end

    test "list_pilot_standings returns all cached pilot overrides", %{tables: tables} do
      pilot_one = address(0x61)
      pilot_two = address(0x62)

      Cache.put(tables.standings, {:pilot_standing, pilot_two}, 4)
      Cache.put(tables.standings, {:pilot_standing, pilot_one}, 0)

      standings =
        Diplomacy.list_pilot_standings(tables: tables)
        |> Enum.sort_by(& &1.pilot)

      assert standings == [
               %{pilot: pilot_one, standing: :hostile},
               %{pilot: pilot_two, standing: :allied}
             ]
    end

    test "get_pilot_standing returns cached standing for known pilot", %{tables: tables} do
      pilot = address(0x63)
      Cache.put(tables.standings, {:pilot_standing, pilot}, 3)

      assert Diplomacy.get_pilot_standing(pilot, tables: tables) == :friendly
    end

    test "get_pilot_standing returns neutral for unknown pilot", %{tables: tables} do
      assert Diplomacy.get_pilot_standing(address(0x64), tables: tables) == :neutral
    end

    test "get_default_standing returns cached or neutral default", %{tables: tables} do
      assert Diplomacy.get_default_standing(tables: tables) == :neutral

      Cache.put(tables.standings, :default_standing, 1)

      assert Diplomacy.get_default_standing(tables: tables) == :unfriendly
    end

    test "standing values map to correct atoms", %{tables: tables} do
      Cache.put(tables.standings, {:tribe_standing, 0}, 0)
      Cache.put(tables.standings, {:tribe_standing, 1}, 1)
      Cache.put(tables.standings, {:tribe_standing, 2}, 2)
      Cache.put(tables.standings, {:tribe_standing, 3}, 3)
      Cache.put(tables.standings, {:tribe_standing, 4}, 4)

      mapped =
        Diplomacy.list_standings(tables: tables)
        |> Enum.sort_by(& &1.tribe_id)
        |> Enum.map(& &1.standing)

      assert mapped == [:hostile, :unfriendly, :neutral, :friendly, :allied]
    end
  end

  describe "active table selection" do
    test "set_active_table stores the table under the sender scope", %{
      tables: tables,
      sender: sender
    } do
      table = table_info(%{object_id: table_id(0x71), initial_shared_version: 88, owner: sender})

      assert :ok = Diplomacy.set_active_table(table, tables: tables, sender: sender)
      assert Diplomacy.get_active_table(tables: tables, sender: sender) == table
    end

    test "get_active_table returns nil when no table has been selected", %{
      tables: tables,
      sender: sender
    } do
      assert Diplomacy.get_active_table(tables: tables, sender: sender) == nil
    end
  end

  describe "transaction building" do
    test "build_set_standing_tx produces valid Base64 transaction bytes", %{
      tables: tables,
      sender: sender
    } do
      active_table =
        table_info(%{object_id: table_id(0x81), initial_shared_version: 13, owner: sender})

      Cache.put(tables.standings, {:active_table, sender}, active_table)

      # No gas coin mocking — wallet handles gas via Transaction.fromKind()

      assert {:ok, %{tx_bytes: tx_bytes}} =
               Diplomacy.build_set_standing_tx(42, 0, tables: tables, sender: sender)

      assert tx_bytes == expected_set_standing_kind_bytes(active_table, 42, 0)
      assert is_binary(Base.decode64!(tx_bytes))
    end

    test "build_set_standing_tx fails with no_active_table when none selected", %{
      tables: tables,
      sender: sender
    } do
      expect(Sigil.Sui.ClientMock, :get_objects, 0, fn _filters, _opts ->
        {:ok, page([])}
      end)

      assert Diplomacy.build_set_standing_tx(42, 0, tables: tables, sender: sender) ==
               {:error, :no_active_table}
    end

    test "build_create_table_tx produces valid transaction bytes", %{
      tables: tables,
      sender: sender
    } do
      # No gas coin mocking — wallet handles gas via Transaction.fromKind()

      assert {:ok, %{tx_bytes: tx_bytes}} =
               Diplomacy.build_create_table_tx(tables: tables, sender: sender)

      assert tx_bytes == expected_create_table_kind_bytes()
      assert is_binary(Base.decode64!(tx_bytes))
    end

    test "build_batch_set_standings_tx encodes multiple standings", %{
      tables: tables,
      sender: sender
    } do
      active_table =
        table_info(%{object_id: table_id(0x82), initial_shared_version: 14, owner: sender})

      Cache.put(tables.standings, {:active_table, sender}, active_table)

      # No gas coin mocking — wallet handles gas via Transaction.fromKind()

      updates = [{1, 0}, {2, 3}, {3, 4}]

      assert {:ok, %{tx_bytes: tx_bytes}} =
               Diplomacy.build_batch_set_standings_tx(updates, tables: tables, sender: sender)

      assert tx_bytes ==
               expected_batch_set_standings_kind_bytes(active_table, updates)
    end

    test "build_set_pilot_standing_tx produces valid transaction bytes", %{
      tables: tables,
      sender: sender
    } do
      active_table =
        table_info(%{object_id: table_id(0x83), initial_shared_version: 15, owner: sender})

      pilot = address(0x95)
      Cache.put(tables.standings, {:active_table, sender}, active_table)

      # No gas coin mocking — wallet handles gas via Transaction.fromKind()

      assert {:ok, %{tx_bytes: tx_bytes}} =
               Diplomacy.build_set_pilot_standing_tx(pilot, 1, tables: tables, sender: sender)

      assert tx_bytes ==
               expected_set_pilot_standing_kind_bytes(active_table, pilot, 1)
    end

    test "build_set_default_standing_tx produces valid transaction bytes", %{
      tables: tables,
      sender: sender
    } do
      active_table =
        table_info(%{object_id: table_id(0x84), initial_shared_version: 16, owner: sender})

      Cache.put(tables.standings, {:active_table, sender}, active_table)

      # No gas coin mocking — wallet handles gas via Transaction.fromKind()

      assert {:ok, %{tx_bytes: tx_bytes}} =
               Diplomacy.build_set_default_standing_tx(4, tables: tables, sender: sender)

      assert tx_bytes == expected_set_default_standing_kind_bytes(active_table, 4)
    end

    test "build_batch_set_pilot_standings_tx encodes multiple pilot overrides", %{
      tables: tables,
      sender: sender
    } do
      active_table =
        table_info(%{object_id: table_id(0x85), initial_shared_version: 18, owner: sender})

      Cache.put(tables.standings, {:active_table, sender}, active_table)

      # No gas coin mocking — wallet handles gas via Transaction.fromKind()

      updates = [{address(0x96), 0}, {address(0x97), 4}]

      assert {:ok, %{tx_bytes: tx_bytes}} =
               Diplomacy.build_batch_set_pilot_standings_tx(updates,
                 tables: tables,
                 sender: sender
               )

      assert tx_bytes ==
               expected_batch_set_pilot_standings_kind_bytes(active_table, updates)
    end

    test "kind bytes are independent of gas price config", %{sender: sender} do
      active_table =
        table_info(%{object_id: table_id(0x86), initial_shared_version: 19, owner: sender})

      req_options =
        probe_req_options(active_table, [])

      result =
        run_diplomacy_probe!(
          """
          {:ok, cache_pid} = Sigil.Cache.start_link(tables: [:standings])
          tables = Sigil.Cache.tables(cache_pid)

          {:ok, [_table]} =
            Sigil.Diplomacy.discover_tables(#{inspect(sender)},
              tables: tables,
              sender: #{inspect(sender)},
              client: Sigil.DiplomacyTestSuiClient,
              req_options: #{inspect(req_options)}
            )

          {:ok, %{tx_bytes: tx_bytes}} =
            Sigil.Diplomacy.build_set_standing_tx(42, 0,
              tables: tables,
              sender: #{inspect(sender)},
              client: Sigil.DiplomacyTestSuiClient,
              req_options: #{inspect(req_options)}
            )

          IO.write(Jason.encode!(%{tx_bytes: tx_bytes}))
          """,
          reference_gas_price: 4_321
        )

      assert result["tx_bytes"] ==
               expected_set_standing_kind_bytes(active_table, 42, 0)
    end
  end

  describe "transaction submission" do
    test "submit_signed_transaction updates cache and broadcasts on success", %{
      tables: tables,
      pubsub: pubsub,
      sender: sender
    } do
      active_table =
        table_info(%{object_id: table_id(0x91), initial_shared_version: 25, owner: sender})

      Cache.put(tables.standings, {:active_table, sender}, active_table)

      # No gas coin mocking — wallet handles gas via Transaction.fromKind()

      expect(Sigil.Sui.ClientMock, :execute_transaction, fn tx_bytes, ["wallet-signature"], [] ->
        assert tx_bytes == expected_set_standing_kind_bytes(active_table, 42, 0)
        {:ok, success_effects("set-standing-success")}
      end)

      assert {:ok, %{tx_bytes: tx_bytes}} =
               Diplomacy.build_set_standing_tx(42, 0,
                 tables: tables,
                 pubsub: pubsub,
                 sender: sender
               )

      assert {:ok, %{digest: "set-standing-success", effects_bcs: "dGVzdC1lZmZlY3Rz"}} =
               Diplomacy.submit_signed_transaction(tx_bytes, "wallet-signature",
                 tables: tables,
                 pubsub: pubsub,
                 sender: sender
               )

      assert Diplomacy.get_standing(42, tables: tables) == :hostile
      assert_receive {:standing_updated, %{tribe_id: 42, standing: :hostile}}
    end

    test "submit_signed_transaction returns error without modifying cache on failure", %{
      tables: tables,
      pubsub: pubsub,
      sender: sender
    } do
      active_table =
        table_info(%{object_id: table_id(0x92), initial_shared_version: 26, owner: sender})

      Cache.put(tables.standings, {:active_table, sender}, active_table)
      Cache.put(tables.standings, {:tribe_standing, 42}, 3)

      # No gas coin mocking — wallet handles gas via Transaction.fromKind()

      expect(Sigil.Sui.ClientMock, :execute_transaction, fn _tx_bytes, ["wallet-signature"], [] ->
        {:error, {:graphql_errors, [%{"message" => "signature rejected"}]}}
      end)

      assert {:ok, %{tx_bytes: tx_bytes}} =
               Diplomacy.build_set_standing_tx(42, 0,
                 tables: tables,
                 pubsub: pubsub,
                 sender: sender
               )

      assert Diplomacy.submit_signed_transaction(tx_bytes, "wallet-signature",
               tables: tables,
               pubsub: pubsub,
               sender: sender
             ) == {:error, {:graphql_errors, [%{"message" => "signature rejected"}]}}

      assert Diplomacy.get_standing(42, tables: tables) == :friendly
      refute_receive {:standing_updated, _}
    end
  end

  describe "tribe name resolution" do
    test "resolve_tribe_names fetches and caches tribe data" do
      result =
        run_diplomacy_probe!("""
        {:ok, cache_pid} = Sigil.Cache.start_link(tables: [:standings])
        tables = Sigil.Cache.tables(cache_pid)

        {:ok, tribes} =
          Sigil.Diplomacy.resolve_tribe_names(
            tables: tables,
            req_options: [tribes: #{inspect(world_tribe_records())}]
          )

        cached = Sigil.Diplomacy.get_tribe_name(314, tables: tables)

        IO.write(Jason.encode!(%{tribes: tribes, cached: cached}))
        """)

      assert Enum.sort_by(result["tribes"], & &1["id"]) == [
               %{"id" => 271, "name" => "Frontier Defense Union", "short_name" => "FDU"},
               %{"id" => 314, "name" => "Progenitor Collective", "short_name" => "PGCL"}
             ]

      assert result["cached"] == %{
               "id" => 314,
               "name" => "Progenitor Collective",
               "short_name" => "PGCL"
             }
    end

    test "get_tribe_name returns cached tribe or nil", %{tables: tables} do
      Cache.put(tables.standings, {:world_tribe, 314}, %{
        id: 314,
        name: "Progenitor Collective",
        short_name: "PGCL"
      })

      assert Diplomacy.get_tribe_name(314, tables: tables) == %{
               id: 314,
               name: "Progenitor Collective",
               short_name: "PGCL"
             }

      assert Diplomacy.get_tribe_name(999, tables: tables) == nil
    end
  end

  @tag :acceptance
  test "setting a standing builds transaction and updates cache on submission", %{
    tables: tables,
    pubsub: pubsub,
    sender: sender
  } do
    # Full user journey: discover tables -> build tx -> submit -> verify cache + events
    table = table_object_json(table_id(0x99), sender, 31)

    expected_table =
      table_info(%{object_id: table_id(0x99), initial_shared_version: 31, owner: sender})

    # Step 1: Discover tables (single table → auto-select as active)
    expect(Sigil.Sui.ClientMock, :get_objects, fn [type: @standings_table_type], [] ->
      {:ok, page([table])}
    end)

    assert {:ok, [active_table]} =
             Diplomacy.discover_tables(sender,
               tables: tables,
               pubsub: pubsub,
               sender: sender
             )

    assert active_table.object_id == expected_table.object_id
    assert_receive {:table_discovered, [^active_table]}

    # Step 2: Build set_standing transaction (no gas coin mocking — wallet handles gas)
    assert {:ok, %{tx_bytes: tx_bytes}} =
             Diplomacy.build_set_standing_tx(42, 0,
               tables: tables,
               pubsub: pubsub,
               sender: sender
             )

    refute tx_bytes == nil
    assert is_binary(Base.decode64!(tx_bytes))

    # Step 3: Submit signed transaction
    expect(Sigil.Sui.ClientMock, :execute_transaction, fn ^tx_bytes, ["wallet-sig"], [] ->
      {:ok, success_effects("acceptance-digest")}
    end)

    assert {:ok, %{digest: "acceptance-digest", effects_bcs: "dGVzdC1lZmZlY3Rz"}} =
             Diplomacy.submit_signed_transaction(tx_bytes, "wallet-sig",
               tables: tables,
               pubsub: pubsub,
               sender: sender
             )

    # Step 4: Verify cache updated + PubSub event broadcast
    assert Diplomacy.get_standing(42, tables: tables) == :hostile
    assert_receive {:standing_updated, %{tribe_id: 42, standing: :hostile}}

    # Step 5: Verify no unexpected events
    refute_receive {:default_standing_updated, _}
  end

  defp unique_pubsub_name do
    :"diplomacy_pubsub_#{System.unique_integer([:positive])}"
  end

  defp sender_address do
    address(0xAA)
  end

  defp address(byte) do
    "0x" <> Base.encode16(:binary.copy(<<byte>>, 32), case: :lower)
  end

  defp table_id(byte), do: address(byte)
  defp object_id(byte), do: :binary.copy(<<byte>>, 32)

  defp table_info(overrides) do
    Map.merge(
      %{
        object_id: table_id(0x11),
        object_id_bytes: object_id(0x11),
        initial_shared_version: 9,
        owner: sender_address()
      },
      overrides
      |> normalize_object_id_bytes()
    )
  end

  defp normalize_object_id_bytes(%{object_id: object_id} = overrides) when is_binary(object_id) do
    Map.put_new(overrides, :object_id_bytes, hex_to_bytes(object_id))
  end

  defp normalize_object_id_bytes(overrides), do: overrides

  defp table_object_json(object_id, owner, initial_shared_version) do
    %{
      "id" => object_id,
      "address" => object_id,
      "owner" => owner,
      "initialSharedVersion" => Integer.to_string(initial_shared_version),
      "initial_shared_version" => initial_shared_version,
      "shared" => %{"initialSharedVersion" => Integer.to_string(initial_shared_version)}
    }
  end

  defp page(entries) do
    %{data: entries, has_next_page: false, end_cursor: nil}
  end

  defp expected_set_standing_kind_bytes(table, tribe_id, standing) do
    table
    |> diplomacy_table_ref()
    |> TxDiplomacy.build_set_standing(tribe_id, standing, [])
    |> TransactionBuilder.build_kind!()
    |> Base.encode64()
  end

  defp expected_create_table_kind_bytes do
    []
    |> TxDiplomacy.build_create_table()
    |> TransactionBuilder.build_kind!()
    |> Base.encode64()
  end

  defp expected_batch_set_standings_kind_bytes(table, updates) do
    table
    |> diplomacy_table_ref()
    |> TxDiplomacy.build_batch_set_standings(updates, [])
    |> TransactionBuilder.build_kind!()
    |> Base.encode64()
  end

  defp expected_set_pilot_standing_kind_bytes(table, pilot, standing) do
    table
    |> diplomacy_table_ref()
    |> TxDiplomacy.build_set_pilot_standing(hex_to_bytes(pilot), standing, [])
    |> TransactionBuilder.build_kind!()
    |> Base.encode64()
  end

  defp expected_set_default_standing_kind_bytes(table, standing) do
    table
    |> diplomacy_table_ref()
    |> TxDiplomacy.build_set_default_standing(standing, [])
    |> TransactionBuilder.build_kind!()
    |> Base.encode64()
  end

  defp expected_batch_set_pilot_standings_kind_bytes(table, updates) do
    encoded_updates =
      Enum.map(updates, fn {pilot, standing} -> {hex_to_bytes(pilot), standing} end)

    table
    |> diplomacy_table_ref()
    |> TxDiplomacy.build_batch_set_pilot_standings(encoded_updates, [])
    |> TransactionBuilder.build_kind!()
    |> Base.encode64()
  end

  defp diplomacy_table_ref(table) do
    %{
      object_id: table.object_id_bytes,
      initial_shared_version: table.initial_shared_version
    }
  end

  defp hex_to_bytes("0x" <> hex), do: Base.decode16!(hex, case: :mixed)

  defp success_effects(digest) do
    %{
      "bcs" => "dGVzdC1lZmZlY3Rz",
      "status" => "SUCCESS",
      "transaction" => %{"digest" => digest},
      "gasEffects" => %{"gasSummary" => %{"computationCost" => "1"}}
    }
  end

  defp world_tribe_records do
    [
      %{"id" => 314, "name" => "Progenitor Collective", "short_name" => "PGCL"},
      %{"id" => 271, "name" => "Frontier Defense Union", "short_name" => "FDU"}
    ]
  end

  # ---------------------------------------------------------------------------
  # Probe subprocess helpers
  # ---------------------------------------------------------------------------
  # Tests that depend on Application.get_env (e.g. :reference_gas_price, :sui_client)
  # run in a separate BEAM process so the global config does not leak across tests.

  defp run_diplomacy_probe!(script), do: run_diplomacy_probe!(script, [])

  defp run_diplomacy_probe!(script, opts) do
    config_path = write_diplomacy_probe_config!(opts)

    args =
      Fixtures.mix_run_args(config_path, script)

    {output, status} =
      System.cmd(
        "mix",
        args,
        cd: project_root(),
        env: [
          {"MIX_ENV", "test"},
          {"ELIXIR_CLI_NO_VALIDATE_COMPILE_ENV", "1"}
        ],
        stderr_to_stdout: true
      )

    assert status == 0, output

    output
    |> extract_json!()
    |> Jason.decode!()
  end

  defp write_diplomacy_probe_config!(opts) do
    config_dir = Fixtures.ensure_tmp_dir!("diplomacy_probe")
    Fixtures.write_diplomacy_probe_config!(config_dir, opts)
  end

  defp probe_req_options(table, extra) do
    base = [
      table_id: table.object_id,
      table_version: table.initial_shared_version
    ]

    Keyword.merge(base, extra)
  end

  defp project_root do
    Path.expand("../..", __DIR__)
  end

  defp extract_json!(output) do
    case Regex.run(~r/(\{.*\})/s, output, capture: :all_but_first) do
      [json] -> json
      _other -> raise ExUnit.AssertionError, message: output
    end
  end
end
