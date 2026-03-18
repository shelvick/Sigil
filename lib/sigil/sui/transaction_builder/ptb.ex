defmodule Sigil.Sui.TransactionBuilder.PTB do
  @moduledoc """
  Encodes Sui programmable transaction building blocks into BCS.
  """

  alias Sigil.Sui.BCS

  @type bytes32() :: <<_::256>>
  @type object_ref() :: {bytes32(), non_neg_integer(), bytes32()}
  @type argument() ::
          :gas_coin
          | {:input, non_neg_integer()}
          | {:result, non_neg_integer()}
          | {:nested_result, non_neg_integer(), non_neg_integer()}
  @type shared_object() :: {:shared, binary(), non_neg_integer(), boolean()}
  @type owned_object() :: {:imm_or_owned, object_ref()}
  @type receiving_object() :: {:receiving, object_ref()}
  @type object_arg() :: shared_object() | owned_object() | receiving_object()
  @type call_arg() :: {:pure, binary()} | {:object, object_arg()}
  @type type_tag() ::
          :bool
          | :u8
          | :u16
          | :u32
          | :u64
          | :u128
          | :u256
          | :address
          | :signer
          | {:vector, type_tag()}
          | {:struct, binary(), String.t(), String.t(), [type_tag()]}
  @type struct_tag() :: {binary(), String.t(), String.t(), [type_tag()]}
  @type move_call() :: {binary(), String.t(), String.t(), [type_tag()], [argument()]}
  @type command() :: {:move_call, binary(), String.t(), String.t(), [type_tag()], [argument()]}
  @type programmable_transaction() :: %{inputs: [call_arg()], commands: [command()]}
  @type gas_data() :: %{
          payment: [object_ref()],
          owner: binary(),
          price: non_neg_integer(),
          budget: non_neg_integer()
        }
  @type expiration() :: :none | {:epoch, non_neg_integer()}
  @type transaction_data_v1() :: %{
          kind: programmable_transaction(),
          sender: binary(),
          gas_data: gas_data(),
          expiration: expiration()
        }

  # BCS variant indices for TypeTag primitives. U16/U32/U256 are non-sequential
  # (indices 8-10) because they were appended to the Move TypeTag enum after the
  # original definition for backward compatibility.
  @type_tag_indices %{
    bool: 0x00,
    u8: 0x01,
    u64: 0x02,
    u128: 0x03,
    address: 0x04,
    signer: 0x05,
    u16: 0x08,
    u32: 0x09,
    u256: 0x0A
  }

  @doc "Encodes a programmable transaction argument."
  @spec encode_argument(argument()) :: binary()
  def encode_argument(:gas_coin), do: <<0x00>>

  @doc false
  def encode_argument({:input, index}) when is_integer(index) and index >= 0 do
    <<0x01>> <> BCS.encode_u16(index)
  end

  @doc false
  def encode_argument({:result, index}) when is_integer(index) and index >= 0 do
    <<0x02>> <> BCS.encode_u16(index)
  end

  @doc false
  def encode_argument({:nested_result, result_index, nested_index})
      when is_integer(result_index) and result_index >= 0 and is_integer(nested_index) and
             nested_index >= 0 do
    <<0x03>> <> BCS.encode_u16(result_index) <> BCS.encode_u16(nested_index)
  end

  @doc "Encodes a programmable transaction call argument."
  @spec encode_call_arg(call_arg()) :: binary()
  def encode_call_arg({:pure, bytes}) when is_binary(bytes) do
    <<0x00>> <> BCS.encode_uleb128(byte_size(bytes)) <> bytes
  end

  @doc false
  def encode_call_arg({:object, {:imm_or_owned, object_ref}}) do
    <<0x01, 0x00>> <> encode_object_ref(object_ref)
  end

  @doc false
  def encode_call_arg({:object, {:shared, object_id, version, mutable}})
      when is_integer(version) and version >= 0 do
    <<0x01, 0x01>> <>
      BCS.encode_address(object_id) <>
      BCS.encode_u64(version) <>
      BCS.encode_bool(mutable)
  end

  @doc false
  def encode_call_arg({:object, {:receiving, object_ref}}) do
    <<0x01, 0x02>> <> encode_object_ref(object_ref)
  end

  @doc "Encodes an object reference tuple."
  @spec encode_object_ref(object_ref()) :: binary()
  def encode_object_ref(
        {<<_::binary-size(32)>> = object_id, version, <<_::binary-size(32)>> = digest}
      )
      when is_integer(version) and version >= 0 do
    BCS.encode_address(object_id) <>
      BCS.encode_u64(version) <>
      BCS.encode_uleb128(byte_size(digest)) <> digest
  end

  @doc "Encodes gas data for a transaction."
  @spec encode_gas_data(gas_data()) :: binary()
  def encode_gas_data(%{payment: payment, owner: owner, price: price, budget: budget})
      when is_list(payment) and is_integer(price) and price >= 0 and is_integer(budget) and
             budget >= 0 do
    BCS.encode_vector(payment, &encode_object_ref/1) <>
      BCS.encode_address(owner) <>
      BCS.encode_u64(price) <>
      BCS.encode_u64(budget)
  end

  @doc "Encodes transaction expiration."
  @spec encode_transaction_expiration(expiration()) :: binary()
  def encode_transaction_expiration(:none), do: <<0x00>>

  @doc false
  def encode_transaction_expiration({:epoch, epoch}) when is_integer(epoch) and epoch >= 0 do
    <<0x01>> <> BCS.encode_u64(epoch)
  end

  @doc "Encodes a Move type tag."
  @spec encode_type_tag(type_tag()) :: binary()
  def encode_type_tag(primitive) when is_map_key(@type_tag_indices, primitive) do
    <<Map.fetch!(@type_tag_indices, primitive)>>
  end

  @doc false
  def encode_type_tag({:vector, type_tag}), do: <<0x06>> <> encode_type_tag(type_tag)

  @doc false
  def encode_type_tag({:struct, address, module, name, type_params}) do
    <<0x07>> <> encode_struct_tag({address, module, name, type_params})
  end

  @doc "Encodes a Move struct tag."
  @spec encode_struct_tag(struct_tag()) :: binary()
  def encode_struct_tag({address, module, name, type_params}) when is_list(type_params) do
    BCS.encode_address(address) <>
      BCS.encode_string(module) <>
      BCS.encode_string(name) <>
      BCS.encode_vector(type_params, &encode_type_tag/1)
  end

  @doc "Encodes a programmable Move call."
  @spec encode_move_call(move_call()) :: binary()
  def encode_move_call({package, module, function, type_arguments, arguments})
      when is_list(type_arguments) and is_list(arguments) do
    BCS.encode_address(package) <>
      BCS.encode_string(module) <>
      BCS.encode_string(function) <>
      BCS.encode_vector(type_arguments, &encode_type_tag/1) <>
      BCS.encode_vector(arguments, &encode_argument/1)
  end

  @doc "Encodes a programmable transaction command."
  @spec encode_command(command()) :: binary()
  def encode_command({:move_call, package, module, function, type_arguments, arguments}) do
    <<0x00>> <> encode_move_call({package, module, function, type_arguments, arguments})
  end

  @doc "Encodes a programmable transaction."
  @spec encode_programmable_transaction(programmable_transaction()) :: binary()
  def encode_programmable_transaction(%{inputs: inputs, commands: commands})
      when is_list(inputs) and is_list(commands) do
    BCS.encode_vector(inputs, &encode_call_arg/1) <>
      BCS.encode_vector(commands, &encode_command/1)
  end

  @doc "Encodes just the TransactionKind enum (ProgrammableTransaction variant)."
  @spec encode_transaction_kind(programmable_transaction()) :: binary()
  def encode_transaction_kind(%{inputs: _inputs, commands: _commands} = kind) do
    <<0x00>> <> encode_programmable_transaction(kind)
  end

  @doc "Encodes the TransactionDataV1 struct."
  @spec encode_transaction_data_v1(transaction_data_v1()) :: binary()
  # Sui uses the protocol name TransactionDataV1, so the public API keeps that exact suffix.
  # credo:disable-for-next-line Credo.Check.Warning.LegacyCodeMarkers
  def encode_transaction_data_v1(%{
        kind: kind,
        sender: sender,
        gas_data: gas_data,
        expiration: expiration
      }) do
    <<0x00>> <>
      encode_programmable_transaction(kind) <>
      BCS.encode_address(sender) <>
      encode_gas_data(gas_data) <>
      encode_transaction_expiration(expiration)
  end

  @doc "Encodes the outer TransactionData enum."
  @spec encode_transaction_data(transaction_data_v1()) :: binary()
  def encode_transaction_data(transaction_data_v1) do
    <<0x00>> <> encode_transaction_data_v1(transaction_data_v1)
  end
end
