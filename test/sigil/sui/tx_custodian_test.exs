defmodule Sigil.Sui.TxCustodianTest do
  @moduledoc """
  Defines packet 2 transaction builder tests for custodian PTB construction.
  """

  use ExUnit.Case, async: true

  alias Sigil.Sui.BCS
  alias Sigil.Sui.TransactionBuilder
  alias Sigil.Sui.TxCustodian

  @package_id Base.decode16!("06CE9D6BED77615383575CC7EBA4883D32769B30CD5DF00561E38434A59611A1",
                case: :mixed
              )

  describe "custodian lifecycle builders" do
    test "build_create_custodian produces correct inputs and command" do
      tx_opts = sample_tx_opts()

      assert TxCustodian.build_create_custodian(
               sample_registry_ref(),
               sample_character_ref(),
               tx_opts
             ) ==
               tx_opts ++
                 [
                   inputs: [
                     {:object, {:shared, object_id(0x10), 7, true}},
                     {:object, {:shared, object_id(0x20), 11, false}}
                   ],
                   commands: [
                     {:move_call, @package_id, "tribe_custodian", "create_custodian", [],
                      [{:input, 0}, {:input, 1}]}
                   ]
                 ]
    end

    test "build_join produces correct inputs and command" do
      tx_opts = sample_tx_opts()

      assert TxCustodian.build_join(sample_custodian_ref(), sample_character_ref(), tx_opts) ==
               tx_opts ++
                 [
                   inputs: [
                     {:object, {:shared, object_id(0x11), 9, true}},
                     {:object, {:shared, object_id(0x20), 11, false}}
                   ],
                   commands: [
                     {:move_call, @package_id, "tribe_custodian", "join", [],
                      [{:input, 0}, {:input, 1}]}
                   ]
                 ]
    end
  end

  describe "governance builders" do
    test "build_vote_leader encodes candidate address correctly" do
      candidate = object_id(0x30)

      build_opts =
        TxCustodian.build_vote_leader(
          sample_custodian_ref(),
          sample_character_ref(),
          candidate,
          sample_tx_opts()
        )

      assert build_opts[:inputs] == [
               {:object, {:shared, object_id(0x11), 9, true}},
               {:object, {:shared, object_id(0x20), 11, false}},
               {:pure, BCS.encode_address(candidate)}
             ]

      assert build_opts[:commands] == [
               {:move_call, @package_id, "tribe_custodian", "vote_leader", [],
                [{:input, 0}, {:input, 1}, {:input, 2}]}
             ]
    end

    test "build_claim_leadership produces correct command" do
      build_opts =
        TxCustodian.build_claim_leadership(
          sample_custodian_ref(),
          sample_character_ref(),
          sample_tx_opts()
        )

      assert build_opts[:inputs] == [
               {:object, {:shared, object_id(0x11), 9, true}},
               {:object, {:shared, object_id(0x20), 11, false}}
             ]

      assert build_opts[:commands] == [
               {:move_call, @package_id, "tribe_custodian", "claim_leadership", [],
                [{:input, 0}, {:input, 1}]}
             ]
    end

    test "build_add_operator encodes operator address correctly" do
      operator = object_id(0x31)

      build_opts =
        TxCustodian.build_add_operator(
          sample_custodian_ref(),
          sample_character_ref(),
          operator,
          sample_tx_opts()
        )

      assert build_opts[:inputs] == [
               {:object, {:shared, object_id(0x11), 9, true}},
               {:object, {:shared, object_id(0x20), 11, false}},
               {:pure, BCS.encode_address(operator)}
             ]

      assert build_opts[:commands] == [
               {:move_call, @package_id, "tribe_custodian", "add_operator", [],
                [{:input, 0}, {:input, 1}, {:input, 2}]}
             ]
    end

    test "build_remove_operator encodes operator address correctly" do
      operator = object_id(0x32)

      build_opts =
        TxCustodian.build_remove_operator(
          sample_custodian_ref(),
          sample_character_ref(),
          operator,
          sample_tx_opts()
        )

      assert build_opts[:inputs] == [
               {:object, {:shared, object_id(0x11), 9, true}},
               {:object, {:shared, object_id(0x20), 11, false}},
               {:pure, BCS.encode_address(operator)}
             ]

      assert build_opts[:commands] == [
               {:move_call, @package_id, "tribe_custodian", "remove_operator", [],
                [{:input, 0}, {:input, 1}, {:input, 2}]}
             ]
    end
  end

  describe "standings builders" do
    test "build_set_standing encodes tribe_id and standing correctly" do
      build_opts =
        TxCustodian.build_set_standing(
          sample_custodian_ref(),
          sample_character_ref(),
          42,
          0,
          sample_tx_opts()
        )

      assert build_opts[:inputs] == [
               {:object, {:shared, object_id(0x11), 9, true}},
               {:object, {:shared, object_id(0x20), 11, false}},
               {:pure, BCS.encode_u32(42)},
               {:pure, BCS.encode_u8(0)}
             ]

      assert build_opts[:commands] == [
               {:move_call, @package_id, "tribe_custodian", "set_standing", [],
                [{:input, 0}, {:input, 1}, {:input, 2}, {:input, 3}]}
             ]
    end

    test "build_set_default_standing encodes standing correctly" do
      build_opts =
        TxCustodian.build_set_default_standing(
          sample_custodian_ref(),
          sample_character_ref(),
          4,
          sample_tx_opts()
        )

      assert build_opts[:inputs] == [
               {:object, {:shared, object_id(0x11), 9, true}},
               {:object, {:shared, object_id(0x20), 11, false}},
               {:pure, BCS.encode_u8(4)}
             ]

      assert build_opts[:commands] == [
               {:move_call, @package_id, "tribe_custodian", "set_default_standing", [],
                [{:input, 0}, {:input, 1}, {:input, 2}]}
             ]
    end

    test "build_set_pilot_standing encodes pilot address and standing" do
      pilot = object_id(0x33)

      build_opts =
        TxCustodian.build_set_pilot_standing(
          sample_custodian_ref(),
          sample_character_ref(),
          pilot,
          1,
          sample_tx_opts()
        )

      assert build_opts[:inputs] == [
               {:object, {:shared, object_id(0x11), 9, true}},
               {:object, {:shared, object_id(0x20), 11, false}},
               {:pure, BCS.encode_address(pilot)},
               {:pure, BCS.encode_u8(1)}
             ]

      assert build_opts[:commands] == [
               {:move_call, @package_id, "tribe_custodian", "set_pilot_standing", [],
                [{:input, 0}, {:input, 1}, {:input, 2}, {:input, 3}]}
             ]
    end

    test "build_batch_set_standings encodes parallel vectors" do
      updates = [{1, 0}, {2, 3}, {3, 4}]

      build_opts =
        TxCustodian.build_batch_set_standings(
          sample_custodian_ref(),
          sample_character_ref(),
          updates,
          sample_tx_opts()
        )

      assert build_opts[:inputs] == [
               {:object, {:shared, object_id(0x11), 9, true}},
               {:object, {:shared, object_id(0x20), 11, false}},
               {:pure, BCS.encode_vector([1, 2, 3], &BCS.encode_u32/1)},
               {:pure, BCS.encode_vector([0, 3, 4], &BCS.encode_u8/1)}
             ]

      assert build_opts[:commands] == [
               {:move_call, @package_id, "tribe_custodian", "batch_set_standings", [],
                [{:input, 0}, {:input, 1}, {:input, 2}, {:input, 3}]}
             ]
    end

    test "build_batch_set_pilot_standings encodes address and standing vectors" do
      updates = [{object_id(0x41), 0}, {object_id(0x42), 4}]

      build_opts =
        TxCustodian.build_batch_set_pilot_standings(
          sample_custodian_ref(),
          sample_character_ref(),
          updates,
          sample_tx_opts()
        )

      assert build_opts[:inputs] == [
               {:object, {:shared, object_id(0x11), 9, true}},
               {:object, {:shared, object_id(0x20), 11, false}},
               {:pure, BCS.encode_vector(Enum.map(updates, &elem(&1, 0)), &BCS.encode_address/1)},
               {:pure, BCS.encode_vector(Enum.map(updates, &elem(&1, 1)), &BCS.encode_u8/1)}
             ]

      assert build_opts[:commands] == [
               {:move_call, @package_id, "tribe_custodian", "batch_set_pilot_standings", [],
                [{:input, 0}, {:input, 1}, {:input, 2}, {:input, 3}]}
             ]
    end
  end

  describe "shared package and object semantics" do
    test "all move_calls reference the sigil package ID" do
      move_calls = [
        TxCustodian.build_create_custodian(
          sample_registry_ref(),
          sample_character_ref(),
          sample_tx_opts()
        ),
        TxCustodian.build_join(sample_custodian_ref(), sample_character_ref(), sample_tx_opts()),
        TxCustodian.build_vote_leader(
          sample_custodian_ref(),
          sample_character_ref(),
          object_id(0x30),
          sample_tx_opts()
        ),
        TxCustodian.build_claim_leadership(
          sample_custodian_ref(),
          sample_character_ref(),
          sample_tx_opts()
        ),
        TxCustodian.build_add_operator(
          sample_custodian_ref(),
          sample_character_ref(),
          object_id(0x31),
          sample_tx_opts()
        ),
        TxCustodian.build_remove_operator(
          sample_custodian_ref(),
          sample_character_ref(),
          object_id(0x32),
          sample_tx_opts()
        ),
        TxCustodian.build_set_standing(
          sample_custodian_ref(),
          sample_character_ref(),
          42,
          0,
          sample_tx_opts()
        ),
        TxCustodian.build_set_default_standing(
          sample_custodian_ref(),
          sample_character_ref(),
          4,
          sample_tx_opts()
        ),
        TxCustodian.build_set_pilot_standing(
          sample_custodian_ref(),
          sample_character_ref(),
          object_id(0x33),
          1,
          sample_tx_opts()
        ),
        TxCustodian.build_batch_set_standings(
          sample_custodian_ref(),
          sample_character_ref(),
          [{1, 0}],
          sample_tx_opts()
        ),
        TxCustodian.build_batch_set_pilot_standings(
          sample_custodian_ref(),
          sample_character_ref(),
          [{object_id(0x41), 3}],
          sample_tx_opts()
        )
      ]

      assert Enum.all?(move_calls, fn build_opts ->
               match?(
                 [{:move_call, @package_id, "tribe_custodian", _, _, _}],
                 build_opts[:commands]
               )
             end)
    end

    test "custodian operations use mutable shared object reference" do
      build_opts_list = [
        TxCustodian.build_create_custodian(
          sample_registry_ref(),
          sample_character_ref(),
          sample_tx_opts()
        ),
        TxCustodian.build_join(sample_custodian_ref(), sample_character_ref(), sample_tx_opts()),
        TxCustodian.build_vote_leader(
          sample_custodian_ref(),
          sample_character_ref(),
          object_id(0x30),
          sample_tx_opts()
        ),
        TxCustodian.build_claim_leadership(
          sample_custodian_ref(),
          sample_character_ref(),
          sample_tx_opts()
        ),
        TxCustodian.build_add_operator(
          sample_custodian_ref(),
          sample_character_ref(),
          object_id(0x31),
          sample_tx_opts()
        ),
        TxCustodian.build_remove_operator(
          sample_custodian_ref(),
          sample_character_ref(),
          object_id(0x32),
          sample_tx_opts()
        ),
        TxCustodian.build_set_standing(
          sample_custodian_ref(),
          sample_character_ref(),
          42,
          0,
          sample_tx_opts()
        ),
        TxCustodian.build_set_default_standing(
          sample_custodian_ref(),
          sample_character_ref(),
          4,
          sample_tx_opts()
        ),
        TxCustodian.build_set_pilot_standing(
          sample_custodian_ref(),
          sample_character_ref(),
          object_id(0x33),
          1,
          sample_tx_opts()
        ),
        TxCustodian.build_batch_set_standings(
          sample_custodian_ref(),
          sample_character_ref(),
          [{1, 0}],
          sample_tx_opts()
        ),
        TxCustodian.build_batch_set_pilot_standings(
          sample_custodian_ref(),
          sample_character_ref(),
          [{object_id(0x41), 3}],
          sample_tx_opts()
        )
      ]

      assert Enum.all?(build_opts_list, fn build_opts ->
               match?({:object, {:shared, _, _, true}}, List.first(build_opts[:inputs]))
             end)
    end

    test "character uses immutable shared object reference" do
      build_opts_list = [
        TxCustodian.build_create_custodian(
          sample_registry_ref(),
          sample_character_ref(),
          sample_tx_opts()
        ),
        TxCustodian.build_join(sample_custodian_ref(), sample_character_ref(), sample_tx_opts()),
        TxCustodian.build_vote_leader(
          sample_custodian_ref(),
          sample_character_ref(),
          object_id(0x30),
          sample_tx_opts()
        ),
        TxCustodian.build_claim_leadership(
          sample_custodian_ref(),
          sample_character_ref(),
          sample_tx_opts()
        ),
        TxCustodian.build_add_operator(
          sample_custodian_ref(),
          sample_character_ref(),
          object_id(0x31),
          sample_tx_opts()
        ),
        TxCustodian.build_remove_operator(
          sample_custodian_ref(),
          sample_character_ref(),
          object_id(0x32),
          sample_tx_opts()
        ),
        TxCustodian.build_set_standing(
          sample_custodian_ref(),
          sample_character_ref(),
          42,
          0,
          sample_tx_opts()
        ),
        TxCustodian.build_set_default_standing(
          sample_custodian_ref(),
          sample_character_ref(),
          4,
          sample_tx_opts()
        ),
        TxCustodian.build_set_pilot_standing(
          sample_custodian_ref(),
          sample_character_ref(),
          object_id(0x33),
          1,
          sample_tx_opts()
        ),
        TxCustodian.build_batch_set_standings(
          sample_custodian_ref(),
          sample_character_ref(),
          [{1, 0}],
          sample_tx_opts()
        ),
        TxCustodian.build_batch_set_pilot_standings(
          sample_custodian_ref(),
          sample_character_ref(),
          [{object_id(0x41), 3}],
          sample_tx_opts()
        )
      ]

      assert Enum.all?(build_opts_list, fn build_opts ->
               match?({:object, {:shared, _, _, false}}, Enum.at(build_opts[:inputs], 1))
             end)
    end
  end

  describe "argument validation" do
    test "invalid standing raises across all standing builders" do
      assert_raise ArgumentError, fn ->
        TxCustodian.build_set_standing(
          sample_custodian_ref(),
          sample_character_ref(),
          42,
          5,
          sample_tx_opts()
        )
      end

      assert_raise ArgumentError, fn ->
        TxCustodian.build_set_default_standing(
          sample_custodian_ref(),
          sample_character_ref(),
          5,
          sample_tx_opts()
        )
      end

      assert_raise ArgumentError, fn ->
        TxCustodian.build_set_pilot_standing(
          sample_custodian_ref(),
          sample_character_ref(),
          object_id(0x33),
          5,
          sample_tx_opts()
        )
      end

      assert_raise ArgumentError, fn ->
        TxCustodian.build_batch_set_standings(
          sample_custodian_ref(),
          sample_character_ref(),
          [{1, 0}, {2, 5}],
          sample_tx_opts()
        )
      end

      assert_raise ArgumentError, fn ->
        TxCustodian.build_batch_set_pilot_standings(
          sample_custodian_ref(),
          sample_character_ref(),
          [{object_id(0x41), 0}, {object_id(0x42), 5}],
          sample_tx_opts()
        )
      end
    end

    test "empty batch raises for both batch builders" do
      assert_raise ArgumentError, fn ->
        TxCustodian.build_batch_set_standings(
          sample_custodian_ref(),
          sample_character_ref(),
          [],
          sample_tx_opts()
        )
      end

      assert_raise ArgumentError, fn ->
        TxCustodian.build_batch_set_pilot_standings(
          sample_custodian_ref(),
          sample_character_ref(),
          [],
          sample_tx_opts()
        )
      end
    end

    test "invalid address inputs raise ArgumentError" do
      invalid_address = <<1, 2, 3>>
      invalid_ref = %{object_id: invalid_address, initial_shared_version: 9}

      assert_raise ArgumentError, fn ->
        TxCustodian.build_create_custodian(invalid_ref, sample_character_ref(), sample_tx_opts())
      end

      assert_raise ArgumentError, fn ->
        TxCustodian.build_join(invalid_ref, sample_character_ref(), sample_tx_opts())
      end

      assert_raise ArgumentError, fn ->
        TxCustodian.build_vote_leader(
          sample_custodian_ref(),
          sample_character_ref(),
          invalid_address,
          sample_tx_opts()
        )
      end

      assert_raise ArgumentError, fn ->
        TxCustodian.build_claim_leadership(
          sample_custodian_ref(),
          %{object_id: invalid_address, initial_shared_version: 11},
          sample_tx_opts()
        )
      end

      assert_raise ArgumentError, fn ->
        TxCustodian.build_add_operator(
          sample_custodian_ref(),
          sample_character_ref(),
          invalid_address,
          sample_tx_opts()
        )
      end

      assert_raise ArgumentError, fn ->
        TxCustodian.build_remove_operator(
          sample_custodian_ref(),
          sample_character_ref(),
          invalid_address,
          sample_tx_opts()
        )
      end

      assert_raise ArgumentError, fn ->
        TxCustodian.build_set_pilot_standing(
          sample_custodian_ref(),
          sample_character_ref(),
          invalid_address,
          1,
          sample_tx_opts()
        )
      end

      assert_raise ArgumentError, fn ->
        TxCustodian.build_batch_set_pilot_standings(
          sample_custodian_ref(),
          sample_character_ref(),
          [{invalid_address, 1}],
          sample_tx_opts()
        )
      end
    end
  end

  describe "TransactionBuilder integration" do
    test "build output passes through TransactionBuilder.build!" do
      build_opts =
        TxCustodian.build_set_standing(
          sample_custodian_ref(),
          sample_character_ref(),
          42,
          0,
          sample_tx_opts()
        )

      assert is_binary(TransactionBuilder.build!(build_opts))
    end

    test "build output works with build_kind! for wallet signing flow" do
      build_opts =
        TxCustodian.build_set_standing(
          sample_custodian_ref(),
          sample_character_ref(),
          42,
          0,
          []
        )

      assert build_opts == [
               inputs: [
                 {:object, {:shared, object_id(0x11), 9, true}},
                 {:object, {:shared, object_id(0x20), 11, false}},
                 {:pure, BCS.encode_u32(42)},
                 {:pure, BCS.encode_u8(0)}
               ],
               commands: [
                 {:move_call, @package_id, "tribe_custodian", "set_standing", [],
                  [{:input, 0}, {:input, 1}, {:input, 2}, {:input, 3}]}
               ]
             ]

      assert is_binary(TransactionBuilder.build_kind!(build_opts))
    end
  end

  defp sample_registry_ref do
    %{object_id: object_id(0x10), initial_shared_version: 7}
  end

  defp sample_custodian_ref do
    %{object_id: object_id(0x11), initial_shared_version: 9}
  end

  defp sample_character_ref do
    %{object_id: object_id(0x20), initial_shared_version: 11}
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
