defmodule Sigil.Sui.TransactionBuilder.PTBTest do
  @moduledoc """
  Covers packet 1 PTB encoding requirements for the transaction builder.
  """

  use ExUnit.Case, async: true

  alias Sigil.Sui.BCS
  alias Sigil.Sui.TransactionBuilder.PTB

  describe "argument encoding" do
    test "encodes GasCoin argument as variant 0" do
      assert PTB.encode_argument(:gas_coin) == <<0x00>>
    end

    test "encodes Input argument with u16 index" do
      assert PTB.encode_argument({:input, 3}) == <<0x01, 0x03, 0x00>>
    end

    test "encodes Result argument with u16 index" do
      assert PTB.encode_argument({:result, 1}) == <<0x02, 0x01, 0x00>>
    end

    test "encodes NestedResult argument with two u16 indices" do
      assert PTB.encode_argument({:nested_result, 1, 2}) == <<0x03, 0x01, 0x00, 0x02, 0x00>>
    end
  end

  describe "call arg encoding" do
    test "encodes Pure call arg with length-prefixed bytes" do
      assert PTB.encode_call_arg({:pure, <<1, 2, 3>>}) == <<0x00, 0x03, 0x01, 0x02, 0x03>>
    end

    test "encodes ImmOrOwned object call arg" do
      object_ref = sample_object_ref()

      assert PTB.encode_call_arg({:object, {:imm_or_owned, object_ref}}) ==
               <<0x01, 0x00>> <> expected_object_ref(object_ref)
    end

    test "encodes Shared object call arg with mutability flag" do
      shared_id = address(0x33)

      assert PTB.encode_call_arg({:object, {:shared, shared_id, 9, true}}) ==
               <<0x01, 0x01>> <> shared_id <> BCS.encode_u64(9) <> BCS.encode_bool(true)
    end
  end

  describe "core struct encoding" do
    test "encodes ObjectRef as 73-byte tuple (digest is length-prefixed)" do
      object_ref = sample_object_ref()
      encoded = PTB.encode_object_ref(object_ref)

      assert encoded == expected_object_ref(object_ref)
      assert byte_size(encoded) == 73
    end

    test "encodes GasData with correct field order" do
      payment_ref = sample_object_ref()
      owner = address(0x44)
      gas_data = %{payment: [payment_ref], owner: owner, price: 1_000, budget: 50_000_000}

      assert PTB.encode_gas_data(gas_data) ==
               BCS.encode_uleb128(1) <>
                 expected_object_ref(payment_ref) <>
                 owner <>
                 <<0xE8, 0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00>> <>
                 <<0x80, 0xF0, 0xFA, 0x02, 0x00, 0x00, 0x00, 0x00>>
    end

    test "encodes None expiration as variant 0" do
      assert PTB.encode_transaction_expiration(:none) == <<0x00>>
    end

    test "encodes Epoch expiration with u64 epoch number" do
      assert PTB.encode_transaction_expiration({:epoch, 100}) == <<0x01>> <> BCS.encode_u64(100)
    end

    test "encodes all primitive TypeTag variants with correct indices" do
      assert PTB.encode_type_tag(:bool) == <<0x00>>
      assert PTB.encode_type_tag(:u8) == <<0x01>>
      assert PTB.encode_type_tag(:u64) == <<0x02>>
      assert PTB.encode_type_tag(:u128) == <<0x03>>
      assert PTB.encode_type_tag(:address) == <<0x04>>
      assert PTB.encode_type_tag(:signer) == <<0x05>>
      assert PTB.encode_type_tag(:u16) == <<0x08>>
      assert PTB.encode_type_tag(:u32) == <<0x09>>
      assert PTB.encode_type_tag(:u256) == <<0x0A>>
    end

    test "encodes Vector TypeTag with nested element type" do
      assert PTB.encode_type_tag({:vector, :u8}) == <<0x06, 0x01>>
    end

    test "encodes Struct TypeTag with StructTag" do
      struct_tag = {address(0x55), "module", "Name", []}

      assert PTB.encode_type_tag({:struct, address(0x55), "module", "Name", []}) ==
               <<0x07>> <> expected_struct_tag(struct_tag)
    end

    test "encodes StructTag with correct field order" do
      struct_tag = {address(0x66), "coin", "Coin", [:u64]}

      assert PTB.encode_struct_tag(struct_tag) == expected_struct_tag(struct_tag)
    end

    test "encodes MoveCall with correct field order" do
      move_call = {address(0x77), "mod", "fun", [], [:gas_coin]}

      assert PTB.encode_move_call(move_call) == expected_move_call(move_call)
    end

    test "encodes MoveCall command as variant 0" do
      move_call = {address(0x88), "mod", "fun", [], [:gas_coin]}

      assert PTB.encode_command({:move_call, address(0x88), "mod", "fun", [], [:gas_coin]}) ==
               <<0x00>> <> expected_move_call(move_call)
    end

    test "encodes SplitCoins command as variant 2" do
      split_coins = {:split_coins, :gas_coin, [{:input, 1}]}

      assert PTB.encode_command(split_coins) == expected_command(split_coins)
    end

    test "encodes ProgrammableTransaction with inputs before commands" do
      programmable_transaction = %{
        inputs: [{:pure, <<1, 2, 3>>}],
        commands: [{:move_call, address(0x99), "mod", "fun", [], [:gas_coin]}]
      }

      assert PTB.encode_programmable_transaction(programmable_transaction) ==
               expected_programmable_transaction(programmable_transaction)
    end

    test "encodes TransactionDataV1 with correct field order" do
      transaction_data_v1 = sample_transaction_data_v1()

      assert PTB.encode_transaction_data_v1(transaction_data_v1) ==
               expected_transaction_data_v1(transaction_data_v1)
    end

    test "encodes TransactionData as V1 variant 0" do
      transaction_data_v1 = sample_transaction_data_v1()

      assert PTB.encode_transaction_data(transaction_data_v1) ==
               <<0x00>> <> expected_transaction_data_v1(transaction_data_v1)
    end
  end

  defp sample_transaction_data_v1 do
    %{
      kind: %{
        inputs: [{:pure, <<1, 2, 3>>}],
        commands: [{:move_call, address(0xAA), "mod", "fun", [], [:gas_coin]}]
      },
      sender: address(0xBB),
      gas_data: %{
        payment: [sample_object_ref()],
        owner: address(0xCC),
        price: 1_000,
        budget: 50_000_000
      },
      expiration: :none
    }
  end

  defp sample_object_ref do
    {address(0x11), 7, address(0x22)}
  end

  defp address(byte) do
    :binary.copy(<<byte>>, 32)
  end

  defp expected_transaction_data_v1(%{
         kind: kind,
         sender: sender,
         gas_data: gas_data,
         expiration: expiration
       }) do
    <<0x00>> <>
      expected_programmable_transaction(kind) <>
      sender <> expected_gas_data(gas_data) <> expected_expiration(expiration)
  end

  defp expected_programmable_transaction(%{inputs: inputs, commands: commands}) do
    encode_vector(inputs, &expected_call_arg/1) <> encode_vector(commands, &expected_command/1)
  end

  defp expected_command({:move_call, package, module, function, type_arguments, arguments}) do
    <<0x00>> <> expected_move_call({package, module, function, type_arguments, arguments})
  end

  defp expected_command({:split_coins, coin, amounts}) do
    <<0x02>> <> expected_argument(coin) <> encode_vector(amounts, &expected_argument/1)
  end

  defp expected_move_call({package, module, function, type_arguments, arguments}) do
    package <>
      BCS.encode_string(module) <>
      BCS.encode_string(function) <>
      encode_vector(type_arguments, &expected_type_tag/1) <>
      encode_vector(arguments, &expected_argument/1)
  end

  defp expected_struct_tag({address, module, name, type_params}) do
    address <>
      BCS.encode_string(module) <>
      BCS.encode_string(name) <>
      encode_vector(type_params, &expected_type_tag/1)
  end

  defp expected_type_tag(:bool), do: <<0x00>>
  defp expected_type_tag(:u8), do: <<0x01>>
  defp expected_type_tag(:u64), do: <<0x02>>
  defp expected_type_tag(:u128), do: <<0x03>>
  defp expected_type_tag(:address), do: <<0x04>>
  defp expected_type_tag(:signer), do: <<0x05>>
  defp expected_type_tag({:vector, type_tag}), do: <<0x06>> <> expected_type_tag(type_tag)

  defp expected_type_tag({:struct, address, module, name, type_params}),
    do: <<0x07>> <> expected_struct_tag({address, module, name, type_params})

  defp expected_type_tag(:u16), do: <<0x08>>
  defp expected_type_tag(:u32), do: <<0x09>>
  defp expected_type_tag(:u256), do: <<0x0A>>

  defp expected_expiration(:none), do: <<0x00>>
  defp expected_expiration({:epoch, epoch}), do: <<0x01>> <> BCS.encode_u64(epoch)

  defp expected_gas_data(%{payment: payment, owner: owner, price: price, budget: budget}) do
    encode_vector(payment, &expected_object_ref/1) <>
      owner <> BCS.encode_u64(price) <> BCS.encode_u64(budget)
  end

  defp expected_call_arg({:pure, bytes}) do
    <<0x00>> <> BCS.encode_uleb128(byte_size(bytes)) <> bytes
  end

  defp expected_call_arg({:object, {:imm_or_owned, object_ref}}) do
    <<0x01, 0x00>> <> expected_object_ref(object_ref)
  end

  defp expected_call_arg({:object, {:shared, object_id, version, mutable}}) do
    <<0x01, 0x01>> <> object_id <> BCS.encode_u64(version) <> BCS.encode_bool(mutable)
  end

  defp expected_argument(:gas_coin), do: <<0x00>>
  defp expected_argument({:input, index}), do: <<0x01>> <> BCS.encode_u16(index)
  defp expected_argument({:result, index}), do: <<0x02>> <> BCS.encode_u16(index)

  defp expected_argument({:nested_result, result_index, nested_index}),
    do: <<0x03>> <> BCS.encode_u16(result_index) <> BCS.encode_u16(nested_index)

  defp expected_object_ref({object_id, version, digest}) do
    object_id <> BCS.encode_u64(version) <> BCS.encode_uleb128(byte_size(digest)) <> digest
  end

  defp encode_vector(values, encoder) do
    BCS.encode_uleb128(length(values)) <>
      (values
       |> Enum.map(encoder)
       |> IO.iodata_to_binary())
  end
end
