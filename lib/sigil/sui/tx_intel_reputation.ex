defmodule Sigil.Sui.TxIntelReputation do
  @moduledoc """
  Builds programmable transaction options for intel reputation operations.
  """

  alias Sigil.Sui.TransactionBuilder
  alias Sigil.Sui.TransactionBuilder.PTB

  @module_name "intel_reputation"

  @typedoc "Shared object reference for the reputation registry singleton."
  @type registry_ref() :: %{
          object_id: PTB.bytes32(),
          initial_shared_version: non_neg_integer()
        }

  @typedoc "Shared object reference for an IntelListing."
  @type listing_ref() :: %{
          object_id: PTB.bytes32(),
          initial_shared_version: non_neg_integer()
        }

  @typedoc "Base transaction options required by the transaction builder."
  @type tx_opts() :: Sigil.Sui.TxCustodian.tx_opts()

  @typedoc "Transaction builder options for full or kind-only transaction construction."
  @type builder_opts() :: TransactionBuilder.build_opts() | TransactionBuilder.kind_opts()

  @doc "Builds transaction options for `intel_reputation::confirm_quality`."
  @spec build_confirm_quality(registry_ref(), listing_ref(), tx_opts()) :: builder_opts()
  def build_confirm_quality(registry_ref, listing_ref, tx_opts) when is_list(tx_opts) do
    inputs = [shared_mut_input(registry_ref), shared_imm_input(listing_ref)]
    build_opts(tx_opts, inputs, "confirm_quality")
  end

  @doc "Builds transaction options for `intel_reputation::report_bad_quality`."
  @spec build_report_bad_quality(registry_ref(), listing_ref(), tx_opts()) :: builder_opts()
  def build_report_bad_quality(registry_ref, listing_ref, tx_opts) when is_list(tx_opts) do
    inputs = [shared_mut_input(registry_ref), shared_imm_input(listing_ref)]
    build_opts(tx_opts, inputs, "report_bad_quality")
  end

  @spec build_opts(tx_opts(), [PTB.call_arg()], String.t()) :: builder_opts()
  defp build_opts(tx_opts, inputs, function) do
    tx_opts ++ [inputs: inputs, commands: [move_call(function, input_arguments(inputs))]]
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

  @spec shared_mut_input(map()) :: PTB.call_arg()
  defp shared_mut_input(ref), do: shared_input(ref, true)

  @spec shared_imm_input(map()) :: PTB.call_arg()
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
end
