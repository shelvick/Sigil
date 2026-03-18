defmodule Sigil.Sui.TxDiplomacyTest do
  @moduledoc """
  Defines packet 1 transaction builder tests for diplomacy PTB construction.
  """

  use ExUnit.Case, async: true

  alias Sigil.Sui.BCS
  alias Sigil.Sui.TransactionBuilder
  alias Sigil.Sui.TxDiplomacy

  @package_id Base.decode16!("06CE9D6BED77615383575CC7EBA4883D32769B30CD5DF00561E38434A59611A1",
                case: :mixed
              )

  describe "build_create_table/1" do
    test "build_create_table produces create move_call with no inputs" do
      tx_opts = sample_tx_opts()

      assert TxDiplomacy.build_create_table(tx_opts) ==
               tx_opts ++
                 [
                   inputs: [],
                   commands: [{:move_call, @package_id, "standings_table", "create", [], []}]
                 ]
    end
  end

  describe "table mutation builders" do
    test "build_set_standing encodes tribe_id and standing correctly" do
      build_opts = TxDiplomacy.build_set_standing(sample_table_ref(), 42, 0, sample_tx_opts())

      assert build_opts[:inputs] == [
               {:object, {:shared, object_id(0x11), 9, true}},
               {:pure, BCS.encode_u32(42)},
               {:pure, BCS.encode_u8(0)}
             ]

      assert build_opts[:commands] == [
               {:move_call, @package_id, "standings_table", "set_standing", [],
                [{:input, 0}, {:input, 1}, {:input, 2}]}
             ]
    end

    test "build_set_default_standing encodes standing correctly" do
      build_opts = TxDiplomacy.build_set_default_standing(sample_table_ref(), 4, sample_tx_opts())

      assert build_opts[:inputs] == [
               {:object, {:shared, object_id(0x11), 9, true}},
               {:pure, BCS.encode_u8(4)}
             ]

      assert build_opts[:commands] == [
               {:move_call, @package_id, "standings_table", "set_default_standing", [],
                [{:input, 0}, {:input, 1}]}
             ]
    end

    test "build_set_pilot_standing encodes pilot address and standing" do
      pilot = object_id(0x44)

      build_opts =
        TxDiplomacy.build_set_pilot_standing(sample_table_ref(), pilot, 1, sample_tx_opts())

      assert build_opts[:inputs] == [
               {:object, {:shared, object_id(0x11), 9, true}},
               {:pure, BCS.encode_address(pilot)},
               {:pure, BCS.encode_u8(1)}
             ]

      assert build_opts[:commands] == [
               {:move_call, @package_id, "standings_table", "set_pilot_standing", [],
                [{:input, 0}, {:input, 1}, {:input, 2}]}
             ]
    end

    test "build_batch_set_standings encodes parallel vectors" do
      updates = [{1, 0}, {2, 3}, {3, 4}]

      build_opts =
        TxDiplomacy.build_batch_set_standings(sample_table_ref(), updates, sample_tx_opts())

      assert build_opts[:inputs] == [
               {:object, {:shared, object_id(0x11), 9, true}},
               {:pure, BCS.encode_vector([1, 2, 3], &BCS.encode_u32/1)},
               {:pure, BCS.encode_vector([0, 3, 4], &BCS.encode_u8/1)}
             ]

      assert build_opts[:commands] == [
               {:move_call, @package_id, "standings_table", "batch_set_standings", [],
                [{:input, 0}, {:input, 1}, {:input, 2}]}
             ]
    end

    test "build_batch_set_pilot_standings encodes address and standing vectors" do
      updates = [{object_id(0x21), 0}, {object_id(0x22), 4}]

      build_opts =
        TxDiplomacy.build_batch_set_pilot_standings(sample_table_ref(), updates, sample_tx_opts())

      assert build_opts[:inputs] == [
               {:object, {:shared, object_id(0x11), 9, true}},
               {:pure, BCS.encode_vector(Enum.map(updates, &elem(&1, 0)), &BCS.encode_address/1)},
               {:pure, BCS.encode_vector(Enum.map(updates, &elem(&1, 1)), &BCS.encode_u8/1)}
             ]

      assert build_opts[:commands] == [
               {:move_call, @package_id, "standings_table", "batch_set_pilot_standings", [],
                [{:input, 0}, {:input, 1}, {:input, 2}]}
             ]
    end
  end

  describe "shared package and object semantics" do
    test "all move_calls reference the deployed package ID" do
      move_calls = [
        TxDiplomacy.build_create_table(sample_tx_opts()),
        TxDiplomacy.build_set_standing(sample_table_ref(), 42, 0, sample_tx_opts()),
        TxDiplomacy.build_set_default_standing(sample_table_ref(), 4, sample_tx_opts()),
        TxDiplomacy.build_set_pilot_standing(
          sample_table_ref(),
          object_id(0x44),
          1,
          sample_tx_opts()
        ),
        TxDiplomacy.build_batch_set_standings(sample_table_ref(), [{1, 0}], sample_tx_opts()),
        TxDiplomacy.build_batch_set_pilot_standings(
          sample_table_ref(),
          [{object_id(0x55), 3}],
          sample_tx_opts()
        )
      ]

      assert Enum.all?(move_calls, fn build_opts ->
               match?([{:move_call, @package_id, _, _, _, _}], build_opts[:commands])
             end)
    end

    test "table operations use mutable shared object reference" do
      build_opts_list = [
        TxDiplomacy.build_set_standing(sample_table_ref(), 42, 0, sample_tx_opts()),
        TxDiplomacy.build_set_default_standing(sample_table_ref(), 4, sample_tx_opts()),
        TxDiplomacy.build_set_pilot_standing(
          sample_table_ref(),
          object_id(0x44),
          1,
          sample_tx_opts()
        ),
        TxDiplomacy.build_batch_set_standings(sample_table_ref(), [{1, 0}], sample_tx_opts()),
        TxDiplomacy.build_batch_set_pilot_standings(
          sample_table_ref(),
          [{object_id(0x55), 3}],
          sample_tx_opts()
        )
      ]

      assert Enum.all?(build_opts_list, fn build_opts ->
               match?({:object, {:shared, _, _, true}}, List.first(build_opts[:inputs]))
             end)
    end
  end

  describe "argument validation" do
    test "standing > 4 raises ArgumentError" do
      assert_raise ArgumentError, fn ->
        TxDiplomacy.build_set_standing(sample_table_ref(), 42, 5, sample_tx_opts())
      end
    end

    test "empty batch raises ArgumentError" do
      assert_raise ArgumentError, fn ->
        TxDiplomacy.build_batch_set_standings(sample_table_ref(), [], sample_tx_opts())
      end
    end
  end

  describe "TransactionBuilder integration" do
    test "build output passes through TransactionBuilder.build! successfully" do
      build_opts = TxDiplomacy.build_set_standing(sample_table_ref(), 42, 0, sample_tx_opts())

      assert is_binary(TransactionBuilder.build!(build_opts))
    end
  end

  defp sample_table_ref do
    %{
      object_id: object_id(0x11),
      initial_shared_version: 9
    }
  end

  defp sample_tx_opts do
    [
      sender: object_id(0xAA),
      gas_payment: [{object_id(0xBB), 7, object_id(0xCC)}],
      gas_price: 1_000,
      gas_budget: 50_000_000
    ]
  end

  defp object_id(byte) do
    :binary.copy(<<byte>>, 32)
  end
end
