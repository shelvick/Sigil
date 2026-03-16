defmodule Sigil.Sui.BCSTest do
  @moduledoc """
  Exercises the planned BCS encoder and decoder API from the packet 1 spec.
  """

  use ExUnit.Case, async: true

  alias Sigil.Sui.BCS

  describe "integer encoding" do
    test "encodes unsigned integers as little-endian with correct byte width" do
      assert BCS.encode_u8(18) == <<18>>
      assert BCS.encode_u16(0x1234) == <<0x34, 0x12>>
      assert BCS.encode_u32(0x12345678) == <<0x78, 0x56, 0x34, 0x12>>

      assert BCS.encode_u64(0x0123456789ABCDEF) ==
               <<0xEF, 0xCD, 0xAB, 0x89, 0x67, 0x45, 0x23, 0x01>>

      assert BCS.encode_u128(0x0123456789ABCDEF0123456789ABCDEF) ==
               <<0xEF, 0xCD, 0xAB, 0x89, 0x67, 0x45, 0x23, 0x01, 0xEF, 0xCD, 0xAB, 0x89, 0x67,
                 0x45, 0x23, 0x01>>

      assert BCS.encode_u256(0x0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF) ==
               <<0xEF, 0xCD, 0xAB, 0x89, 0x67, 0x45, 0x23, 0x01, 0xEF, 0xCD, 0xAB, 0x89, 0x67,
                 0x45, 0x23, 0x01, 0xEF, 0xCD, 0xAB, 0x89, 0x67, 0x45, 0x23, 0x01, 0xEF, 0xCD,
                 0xAB, 0x89, 0x67, 0x45, 0x23, 0x01>>
    end

    test "encodes integer boundary values (0 and max)" do
      assert BCS.encode_u8(0) == <<0>>
      assert BCS.encode_u8(255) == <<255>>

      assert BCS.encode_u16(0) == <<0, 0>>
      assert BCS.encode_u16(65_535) == <<255, 255>>

      assert BCS.encode_u32(0) == <<0, 0, 0, 0>>
      assert BCS.encode_u32(4_294_967_295) == <<255, 255, 255, 255>>

      assert BCS.encode_u64(0) == <<0, 0, 0, 0, 0, 0, 0, 0>>

      assert BCS.encode_u64(18_446_744_073_709_551_615) ==
               <<255, 255, 255, 255, 255, 255, 255, 255>>

      assert BCS.encode_u128(0) == <<0::128>>

      assert BCS.encode_u128(340_282_366_920_938_463_463_374_607_431_768_211_455) ==
               <<255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255>>

      assert BCS.encode_u256(0) == <<0::256>>

      assert BCS.encode_u256(
               115_792_089_237_316_195_423_570_985_008_687_907_853_269_984_665_640_564_039_457_584_007_913_129_639_935
             ) ==
               <<255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
                 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255>>
    end
  end

  test "encodes ULEB128 with correct variable-length format" do
    assert BCS.encode_uleb128(0) == <<0>>
    assert BCS.encode_uleb128(127) == <<127>>
    assert BCS.encode_uleb128(128) == <<0x80, 0x01>>
    assert BCS.encode_uleb128(255) == <<0xFF, 0x01>>
    assert BCS.encode_uleb128(16_383) == <<0xFF, 0x7F>>
    assert BCS.encode_uleb128(16_384) == <<0x80, 0x80, 0x01>>
  end

  test "encodes booleans as single bytes" do
    assert BCS.encode_bool(false) == <<0>>
    assert BCS.encode_bool(true) == <<1>>
  end

  test "encodes strings with ULEB128 byte-length prefix" do
    assert BCS.encode_string("") == <<0>>
    assert BCS.encode_string("sui") == <<3, ?s, ?u, ?i>>
    assert BCS.encode_string("A☃") == <<4, 65, 0xE2, 0x98, 0x83>>
  end

  test "encodes vectors with count prefix and element encoder" do
    assert BCS.encode_vector([], &BCS.encode_u8/1) == <<0>>
    assert BCS.encode_vector([1, 2, 255], &BCS.encode_u8/1) == <<3, 1, 2, 255>>
    assert BCS.encode_vector([300, 1], &BCS.encode_u16/1) == <<2, 44, 1, 1, 0>>
  end

  test "encodes options as None (0) or Some (1 + value)" do
    assert BCS.encode_option(nil, &BCS.encode_u64/1) == <<0>>
    assert BCS.encode_option(42, &BCS.encode_u64/1) == <<1, 42, 0, 0, 0, 0, 0, 0, 0>>
  end

  test "encodes addresses as raw 32 bytes without prefix" do
    address =
      <<0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24,
        25, 26, 27, 28, 29, 30, 31>>

    assert BCS.encode_address(address) == address
  end

  test "decode reverses encode for all types (roundtrip)" do
    address =
      <<255, 254, 253, 252, 251, 250, 249, 248, 247, 246, 245, 244, 243, 242, 241, 240, 239, 238,
        237, 236, 235, 234, 233, 232, 231, 230, 229, 228, 227, 226, 225, 224>>

    assert BCS.decode_u8(BCS.encode_u8(255)) == {255, <<>>}
    assert BCS.decode_u16(BCS.encode_u16(513)) == {513, <<>>}
    assert BCS.decode_u32(BCS.encode_u32(65_537)) == {65_537, <<>>}
    assert BCS.decode_u64(BCS.encode_u64(4_294_967_297)) == {4_294_967_297, <<>>}

    assert BCS.decode_u128(BCS.encode_u128(18_446_744_073_709_551_617)) ==
             {18_446_744_073_709_551_617, <<>>}

    assert BCS.decode_u256(BCS.encode_u256(18_446_744_073_709_551_617)) ==
             {18_446_744_073_709_551_617, <<>>}

    assert BCS.decode_uleb128(BCS.encode_uleb128(16_384)) == {16_384, <<>>}
    assert BCS.decode_bool(BCS.encode_bool(true)) == {true, <<>>}
    assert BCS.decode_string(BCS.encode_string("A☃")) == {"A☃", <<>>}

    assert BCS.decode_vector(BCS.encode_vector([1, 2, 3], &BCS.encode_u16/1), &BCS.decode_u16/1) ==
             {[1, 2, 3], <<>>}

    assert BCS.decode_option(BCS.encode_option(nil, &BCS.encode_u32/1), &BCS.decode_u32/1) ==
             {nil, <<>>}

    assert BCS.decode_option(BCS.encode_option(42, &BCS.encode_u32/1), &BCS.decode_u32/1) ==
             {42, <<>>}

    assert BCS.decode_address(BCS.encode_address(address)) == {address, <<>>}
  end

  test "decode returns remaining bytes for composable parsing" do
    binary = BCS.encode_u8(7) <> BCS.encode_string("sui") <> BCS.encode_bool(false)

    assert {7, remainder_after_u8} = BCS.decode_u8(binary)
    assert {"sui", remainder_after_string} = BCS.decode_string(remainder_after_u8)
    assert remainder_after_string == <<0>>
    assert BCS.decode_bool(remainder_after_string) == {false, <<>>}
  end

  test "matches MystenLabs BCS reference test vectors" do
    for vector <- reference_vectors() do
      assert encode_reference_vector(vector) == decode_hex!(vector["expected_hex"])
    end
  end

  defp reference_vectors do
    __DIR__
    |> Path.join("../../fixtures/sui/bcs_reference_vectors.json")
    |> File.read!()
    |> Jason.decode!()
  end

  defp encode_reference_vector(%{"encoder" => "encode_bool", "value" => value}),
    do: BCS.encode_bool(value)

  defp encode_reference_vector(%{"encoder" => "encode_u16", "value" => value}),
    do: BCS.encode_u16(value)

  defp encode_reference_vector(%{"encoder" => "encode_uleb128", "value" => value}),
    do: BCS.encode_uleb128(value)

  defp encode_reference_vector(%{"encoder" => "encode_string", "value" => value}),
    do: BCS.encode_string(value)

  defp encode_reference_vector(%{"encoder" => "encode_vector_u8", "value" => value}),
    do: BCS.encode_vector(value, &BCS.encode_u8/1)

  defp decode_hex!(hex) do
    hex
    |> Base.decode16!(case: :mixed)
  end

  test "rejects out-of-range values, invalid addresses, and malformed decode input" do
    assert_raise FunctionClauseError, fn -> BCS.encode_u8(256) end
    assert_raise FunctionClauseError, fn -> BCS.encode_u16(65_536) end
    assert_raise FunctionClauseError, fn -> BCS.encode_u32(4_294_967_296) end
    assert_raise FunctionClauseError, fn -> apply(BCS, :encode_bool, [:maybe]) end
    assert_raise FunctionClauseError, fn -> BCS.encode_address(<<1, 2, 3>>) end
    assert_raise ArgumentError, fn -> BCS.encode_string(<<0xFF, 0xFE>>) end
    assert_raise FunctionClauseError, fn -> BCS.decode_u8(<<>>) end
    assert_raise FunctionClauseError, fn -> BCS.decode_u16(<<1>>) end
    assert_raise FunctionClauseError, fn -> BCS.decode_bool(<<2>>) end
    assert_raise FunctionClauseError, fn -> BCS.decode_uleb128(<<0x80>>) end
    assert_raise FunctionClauseError, fn -> BCS.decode_string(<<3, ?o, ?k>>) end
    assert_raise ArgumentError, fn -> BCS.decode_string(<<2, 0xFF, 0xFE>>) end
    assert_raise FunctionClauseError, fn -> BCS.decode_address(<<0::248>>) end
  end
end
