defmodule Sigil.GateIndexerTest do
  @moduledoc """
  Covers the packet 1 gate indexer contract from the approved spec.
  """

  use ExUnit.Case, async: true

  import Hammox

  @compile {:no_warn_undefined, Sigil.GateIndexer}

  alias Sigil.Cache
  alias Sigil.Sui.Types.Gate

  @world_package_id "0x1111111111111111111111111111111111111111111111111111111111111111"

  setup :set_mox_from_context
  setup :verify_on_exit!

  setup do
    cache_pid = start_supervised!({Cache, tables: [:gate_network]})
    pubsub = unique_pubsub_name()

    start_supervised!({Phoenix.PubSub, name: pubsub})
    :ok = Phoenix.PubSub.subscribe(pubsub, "gate_network")

    {:ok, tables: Cache.tables(cache_pid), pubsub: pubsub}
  end

  describe "build_topology/1" do
    test "build_topology creates bidirectional adjacency from linked_gate_id" do
      gate_a = gate_struct("0xgate-a", linked_gate_id: "0xgate-b")
      gate_b = gate_struct("0xgate-b", linked_gate_id: nil)

      assert Sigil.GateIndexer.build_topology([gate_a, gate_b]) == %{
               "0xgate-a" => MapSet.new(["0xgate-b"]),
               "0xgate-b" => MapSet.new(["0xgate-a"])
             }
    end

    test "build_topology excludes gates with nil linked_gate_id" do
      assert Sigil.GateIndexer.build_topology([gate_struct("0xsolo", linked_gate_id: nil)]) == %{}
    end

    test "build_topology with empty list returns empty map" do
      assert Sigil.GateIndexer.build_topology([]) == %{}
    end
  end

  describe "build_location_index/1" do
    test "build_location_index groups gates by location_hash" do
      shared_location = location_hash(7)

      gate_a = gate_struct("0xgate-a", location_hash: shared_location)
      gate_b = gate_struct("0xgate-b", location_hash: shared_location)
      gate_c = gate_struct("0xgate-c", location_hash: location_hash(8))

      assert Sigil.GateIndexer.build_location_index([gate_a, gate_b, gate_c]) == %{
               shared_location => MapSet.new(["0xgate-a", "0xgate-b"]),
               location_hash(8) => MapSet.new(["0xgate-c"])
             }
    end

    test "build_location_index with unique locations has single-element sets" do
      gate_a = gate_struct("0xgate-a", location_hash: location_hash(1))
      gate_b = gate_struct("0xgate-b", location_hash: location_hash(2))

      assert Sigil.GateIndexer.build_location_index([gate_a, gate_b]) == %{
               location_hash(1) => MapSet.new(["0xgate-a"]),
               location_hash(2) => MapSet.new(["0xgate-b"])
             }
    end
  end

  describe "query API" do
    test "list_gates returns all cached Gate structs", %{tables: tables} do
      Cache.put(tables.gate_network, "0xgate-a", gate_struct("0xgate-a"))
      Cache.put(tables.gate_network, "0xgate-b", gate_struct("0xgate-b"))
      Cache.put(tables.gate_network, :topology, %{"0xgate-a" => MapSet.new(["0xgate-b"])})

      Cache.put(tables.gate_network, :location_index, %{
        location_hash(1) => MapSet.new(["0xgate-a"])
      })

      assert Sigil.GateIndexer.list_gates(tables: tables)
             |> Enum.map(& &1.id)
             |> Enum.sort() == ["0xgate-a", "0xgate-b"]
    end

    test "list_gates returns empty list when table is empty", %{tables: tables} do
      assert Sigil.GateIndexer.list_gates(tables: tables) == []
    end

    test "get_gate returns gate by ID", %{tables: tables} do
      gate = gate_struct("0xgate-a")
      Cache.put(tables.gate_network, gate.id, gate)

      assert Sigil.GateIndexer.get_gate(gate.id, tables: tables) == gate
    end

    test "get_gate returns nil for unknown ID", %{tables: tables} do
      assert Sigil.GateIndexer.get_gate("0xmissing", tables: tables) == nil
    end

    test "get_topology returns cached adjacency map", %{tables: tables} do
      topology = %{"0xgate-a" => MapSet.new(["0xgate-b"])}
      Cache.put(tables.gate_network, :topology, topology)

      assert Sigil.GateIndexer.get_topology(tables: tables) == topology
    end

    test "get_topology returns empty map before first scan", %{tables: tables} do
      assert Sigil.GateIndexer.get_topology(tables: tables) == %{}
    end

    test "gates_at_location returns gates matching location_hash", %{tables: tables} do
      shared_location = location_hash(5)
      gate_a = gate_struct("0xgate-a", location_hash: shared_location)
      gate_b = gate_struct("0xgate-b", location_hash: shared_location)

      Cache.put(tables.gate_network, gate_a.id, gate_a)
      Cache.put(tables.gate_network, gate_b.id, gate_b)

      Cache.put(tables.gate_network, :location_index, %{
        shared_location => MapSet.new([gate_a.id, gate_b.id])
      })

      gates = Sigil.GateIndexer.gates_at_location(shared_location, tables: tables)
      assert gates |> Enum.map(& &1.id) |> Enum.sort() == ["0xgate-a", "0xgate-b"]
    end

    test "gates_at_location returns empty list for unknown location", %{tables: tables} do
      assert Sigil.GateIndexer.gates_at_location(location_hash(4), tables: tables) == []
    end
  end

  describe "GenServer lifecycle" do
    test "initial scan populates gates in ETS", %{tables: tables, pubsub: pubsub} do
      expect_get_objects_sequence!([
        fn filters, [] ->
          assert Keyword.get(filters, :cursor) == nil

          {:ok,
           page([
             gate_json("0xgate-a", linked_gate_id: "0xgate-b", location_hash: location_hash(1)),
             gate_json("0xgate-b", linked_gate_id: nil, location_hash: location_hash(1))
           ])}
        end
      ])

      _pid =
        start_gate_indexer!(
          tables: tables,
          pubsub: pubsub,
          interval_ms: 1_000,
          req_options: []
        )

      assert_receive {:get_objects_called, 1, nil}, 1_000
      assert_receive {:gates_updated, %{count: 2, added: 2, removed: 0}}, 1_000

      assert Sigil.GateIndexer.list_gates(tables: tables) |> Enum.map(& &1.id) |> Enum.sort() ==
               ["0xgate-a", "0xgate-b"]

      assert Sigil.GateIndexer.get_topology(tables: tables) == %{
               "0xgate-a" => MapSet.new(["0xgate-b"]),
               "0xgate-b" => MapSet.new(["0xgate-a"])
             }

      location_gates = Sigil.GateIndexer.gates_at_location(location_hash(1), tables: tables)
      assert location_gates |> Enum.map(& &1.id) |> Enum.sort() == ["0xgate-a", "0xgate-b"]
    end

    test "periodic re-scan updates ETS after interval", %{tables: tables, pubsub: pubsub} do
      expect_get_objects_sequence!([
        fn filters, [] ->
          assert Keyword.get(filters, :cursor) == nil
          {:ok, page([gate_json("0xgate-a")])}
        end,
        fn filters, [] ->
          assert Keyword.get(filters, :cursor) == nil
          {:ok, page([gate_json("0xgate-a")])}
        end
      ])

      _pid = start_gate_indexer!(tables: tables, pubsub: pubsub, interval_ms: 30)

      assert_receive {:get_objects_called, 1, nil}, 1_000
      assert_receive {:gates_updated, %{count: 1, added: 1, removed: 0}}, 1_000
      assert_receive {:get_objects_called, 2, nil}, 1_000
      assert_receive {:gates_updated, %{count: 1, added: 0, removed: 0}}, 1_000
    end

    test "pagination fetches all pages of gates", %{tables: tables, pubsub: pubsub} do
      expect_get_objects_sequence!([
        fn filters, [] ->
          assert Keyword.get(filters, :cursor) == nil
          {:ok, page([gate_json("0xgate-a")], true, "cursor-1")}
        end,
        fn filters, [] ->
          assert Keyword.get(filters, :cursor) == "cursor-1"
          {:ok, page([gate_json("0xgate-b")])}
        end
      ])

      _pid = start_gate_indexer!(tables: tables, pubsub: pubsub, interval_ms: 1_000)

      assert_receive {:get_objects_called, 1, nil}, 1_000
      assert_receive {:get_objects_called, 2, "cursor-1"}, 1_000
      assert_receive {:gates_updated, %{count: 2, added: 2, removed: 0}}, 1_000

      assert Sigil.GateIndexer.list_gates(tables: tables) |> Enum.map(& &1.id) |> Enum.sort() ==
               ["0xgate-a", "0xgate-b"]
    end

    test "stale gates are removed from ETS on re-scan", %{tables: tables, pubsub: pubsub} do
      expect_get_objects_sequence!([
        fn _filters, [] ->
          {:ok, page([gate_json("0xgate-a"), gate_json("0xgate-b")])}
        end,
        fn _filters, [] ->
          {:ok, page([gate_json("0xgate-b"), gate_json("0xgate-c")])}
        end
      ])

      _pid = start_gate_indexer!(tables: tables, pubsub: pubsub, interval_ms: 30)

      assert_receive {:gates_updated, %{count: 2, added: 2, removed: 0}}, 1_000
      assert Sigil.GateIndexer.get_gate("0xgate-a", tables: tables)
      assert_receive {:gates_updated, %{count: 2, added: 1, removed: 1}}, 1_000

      assert Sigil.GateIndexer.get_gate("0xgate-a", tables: tables) == nil

      assert Sigil.GateIndexer.list_gates(tables: tables) |> Enum.map(& &1.id) |> Enum.sort() ==
               ["0xgate-b", "0xgate-c"]
    end

    test "restart removes stale gates already cached in ETS", %{tables: tables, pubsub: pubsub} do
      expect_get_objects_sequence!([
        fn _filters, [] ->
          {:ok, page([gate_json("0xgate-a"), gate_json("0xgate-b")])}
        end,
        fn _filters, [] ->
          {:ok, page([gate_json("0xgate-b")])}
        end
      ])

      pid = start_gate_indexer!(tables: tables, pubsub: pubsub, interval_ms: 1_000)

      assert_receive {:gates_updated, %{count: 2, added: 2, removed: 0}}, 1_000
      assert Sigil.GateIndexer.get_gate("0xgate-a", tables: tables)

      GenServer.stop(pid, :normal, :infinity)

      restarted_pid = start_gate_indexer!(tables: tables, pubsub: pubsub, interval_ms: 1_000)

      assert_receive {:gates_updated, %{count: 1, added: 0, removed: 1}}, 1_000
      assert Process.alive?(restarted_pid)
      assert Sigil.GateIndexer.get_gate("0xgate-a", tables: tables) == nil
      assert Sigil.GateIndexer.list_gates(tables: tables) |> Enum.map(& &1.id) == ["0xgate-b"]
    end

    test "broadcasts gates_updated on PubSub after scan", %{tables: tables, pubsub: pubsub} do
      expect_get_objects_sequence!([
        fn _filters, [] ->
          {:ok, page([gate_json("0xgate-a"), gate_json("0xgate-b")])}
        end
      ])

      _pid = start_gate_indexer!(tables: tables, pubsub: pubsub, interval_ms: 1_000)

      assert_receive {:gates_updated, %{count: 2, added: 2, removed: 0}}, 1_000
    end

    test "gate indexer is not a named process", %{tables: tables, pubsub: pubsub} do
      expect_get_objects_sequence!([
        fn _filters, [] -> {:ok, page([])} end
      ])

      pid = start_gate_indexer!(tables: tables, pubsub: pubsub, interval_ms: 1_000)

      assert_receive {:get_objects_called, 1, nil}, 1_000
      assert Process.info(pid, :registered_name) == {:registered_name, []}
    end

    test "child_spec generates unique id" do
      spec_one = Sigil.GateIndexer.child_spec([])
      spec_two = Sigil.GateIndexer.child_spec([])

      assert spec_one.start == {Sigil.GateIndexer, :start_link, [[]]}
      assert spec_two.start == {Sigil.GateIndexer, :start_link, [[]]}
      refute spec_one.id == spec_two.id
    end
  end

  describe "error handling" do
    test "chain query error preserves previous cache and schedules retry", %{
      tables: tables,
      pubsub: pubsub
    } do
      expect_get_objects_sequence!([
        fn _filters, [] -> {:ok, page([gate_json("0xgate-a")])} end,
        fn _filters, [] -> {:error, :timeout} end,
        fn _filters, [] -> {:ok, page([gate_json("0xgate-a")])} end
      ])

      _pid = start_gate_indexer!(tables: tables, pubsub: pubsub, interval_ms: 30)

      assert_receive {:gates_updated, %{count: 1, added: 1, removed: 0}}, 1_000
      assert Sigil.GateIndexer.get_gate("0xgate-a", tables: tables)

      assert_receive {:get_objects_called, 2, nil}, 1_000
      assert Sigil.GateIndexer.get_gate("0xgate-a", tables: tables)

      assert_receive {:get_objects_called, 3, nil}, 1_000
      assert_receive {:gates_updated, %{count: 1, added: 0, removed: 0}}, 1_000
    end

    test "malformed gate JSON is skipped without crashing scan", %{tables: tables, pubsub: pubsub} do
      expect_get_objects_sequence!([
        fn _filters, [] ->
          {:ok,
           page([
             gate_json("0xgate-a", linked_gate_id: nil),
             malformed_gate_json("0xbroken-gate")
           ])}
        end
      ])

      pid = start_gate_indexer!(tables: tables, pubsub: pubsub, interval_ms: 1_000)

      assert_receive {:gates_updated, %{count: 1, added: 1, removed: 0}}, 1_000
      assert Process.alive?(pid)
      assert Sigil.GateIndexer.list_gates(tables: tables) |> Enum.map(& &1.id) == ["0xgate-a"]
    end

    test "zero gates on chain produces empty index", %{tables: tables, pubsub: pubsub} do
      expect_get_objects_sequence!([
        fn _filters, [] -> {:ok, page([])} end
      ])

      _pid = start_gate_indexer!(tables: tables, pubsub: pubsub, interval_ms: 1_000)

      assert_receive {:gates_updated, %{count: 0, added: 0, removed: 0}}, 1_000
      assert Sigil.GateIndexer.list_gates(tables: tables) == []
      assert Sigil.GateIndexer.get_topology(tables: tables) == %{}
      assert Sigil.GateIndexer.gates_at_location(location_hash(1), tables: tables) == []
    end
  end

  @tag :acceptance
  test "full lifecycle: start, scan, query, re-scan with changes", %{
    tables: tables,
    pubsub: pubsub
  } do
    expect_get_objects_sequence!([
      fn _filters, [] ->
        {:ok,
         page([
           gate_json("0xgate-a", linked_gate_id: "0xgate-b", location_hash: location_hash(1)),
           gate_json("0xgate-b", linked_gate_id: nil, location_hash: location_hash(1))
         ])}
      end,
      fn _filters, [] ->
        {:ok,
         page([
           gate_json("0xgate-b", linked_gate_id: "0xgate-d", location_hash: location_hash(2)),
           gate_json("0xgate-d", linked_gate_id: nil, location_hash: location_hash(2))
         ])}
      end
    ])

    _pid = start_gate_indexer!(tables: tables, pubsub: pubsub, interval_ms: 30)

    assert_receive {:gates_updated, %{count: 2, added: 2, removed: 0}}, 1_000

    assert Sigil.GateIndexer.list_gates(tables: tables) |> Enum.map(& &1.id) |> Enum.sort() ==
             ["0xgate-a", "0xgate-b"]

    assert Sigil.GateIndexer.get_topology(tables: tables) == %{
             "0xgate-a" => MapSet.new(["0xgate-b"]),
             "0xgate-b" => MapSet.new(["0xgate-a"])
           }

    first_location_gates = Sigil.GateIndexer.gates_at_location(location_hash(1), tables: tables)
    first_location_ids = first_location_gates |> Enum.map(& &1.id) |> Enum.sort()

    assert first_location_ids == ["0xgate-a", "0xgate-b"]
    refute "0xgate-d" in first_location_ids

    assert_receive {:gates_updated, %{count: 2, added: 1, removed: 1}}, 1_000

    assert Sigil.GateIndexer.list_gates(tables: tables) |> Enum.map(& &1.id) |> Enum.sort() ==
             ["0xgate-b", "0xgate-d"]

    assert Sigil.GateIndexer.get_topology(tables: tables) == %{
             "0xgate-b" => MapSet.new(["0xgate-d"]),
             "0xgate-d" => MapSet.new(["0xgate-b"])
           }

    second_location_gates = Sigil.GateIndexer.gates_at_location(location_hash(2), tables: tables)
    second_location_ids = second_location_gates |> Enum.map(& &1.id) |> Enum.sort()

    assert second_location_ids == ["0xgate-b", "0xgate-d"]
    refute Sigil.GateIndexer.get_gate("0xgate-a", tables: tables)
    refute "0xgate-a" in second_location_ids
  end

  defp start_gate_indexer!(opts) do
    start_supervised!({Sigil.GateIndexer, Keyword.put(opts, :mox_owner, self())})
  end

  defp expect_get_objects_sequence!(responses) do
    parent = self()
    counter = start_supervised!({Agent, fn -> 0 end})

    expect(Sigil.Sui.ClientMock, :get_objects, length(responses), fn filters, req_options ->
      call_number = Agent.get_and_update(counter, &{&1 + 1, &1 + 1})
      send(parent, {:get_objects_called, call_number, Keyword.get(filters, :cursor)})
      assert Keyword.get(filters, :type) == gate_type()

      responses
      |> Enum.fetch!(call_number - 1)
      |> then(& &1.(filters, req_options))
    end)
  end

  defp page(data, has_next_page \\ false, end_cursor \\ nil) do
    %{data: data, has_next_page: has_next_page, end_cursor: end_cursor}
  end

  defp gate_struct(id, opts \\ []) do
    id
    |> gate_json(opts)
    |> Gate.from_json()
  end

  defp gate_json(id, opts \\ []) do
    linked_gate_id = Keyword.get(opts, :linked_gate_id, default_linked_gate_id(id))
    location = Keyword.get(opts, :location_hash, location_hash(1))

    %{
      "id" => uid(id),
      "key" => %{"item_id" => "7", "tenant" => "0xtenant"},
      "owner_cap_id" => uid(id <> "-owner"),
      "type_id" => "9001",
      "linked_gate_id" => linked_gate_id,
      "status" => %{"status" => "ONLINE"},
      "location" => %{"location_hash" => :binary.bin_to_list(location)},
      "energy_source_id" => id <> "-energy",
      "metadata" => %{
        "assembly_id" => id <> "-metadata",
        "name" => "Gate #{id}",
        "description" => "Gate fixture #{id}",
        "url" => "https://example.test/gates/#{String.trim_leading(id, "0x")}"
      },
      "extension" => "0x2::frontier::GateExtension"
    }
  end

  defp malformed_gate_json(id) do
    id |> gate_json() |> Map.delete("key")
  end

  defp default_linked_gate_id("0xgate-a"), do: "0xgate-b"
  defp default_linked_gate_id("0xgate-b"), do: nil
  defp default_linked_gate_id("0xgate-d"), do: nil
  defp default_linked_gate_id(_id), do: nil

  defp gate_type do
    "#{@world_package_id}::gate::Gate"
  end

  defp location_hash(byte), do: :binary.copy(<<byte>>, 32)

  defp uid(id), do: %{"id" => id}

  defp unique_pubsub_name do
    :"gate_indexer_pubsub_#{System.unique_integer([:positive])}"
  end
end
