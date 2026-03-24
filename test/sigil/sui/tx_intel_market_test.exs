defmodule Sigil.Sui.TxIntelMarketTest do
  @moduledoc """
  Defines packet 3 transaction builder tests for intel marketplace PTB construction.
  """

  use ExUnit.Case, async: true

  @compile {:no_warn_undefined, Sigil.Sui.TxIntelMarket}

  alias Sigil.Sui.BCS
  alias Sigil.Sui.TransactionBuilder
  alias Sigil.Sui.TxIntelMarket

  @package_id Base.decode16!(
                "06CE9D6BED77615383575CC7EBA4883D32769B30CD5DF00561E38434A59611A1",
                case: :mixed
              )

  describe "listing builders" do
    test "build_create_listing produces correct PTB structure" do
      tx_opts = sample_tx_opts()
      params = sample_create_listing_params()

      assert TxIntelMarket.build_create_listing(sample_marketplace_ref(), params, tx_opts) ==
               tx_opts ++
                 [
                   inputs: [
                     {:object, {:shared, object_id(0x10), 7, true}},
                     {:pure, encode_bytes_vector(params.proof_points)},
                     {:pure, encode_bytes_vector(params.public_inputs)},
                     {:pure, BCS.encode_u256(params.commitment)},
                     {:pure, BCS.encode_u64(params.client_nonce)},
                     {:pure, BCS.encode_u64(params.price)},
                     {:pure, BCS.encode_u8(params.report_type)},
                     {:pure, BCS.encode_u32(params.solar_system_id)},
                     {:pure, encode_bytes_vector(params.description)}
                   ],
                   commands: [
                     {:move_call, @package_id, "intel_market", "create_listing", [],
                      [
                        {:input, 0},
                        {:input, 1},
                        {:input, 2},
                        {:input, 3},
                        {:input, 4},
                        {:input, 5},
                        {:input, 6},
                        {:input, 7},
                        {:input, 8}
                      ]}
                   ]
                 ]
    end

    test "build_create_listing encodes proof commitment and nonce" do
      params = sample_create_listing_params()

      build_opts =
        TxIntelMarket.build_create_listing(sample_marketplace_ref(), params, sample_tx_opts())

      assert build_opts[:inputs] == [
               {:object, {:shared, object_id(0x10), 7, true}},
               {:pure, encode_bytes_vector(params.proof_points)},
               {:pure, encode_bytes_vector(params.public_inputs)},
               {:pure, BCS.encode_u256(params.commitment)},
               {:pure, BCS.encode_u64(params.client_nonce)},
               {:pure, BCS.encode_u64(params.price)},
               {:pure, BCS.encode_u8(params.report_type)},
               {:pure, BCS.encode_u32(params.solar_system_id)},
               {:pure, encode_bytes_vector(params.description)}
             ]
    end

    test "create_restricted_listing includes custodian ref" do
      params = sample_create_listing_params()

      build_opts =
        TxIntelMarket.build_create_restricted_listing(
          sample_marketplace_ref(),
          sample_custodian_ref(),
          params,
          sample_tx_opts()
        )

      assert build_opts[:inputs] == [
               {:object, {:shared, object_id(0x10), 7, true}},
               {:object, {:shared, object_id(0x20), 11, false}},
               {:pure, encode_bytes_vector(params.proof_points)},
               {:pure, encode_bytes_vector(params.public_inputs)},
               {:pure, BCS.encode_u256(params.commitment)},
               {:pure, BCS.encode_u64(params.client_nonce)},
               {:pure, BCS.encode_u64(params.price)},
               {:pure, BCS.encode_u8(params.report_type)},
               {:pure, BCS.encode_u32(params.solar_system_id)},
               {:pure, encode_bytes_vector(params.description)}
             ]

      assert build_opts[:commands] == [
               {:move_call, @package_id, "intel_market", "create_restricted_listing", [],
                [
                  {:input, 0},
                  {:input, 1},
                  {:input, 2},
                  {:input, 3},
                  {:input, 4},
                  {:input, 5},
                  {:input, 6},
                  {:input, 7},
                  {:input, 8},
                  {:input, 9}
                ]}
             ]
    end

    test "build_cancel_listing produces cancel move_call" do
      tx_opts = sample_tx_opts()

      assert TxIntelMarket.build_cancel_listing(sample_listing_ref(), tx_opts) ==
               tx_opts ++
                 [
                   inputs: [
                     {:object, {:shared, object_id(0x30), 13, true}}
                   ],
                   commands: [
                     {:move_call, @package_id, "intel_market", "cancel_listing", [],
                      [{:input, 0}]}
                   ]
                 ]
    end
  end

  describe "purchase builders" do
    test "build_purchase creates split-and-call command sequence" do
      tx_opts = sample_tx_opts()

      assert TxIntelMarket.build_purchase(sample_listing_ref(), 125_000_000, tx_opts) ==
               tx_opts ++
                 [
                   inputs: [
                     {:object, {:shared, object_id(0x30), 13, true}},
                     {:pure, BCS.encode_u64(125_000_000)}
                   ],
                   commands: [
                     {:split_coins, :gas_coin, [{:input, 1}]},
                     {:move_call, @package_id, "intel_market", "purchase", [],
                      [{:input, 0}, {:nested_result, 0, 0}]}
                   ]
                 ]
    end

    test "build_purchase_restricted creates split-and-restricted-purchase PTB" do
      tx_opts = sample_tx_opts()

      assert TxIntelMarket.build_purchase_restricted(
               sample_listing_ref(),
               sample_custodian_ref(),
               125_000_000,
               tx_opts
             ) ==
               tx_opts ++
                 [
                   inputs: [
                     {:object, {:shared, object_id(0x30), 13, true}},
                     {:object, {:shared, object_id(0x20), 11, false}},
                     {:pure, BCS.encode_u64(125_000_000)}
                   ],
                   commands: [
                     {:split_coins, :gas_coin, [{:input, 2}]},
                     {:move_call, @package_id, "intel_market", "purchase_restricted", [],
                      [{:input, 0}, {:input, 1}, {:nested_result, 0, 0}]}
                   ]
                 ]
    end
  end

  describe "setup and validation" do
    test "build_setup_pvk encodes all PVK components" do
      pvk_bytes = sample_pvk_bytes()

      build_opts =
        TxIntelMarket.build_setup_pvk(sample_marketplace_ref(), pvk_bytes, sample_tx_opts())

      assert build_opts[:inputs] == [
               {:object, {:shared, object_id(0x10), 7, true}},
               {:pure, encode_bytes_vector(pvk_bytes.vk_gamma_abc_g1)},
               {:pure, encode_bytes_vector(pvk_bytes.alpha_g1_beta_g2)},
               {:pure, encode_bytes_vector(pvk_bytes.gamma_g2_neg_pc)},
               {:pure, encode_bytes_vector(pvk_bytes.delta_g2_neg_pc)}
             ]

      assert build_opts[:commands] == [
               {:move_call, @package_id, "intel_market", "setup_pvk", [],
                [{:input, 0}, {:input, 1}, {:input, 2}, {:input, 3}, {:input, 4}]}
             ]
    end

    test "invalid marketplace ref raises ArgumentError" do
      invalid_marketplace_ref = %{object_id: <<1, 2, 3>>, initial_shared_version: 7}

      assert_raise ArgumentError, fn ->
        TxIntelMarket.build_create_listing(
          invalid_marketplace_ref,
          sample_create_listing_params(),
          sample_tx_opts()
        )
      end
    end

    test "invalid listing ref raises ArgumentError" do
      invalid_listing_ref = %{object_id: <<1, 2, 3>>, initial_shared_version: 13}

      assert_raise ArgumentError, fn ->
        TxIntelMarket.build_cancel_listing(invalid_listing_ref, sample_tx_opts())
      end
    end

    test "invalid custodian ref raises ArgumentError" do
      invalid_custodian_ref = %{object_id: <<1, 2, 3>>, initial_shared_version: 11}

      assert_raise ArgumentError, fn ->
        TxIntelMarket.build_create_restricted_listing(
          sample_marketplace_ref(),
          invalid_custodian_ref,
          sample_create_listing_params(),
          sample_tx_opts()
        )
      end
    end
  end

  describe "TransactionBuilder integration" do
    test "build_create_listing output serializes via build_kind!" do
      build_opts =
        TxIntelMarket.build_create_listing(
          sample_marketplace_ref(),
          sample_create_listing_params(),
          []
        )

      assert is_binary(TransactionBuilder.build_kind!(build_opts))
    end

    test "build_purchase output serializes via build_kind!" do
      build_opts = TxIntelMarket.build_purchase(sample_listing_ref(), 125_000_000, [])

      assert is_binary(TransactionBuilder.build_kind!(build_opts))
    end
  end

  defp sample_marketplace_ref do
    %{object_id: object_id(0x10), initial_shared_version: 7}
  end

  defp sample_custodian_ref do
    %{object_id: object_id(0x20), initial_shared_version: 11}
  end

  defp sample_listing_ref do
    %{object_id: object_id(0x30), initial_shared_version: 13}
  end

  defp sample_create_listing_params do
    %{
      proof_points: <<1, 2, 3, 4>>,
      public_inputs: <<5, 6, 7, 8>>,
      commitment: 123_456_789_012_345_678_901_234_567_890,
      client_nonce: 42,
      price: 125_000_000,
      report_type: 1,
      solar_system_id: 30_001_042,
      description: "Frontier gate fuel intel"
    }
  end

  defp sample_pvk_bytes do
    %{
      vk_gamma_abc_g1: <<10, 11, 12>>,
      alpha_g1_beta_g2: <<13, 14, 15>>,
      gamma_g2_neg_pc: <<16, 17, 18>>,
      delta_g2_neg_pc: <<19, 20, 21>>
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

  defp encode_bytes_vector(bytes) do
    bytes
    |> :binary.bin_to_list()
    |> BCS.encode_vector(&BCS.encode_u8/1)
  end

  defp object_id(byte) do
    :binary.copy(<<byte>>, 32)
  end
end
