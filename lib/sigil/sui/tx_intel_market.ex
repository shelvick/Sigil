defmodule Sigil.Sui.TxIntelMarket do
  @moduledoc """
  Builds programmable transaction options for intel marketplace operations.
  """

  alias Sigil.Sui.BCS
  alias Sigil.Sui.TransactionBuilder
  alias Sigil.Sui.TransactionBuilder.PTB

  @module_name "intel_market"

  @typedoc "Shared object reference for the IntelMarketplace singleton."
  @type marketplace_ref() :: %{
          object_id: PTB.bytes32(),
          initial_shared_version: non_neg_integer()
        }

  @typedoc "Shared object reference for an IntelListing."
  @type listing_ref() :: %{
          object_id: PTB.bytes32(),
          initial_shared_version: non_neg_integer()
        }

  @typedoc "Shared object reference for a tribe custodian."
  @type custodian_ref() :: %{
          object_id: PTB.bytes32(),
          initial_shared_version: non_neg_integer()
        }

  @typedoc "Base transaction options required by the transaction builder."
  @type tx_opts() :: Sigil.Sui.TxCustodian.tx_opts()

  @typedoc "Transaction builder options for full or kind-only transaction construction."
  @type builder_opts() :: TransactionBuilder.build_opts() | TransactionBuilder.kind_opts()

  @typedoc "Structured byte payload for Groth16 verifying key setup."
  @type pvk_bytes() :: %{
          vk_gamma_abc_g1: binary(),
          alpha_g1_beta_g2: binary(),
          gamma_g2_neg_pc: binary(),
          delta_g2_neg_pc: binary()
        }

  @typedoc "Marketplace listing creation parameters."
  @type listing_params() :: %{
          proof_points: binary(),
          public_inputs: binary(),
          commitment: non_neg_integer(),
          client_nonce: non_neg_integer(),
          price: non_neg_integer(),
          report_type: non_neg_integer(),
          solar_system_id: non_neg_integer(),
          description: binary()
        }

  @doc "Builds transaction options for `intel_market::setup_pvk`."
  @spec build_setup_pvk(marketplace_ref(), pvk_bytes(), tx_opts()) :: builder_opts()
  def build_setup_pvk(marketplace_ref, pvk_bytes, tx_opts) when is_list(tx_opts) do
    inputs = [
      shared_mut_input(marketplace_ref),
      {:pure, encode_bytes_vector(Map.fetch!(pvk_bytes, :vk_gamma_abc_g1))},
      {:pure, encode_bytes_vector(Map.fetch!(pvk_bytes, :alpha_g1_beta_g2))},
      {:pure, encode_bytes_vector(Map.fetch!(pvk_bytes, :gamma_g2_neg_pc))},
      {:pure, encode_bytes_vector(Map.fetch!(pvk_bytes, :delta_g2_neg_pc))}
    ]

    build_opts(tx_opts, inputs, [move_call("setup_pvk", input_arguments(inputs))])
  end

  @doc "Builds transaction options for `intel_market::create_listing`."
  @spec build_create_listing(marketplace_ref(), listing_params(), tx_opts()) :: builder_opts()
  def build_create_listing(marketplace_ref, params, tx_opts) when is_list(tx_opts) do
    inputs = [
      shared_mut_input(marketplace_ref),
      {:pure, encode_bytes_vector(Map.fetch!(params, :proof_points))},
      {:pure, encode_bytes_vector(Map.fetch!(params, :public_inputs))},
      {:pure, BCS.encode_u256(Map.fetch!(params, :commitment))},
      {:pure, BCS.encode_u64(Map.fetch!(params, :client_nonce))},
      {:pure, BCS.encode_u64(Map.fetch!(params, :price))},
      {:pure, BCS.encode_u8(Map.fetch!(params, :report_type))},
      {:pure, BCS.encode_u32(Map.fetch!(params, :solar_system_id))},
      {:pure, encode_bytes_vector(Map.fetch!(params, :description))}
    ]

    build_opts(tx_opts, inputs, [move_call("create_listing", input_arguments(inputs))])
  end

  @doc "Builds transaction options for `intel_market::create_restricted_listing`."
  @spec build_create_restricted_listing(
          marketplace_ref(),
          custodian_ref(),
          listing_params(),
          tx_opts()
        ) :: builder_opts()
  def build_create_restricted_listing(marketplace_ref, custodian_ref, params, tx_opts)
      when is_list(tx_opts) do
    inputs = [
      shared_mut_input(marketplace_ref),
      shared_imm_input(custodian_ref),
      {:pure, encode_bytes_vector(Map.fetch!(params, :proof_points))},
      {:pure, encode_bytes_vector(Map.fetch!(params, :public_inputs))},
      {:pure, BCS.encode_u256(Map.fetch!(params, :commitment))},
      {:pure, BCS.encode_u64(Map.fetch!(params, :client_nonce))},
      {:pure, BCS.encode_u64(Map.fetch!(params, :price))},
      {:pure, BCS.encode_u8(Map.fetch!(params, :report_type))},
      {:pure, BCS.encode_u32(Map.fetch!(params, :solar_system_id))},
      {:pure, encode_bytes_vector(Map.fetch!(params, :description))}
    ]

    build_opts(
      tx_opts,
      inputs,
      [move_call("create_restricted_listing", input_arguments(inputs))]
    )
  end

  @doc "Builds transaction options for `intel_market::purchase`."
  @spec build_purchase(listing_ref(), non_neg_integer(), tx_opts()) :: builder_opts()
  def build_purchase(listing_ref, amount_mist, tx_opts)
      when is_integer(amount_mist) and amount_mist >= 0 and is_list(tx_opts) do
    inputs = [shared_mut_input(listing_ref), {:pure, BCS.encode_u64(amount_mist)}]

    commands = [
      {:split_coins, :gas_coin, [{:input, 1}]},
      move_call("purchase", [{:input, 0}, {:nested_result, 0, 0}])
    ]

    build_opts(tx_opts, inputs, commands)
  end

  @doc "Builds transaction options for `intel_market::purchase_restricted`."
  @spec build_purchase_restricted(listing_ref(), custodian_ref(), non_neg_integer(), tx_opts()) ::
          builder_opts()
  def build_purchase_restricted(listing_ref, custodian_ref, amount_mist, tx_opts)
      when is_integer(amount_mist) and amount_mist >= 0 and is_list(tx_opts) do
    inputs = [
      shared_mut_input(listing_ref),
      shared_imm_input(custodian_ref),
      {:pure, BCS.encode_u64(amount_mist)}
    ]

    commands = [
      {:split_coins, :gas_coin, [{:input, 2}]},
      move_call("purchase_restricted", [{:input, 0}, {:input, 1}, {:nested_result, 0, 0}])
    ]

    build_opts(tx_opts, inputs, commands)
  end

  @doc "Builds transaction options for `intel_market::cancel_listing`."
  @spec build_cancel_listing(listing_ref(), tx_opts()) :: builder_opts()
  def build_cancel_listing(listing_ref, tx_opts) when is_list(tx_opts) do
    inputs = [shared_mut_input(listing_ref)]
    build_opts(tx_opts, inputs, [move_call("cancel_listing", input_arguments(inputs))])
  end

  @spec build_opts(tx_opts(), [PTB.call_arg()], [PTB.command()]) :: builder_opts()
  defp build_opts(tx_opts, inputs, commands) do
    tx_opts ++ [inputs: inputs, commands: commands]
  end

  @spec move_call(String.t(), [PTB.argument()]) :: PTB.command()
  defp move_call(function, arguments) do
    {:move_call, sigil_package_id_bytes(), @module_name, function, [], arguments}
  end

  @spec sigil_package_id_bytes() :: PTB.bytes32()
  defp sigil_package_id_bytes do
    "0x" <> hex = sigil_package_id()
    Base.decode16!(hex, case: :mixed)
  end

  @spec sigil_package_id() :: String.t()
  defp sigil_package_id do
    world = Application.fetch_env!(:sigil, :eve_world)
    worlds = Application.fetch_env!(:sigil, :eve_worlds)
    %{sigil_package_id: id} = Map.fetch!(worlds, world)
    id
  end

  @spec input_arguments([PTB.call_arg()]) :: [PTB.argument()]
  defp input_arguments(inputs) do
    for {_input, index} <- Enum.with_index(inputs), do: {:input, index}
  end

  @spec shared_mut_input(marketplace_ref() | listing_ref()) :: PTB.call_arg()
  defp shared_mut_input(ref), do: shared_input(ref, true)

  @spec shared_imm_input(custodian_ref()) :: PTB.call_arg()
  defp shared_imm_input(ref), do: shared_input(ref, false)

  @spec shared_input(map(), boolean()) :: PTB.call_arg()
  defp shared_input(%{object_id: object_id, initial_shared_version: version}, mutable)
       when is_integer(version) and version >= 0 do
    {:object, {:shared, validate_address!(object_id), version, mutable}}
  end

  defp shared_input(_ref, _mutable) do
    raise ArgumentError,
          "shared object ref must include a 32-byte object_id and non-negative initial_shared_version"
  end

  @spec validate_address!(binary()) :: PTB.bytes32()
  defp validate_address!(<<_::binary-size(32)>> = address), do: address

  defp validate_address!(_address) do
    raise ArgumentError, "address must be exactly 32 bytes"
  end

  @spec encode_bytes_vector(binary()) :: binary()
  defp encode_bytes_vector(bytes) when is_binary(bytes) do
    bytes
    |> :binary.bin_to_list()
    |> BCS.encode_vector(&BCS.encode_u8/1)
  end
end
