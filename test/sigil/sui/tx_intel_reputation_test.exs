defmodule Sigil.Sui.TxIntelReputationTest do
  @moduledoc """
  Verifies reputation PTB construction for buyer feedback operations.
  """

  use ExUnit.Case, async: true

  @compile {:no_warn_undefined, Sigil.Sui.TxIntelReputation}

  alias Sigil.Sui.TransactionBuilder
  alias Sigil.Sui.TxIntelReputation

  @package_id Base.decode16!(
                "06CE9D6BED77615383575CC7EBA4883D32769B30CD5DF00561E38434A59611A1",
                case: :mixed
              )

  describe "reputation builders" do
    test "build_confirm_quality produces correct PTB structure" do
      assert TxIntelReputation.build_confirm_quality(
               sample_registry_ref(),
               sample_listing_ref(),
               []
             ) ==
               [
                 inputs: [
                   {:object, {:shared, object_id(0x10), 7, true}},
                   {:object, {:shared, object_id(0x20), 11, false}}
                 ],
                 commands: [
                   {:move_call, @package_id, "intel_reputation", "confirm_quality", [],
                    [{:input, 0}, {:input, 1}]}
                 ]
               ]
    end

    test "build_report_bad_quality produces correct PTB structure" do
      assert TxIntelReputation.build_report_bad_quality(
               sample_registry_ref(),
               sample_listing_ref(),
               []
             ) ==
               [
                 inputs: [
                   {:object, {:shared, object_id(0x10), 7, true}},
                   {:object, {:shared, object_id(0x20), 11, false}}
                 ],
                 commands: [
                   {:move_call, @package_id, "intel_reputation", "report_bad_quality", [],
                    [{:input, 0}, {:input, 1}]}
                 ]
               ]
    end

    test "tx_opts are prepended to builder output" do
      tx_opts = sample_tx_opts()

      assert TxIntelReputation.build_confirm_quality(
               sample_registry_ref(),
               sample_listing_ref(),
               tx_opts
             ) ==
               tx_opts ++
                 [
                   inputs: [
                     {:object, {:shared, object_id(0x10), 7, true}},
                     {:object, {:shared, object_id(0x20), 11, false}}
                   ],
                   commands: [
                     {:move_call, @package_id, "intel_reputation", "confirm_quality", [],
                      [{:input, 0}, {:input, 1}]}
                   ]
                 ]
    end
  end

  describe "validation" do
    test "raises ArgumentError for invalid object_id size" do
      invalid_registry_ref = %{object_id: <<1, 2, 3>>, initial_shared_version: 7}
      invalid_listing_ref = %{object_id: <<4, 5, 6>>, initial_shared_version: 11}

      assert_raise ArgumentError, fn ->
        TxIntelReputation.build_confirm_quality(invalid_registry_ref, sample_listing_ref(), [])
      end

      assert_raise ArgumentError, fn ->
        TxIntelReputation.build_report_bad_quality(sample_registry_ref(), invalid_listing_ref, [])
      end
    end
  end

  describe "TransactionBuilder integration" do
    test "build_confirm_quality output encodes via build_kind!" do
      build_opts =
        TxIntelReputation.build_confirm_quality(sample_registry_ref(), sample_listing_ref(), [])

      assert is_binary(TransactionBuilder.build_kind!(build_opts))
    end
  end

  defp sample_registry_ref do
    %{object_id: object_id(0x10), initial_shared_version: 7}
  end

  defp sample_listing_ref do
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
