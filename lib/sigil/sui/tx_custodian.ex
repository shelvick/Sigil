defmodule Sigil.Sui.TxCustodian do
  @moduledoc """
  Builds programmable transaction options for TribeCustodian operations.
  """

  alias Sigil.Sui.BCS
  alias Sigil.Sui.TransactionBuilder
  alias Sigil.Sui.TransactionBuilder.PTB
  alias Sigil.Worlds

  @module_name "tribe_custodian"

  @typedoc "Shared object reference for an existing TribeCustodianRegistry."
  @type registry_ref() :: %{
          object_id: PTB.bytes32(),
          initial_shared_version: non_neg_integer()
        }

  @typedoc "Shared object reference for an existing Custodian."
  @type custodian_ref() :: %{
          object_id: PTB.bytes32(),
          initial_shared_version: non_neg_integer()
        }

  @typedoc "Shared object reference for an existing Character."
  @type character_ref() :: %{
          object_id: PTB.bytes32(),
          initial_shared_version: non_neg_integer()
        }

  @typedoc "Single transaction option accepted by custodian transaction builders."
  @type tx_opt() ::
          {:sender, PTB.bytes32()}
          | {:gas_payment, [PTB.object_ref()]}
          | {:gas_price, non_neg_integer()}
          | {:gas_budget, non_neg_integer()}
          | {:world, Worlds.world_name()}

  @typedoc "Base transaction options required by the transaction builder."
  @type tx_opts() :: [tx_opt()]

  @typedoc "Custodian standing tier."
  @type standing() :: 0..4

  @typedoc "Transaction builder options for full or kind-only transaction construction."
  @type builder_opts() :: TransactionBuilder.build_opts() | TransactionBuilder.kind_opts()

  @doc "Builds transaction options for `tribe_custodian::create_custodian`."
  @spec build_create_custodian(registry_ref(), character_ref(), tx_opts()) :: builder_opts()
  def build_create_custodian(registry_ref, character_ref, tx_opts) when is_list(tx_opts) do
    inputs = [shared_mut_input(registry_ref), shared_imm_input(character_ref)]
    build_opts(tx_opts, inputs, "create_custodian")
  end

  @doc "Builds transaction options for `tribe_custodian::join`."
  @spec build_join(custodian_ref(), character_ref(), tx_opts()) :: builder_opts()
  def build_join(custodian_ref, character_ref, tx_opts) when is_list(tx_opts) do
    inputs = [shared_mut_input(custodian_ref), shared_imm_input(character_ref)]
    build_opts(tx_opts, inputs, "join")
  end

  @doc "Builds transaction options for `tribe_custodian::vote_leader`."
  @spec build_vote_leader(custodian_ref(), character_ref(), PTB.bytes32(), tx_opts()) ::
          builder_opts()
  def build_vote_leader(custodian_ref, character_ref, candidate, tx_opts) when is_list(tx_opts) do
    inputs = [
      shared_mut_input(custodian_ref),
      shared_imm_input(character_ref),
      {:pure, BCS.encode_address(validate_address!(candidate))}
    ]

    build_opts(tx_opts, inputs, "vote_leader")
  end

  @doc "Builds transaction options for `tribe_custodian::claim_leadership`."
  @spec build_claim_leadership(custodian_ref(), character_ref(), tx_opts()) :: builder_opts()
  def build_claim_leadership(custodian_ref, character_ref, tx_opts) when is_list(tx_opts) do
    inputs = [shared_mut_input(custodian_ref), shared_imm_input(character_ref)]
    build_opts(tx_opts, inputs, "claim_leadership")
  end

  @doc "Builds transaction options for `tribe_custodian::add_operator`."
  @spec build_add_operator(custodian_ref(), character_ref(), PTB.bytes32(), tx_opts()) ::
          builder_opts()
  def build_add_operator(custodian_ref, character_ref, operator, tx_opts) when is_list(tx_opts) do
    inputs = [
      shared_mut_input(custodian_ref),
      shared_imm_input(character_ref),
      {:pure, BCS.encode_address(validate_address!(operator))}
    ]

    build_opts(tx_opts, inputs, "add_operator")
  end

  @doc "Builds transaction options for `tribe_custodian::remove_operator`."
  @spec build_remove_operator(custodian_ref(), character_ref(), PTB.bytes32(), tx_opts()) ::
          builder_opts()
  def build_remove_operator(custodian_ref, character_ref, operator, tx_opts)
      when is_list(tx_opts) do
    inputs = [
      shared_mut_input(custodian_ref),
      shared_imm_input(character_ref),
      {:pure, BCS.encode_address(validate_address!(operator))}
    ]

    build_opts(tx_opts, inputs, "remove_operator")
  end

  @doc "Builds transaction options for `tribe_custodian::set_standing`."
  @spec build_set_standing(
          custodian_ref(),
          character_ref(),
          non_neg_integer(),
          standing(),
          tx_opts()
        ) ::
          builder_opts()
  def build_set_standing(custodian_ref, character_ref, tribe_id, standing, tx_opts)
      when is_integer(tribe_id) and tribe_id >= 0 and is_list(tx_opts) do
    validate_standing!(standing)

    inputs = [
      shared_mut_input(custodian_ref),
      shared_imm_input(character_ref),
      {:pure, BCS.encode_u32(tribe_id)},
      {:pure, BCS.encode_u8(standing)}
    ]

    build_opts(tx_opts, inputs, "set_standing")
  end

  @doc "Builds transaction options for `tribe_custodian::set_default_standing`."
  @spec build_set_default_standing(custodian_ref(), character_ref(), standing(), tx_opts()) ::
          builder_opts()
  def build_set_default_standing(custodian_ref, character_ref, standing, tx_opts)
      when is_list(tx_opts) do
    validate_standing!(standing)

    inputs = [
      shared_mut_input(custodian_ref),
      shared_imm_input(character_ref),
      {:pure, BCS.encode_u8(standing)}
    ]

    build_opts(tx_opts, inputs, "set_default_standing")
  end

  @doc "Builds transaction options for `tribe_custodian::set_pilot_standing`."
  @spec build_set_pilot_standing(
          custodian_ref(),
          character_ref(),
          PTB.bytes32(),
          standing(),
          tx_opts()
        ) ::
          builder_opts()
  def build_set_pilot_standing(custodian_ref, character_ref, pilot, standing, tx_opts)
      when is_list(tx_opts) do
    validate_standing!(standing)

    inputs = [
      shared_mut_input(custodian_ref),
      shared_imm_input(character_ref),
      {:pure, BCS.encode_address(validate_address!(pilot))},
      {:pure, BCS.encode_u8(standing)}
    ]

    build_opts(tx_opts, inputs, "set_pilot_standing")
  end

  @doc "Builds transaction options for `tribe_custodian::batch_set_standings`."
  @spec build_batch_set_standings(
          custodian_ref(),
          character_ref(),
          [{non_neg_integer(), standing()}],
          tx_opts()
        ) ::
          builder_opts()
  def build_batch_set_standings(custodian_ref, character_ref, updates, tx_opts)
      when is_list(updates) and is_list(tx_opts) do
    ensure_non_empty_batch!(updates)

    {tribe_ids, standings} = Enum.unzip(updates)
    Enum.each(standings, &validate_standing!/1)

    inputs = [
      shared_mut_input(custodian_ref),
      shared_imm_input(character_ref),
      {:pure, BCS.encode_vector(tribe_ids, &BCS.encode_u32/1)},
      {:pure, BCS.encode_vector(standings, &BCS.encode_u8/1)}
    ]

    build_opts(tx_opts, inputs, "batch_set_standings")
  end

  @doc "Builds transaction options for `tribe_custodian::batch_set_pilot_standings`."
  @spec build_batch_set_pilot_standings(
          custodian_ref(),
          character_ref(),
          [{PTB.bytes32(), standing()}],
          tx_opts()
        ) ::
          builder_opts()
  def build_batch_set_pilot_standings(custodian_ref, character_ref, updates, tx_opts)
      when is_list(updates) and is_list(tx_opts) do
    ensure_non_empty_batch!(updates)

    {pilots, standings} = Enum.unzip(updates)
    Enum.each(pilots, &validate_address!/1)
    Enum.each(standings, &validate_standing!/1)

    inputs = [
      shared_mut_input(custodian_ref),
      shared_imm_input(character_ref),
      {:pure, BCS.encode_vector(pilots, &BCS.encode_address/1)},
      {:pure, BCS.encode_vector(standings, &BCS.encode_u8/1)}
    ]

    build_opts(tx_opts, inputs, "batch_set_pilot_standings")
  end

  @doc "Builds transaction options for `tribe_custodian::set_oracle`."
  @spec build_set_oracle(custodian_ref(), character_ref(), PTB.bytes32(), tx_opts()) ::
          builder_opts()
  def build_set_oracle(custodian_ref, character_ref, oracle_address, tx_opts)
      when is_list(tx_opts) do
    inputs = [
      shared_mut_input(custodian_ref),
      shared_imm_input(character_ref),
      {:pure, BCS.encode_address(validate_address!(oracle_address))}
    ]

    build_opts(tx_opts, inputs, "set_oracle")
  end

  @doc "Builds transaction options for `tribe_custodian::remove_oracle`."
  @spec build_remove_oracle(custodian_ref(), character_ref(), tx_opts()) :: builder_opts()
  def build_remove_oracle(custodian_ref, character_ref, tx_opts) when is_list(tx_opts) do
    inputs = [shared_mut_input(custodian_ref), shared_imm_input(character_ref)]
    build_opts(tx_opts, inputs, "remove_oracle")
  end

  @doc "Builds transaction options for `tribe_custodian::oracle_set_standing`."
  @spec build_oracle_set_standing(custodian_ref(), non_neg_integer(), standing(), tx_opts()) ::
          builder_opts()
  def build_oracle_set_standing(custodian_ref, tribe_id, standing, tx_opts)
      when is_integer(tribe_id) and tribe_id >= 0 and is_list(tx_opts) do
    validate_standing!(standing)

    inputs = [
      shared_mut_input(custodian_ref),
      {:pure, BCS.encode_u32(tribe_id)},
      {:pure, BCS.encode_u8(standing)}
    ]

    build_opts(tx_opts, inputs, "oracle_set_standing")
  end

  @doc "Builds transaction options for `tribe_custodian::oracle_batch_set_standings`."
  @spec build_oracle_batch_set_standings(
          custodian_ref(),
          [{non_neg_integer(), standing()}],
          tx_opts()
        ) ::
          builder_opts()
  def build_oracle_batch_set_standings(custodian_ref, updates, tx_opts)
      when is_list(updates) and is_list(tx_opts) do
    ensure_non_empty_batch!(updates)

    {tribe_ids, standings} = Enum.unzip(updates)
    Enum.each(standings, &validate_standing!/1)

    inputs = [
      shared_mut_input(custodian_ref),
      {:pure, BCS.encode_vector(tribe_ids, &BCS.encode_u32/1)},
      {:pure, BCS.encode_vector(standings, &BCS.encode_u8/1)}
    ]

    build_opts(tx_opts, inputs, "oracle_batch_set_standings")
  end

  defp build_opts(tx_opts, inputs, function) do
    tx_opts ++ [inputs: inputs, commands: [move_call(function, input_arguments(inputs), tx_opts)]]
  end

  defp move_call(function, arguments, tx_opts) when is_list(tx_opts) do
    {:move_call, sigil_package_id_bytes(tx_opts), @module_name, function, [], arguments}
  end

  @spec sigil_package_id_bytes(tx_opts()) :: binary()
  defp sigil_package_id_bytes(tx_opts) when is_list(tx_opts) do
    "0x" <> hex = sigil_package_id(tx_opts)
    Base.decode16!(hex, case: :mixed)
  end

  @spec sigil_package_id(tx_opts()) :: String.t()
  defp sigil_package_id(tx_opts) when is_list(tx_opts) do
    tx_opts
    |> world()
    |> Worlds.sigil_package_id()
  end

  @spec world(tx_opts()) :: Worlds.world_name()
  defp world(tx_opts) when is_list(tx_opts) do
    Keyword.get(tx_opts, :world, Worlds.default_world())
  end

  defp input_arguments(inputs) do
    for {_input, index} <- Enum.with_index(inputs), do: {:input, index}
  end

  defp shared_mut_input(ref), do: shared_input(ref, true)
  defp shared_imm_input(ref), do: shared_input(ref, false)

  defp shared_input(%{object_id: object_id, initial_shared_version: version}, mutable)
       when is_integer(version) and version >= 0 do
    {:object, {:shared, validate_address!(object_id), version, mutable}}
  end

  defp shared_input(_ref, _mutable) do
    raise ArgumentError,
          "shared object ref must include a 32-byte object_id and non-negative initial_shared_version"
  end

  defp validate_address!(<<_::binary-size(32)>> = address), do: address

  defp validate_address!(_address) do
    raise ArgumentError, "address must be exactly 32 bytes"
  end

  defp validate_standing!(standing) when standing in 0..4, do: :ok

  defp validate_standing!(_standing) do
    raise ArgumentError, "standing must be between 0 and 4"
  end

  defp ensure_non_empty_batch!([]), do: raise(ArgumentError, "batch updates must not be empty")
  defp ensure_non_empty_batch!(_updates), do: :ok
end
