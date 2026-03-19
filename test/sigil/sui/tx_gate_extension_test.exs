defmodule Sigil.Sui.TxGateExtensionTest do
  @moduledoc """
  Defines packet 1 transaction builder tests for gate extension PTB construction.
  """

  use ExUnit.Case, async: true

  alias Sigil.Sui.TransactionBuilder
  alias Sigil.Sui.TxGateExtension

  @sigil_package_id Base.decode16!(
                      "06CE9D6BED77615383575CC7EBA4883D32769B30CD5DF00561E38434A59611A1",
                      case: :mixed
                    )

  describe "build_authorize_extension/3" do
    test "returns 3 inputs and 3 commands" do
      build_opts =
        TxGateExtension.build_authorize_extension(
          sample_gate_ref(),
          sample_owner_cap_ref(),
          sample_character_ref()
        )

      assert length(build_opts[:inputs]) == 3
      assert length(build_opts[:commands]) == 3
    end

    test "command 0 calls character::borrow_owner_cap<Gate>" do
      build_opts =
        TxGateExtension.build_authorize_extension(
          sample_gate_ref(),
          sample_owner_cap_ref(),
          sample_character_ref()
        )

      assert [
               {:move_call, world_package_id, "character", "borrow_owner_cap", [gate_type],
                [{:input, 0}, {:input, 1}]},
               _,
               _
             ] = build_opts[:commands]

      assert gate_type == {:struct, world_package_id, "gate", "Gate", []}
      refute world_package_id == @sigil_package_id
      assert byte_size(world_package_id) == 32
    end

    test "command 1 calls gate::authorize_extension<FrontierGateAuth>" do
      build_opts =
        TxGateExtension.build_authorize_extension(
          sample_gate_ref(),
          sample_owner_cap_ref(),
          sample_character_ref()
        )

      assert [
               _,
               {:move_call, world_package_id, "gate", "authorize_extension",
                [{:struct, @sigil_package_id, "frontier_gate", "FrontierGateAuth", []}],
                [{:input, 2}, {:nested_result, 0, 0}]},
               _
             ] = build_opts[:commands]

      refute world_package_id == @sigil_package_id
      assert byte_size(world_package_id) == 32
    end

    test "command 2 calls character::return_owner_cap<Gate>" do
      build_opts =
        TxGateExtension.build_authorize_extension(
          sample_gate_ref(),
          sample_owner_cap_ref(),
          sample_character_ref()
        )

      assert [
               _,
               _,
               {:move_call, world_package_id, "character", "return_owner_cap", [gate_type],
                [{:input, 0}, {:nested_result, 0, 0}, {:nested_result, 0, 1}]}
             ] = build_opts[:commands]

      assert gate_type == {:struct, world_package_id, "gate", "Gate", []}
      refute world_package_id == @sigil_package_id
      assert byte_size(world_package_id) == 32
    end

    test "input 0 is character shared mutable object" do
      build_opts =
        TxGateExtension.build_authorize_extension(
          sample_gate_ref(),
          sample_owner_cap_ref(),
          sample_character_ref()
        )

      assert [
               {:object, {:shared, character_id, 7, true}},
               _,
               _
             ] = build_opts[:inputs]

      assert character_id == object_id(0x33)
    end

    test "input 1 is owner_cap receiving object" do
      build_opts =
        TxGateExtension.build_authorize_extension(
          sample_gate_ref(),
          sample_owner_cap_ref(),
          sample_character_ref()
        )

      assert [
               _,
               {:object, {:receiving, {owner_cap_id, 11, owner_cap_digest}}},
               _
             ] = build_opts[:inputs]

      assert owner_cap_id == object_id(0x22)
      assert owner_cap_digest == object_id(0x44)
    end

    test "input 2 is gate shared mutable object" do
      build_opts =
        TxGateExtension.build_authorize_extension(
          sample_gate_ref(),
          sample_owner_cap_ref(),
          sample_character_ref()
        )

      assert [
               _,
               _,
               {:object, {:shared, gate_id, 9, true}}
             ] = build_opts[:inputs]

      assert gate_id == object_id(0x11)
    end

    test "borrow and return commands use world package ID" do
      build_opts =
        TxGateExtension.build_authorize_extension(
          sample_gate_ref(),
          sample_owner_cap_ref(),
          sample_character_ref()
        )

      assert [
               {:move_call, borrow_package_id, "character", "borrow_owner_cap", _, _},
               _,
               {:move_call, return_package_id, "character", "return_owner_cap", _, _}
             ] = build_opts[:commands]

      assert borrow_package_id == return_package_id
      refute borrow_package_id == @sigil_package_id
    end

    test "authorize_extension uses sigil package ID for FrontierGateAuth" do
      build_opts =
        TxGateExtension.build_authorize_extension(
          sample_gate_ref(),
          sample_owner_cap_ref(),
          sample_character_ref()
        )

      assert [
               _,
               {:move_call, _, "gate", "authorize_extension",
                [
                  {:struct, frontier_gate_auth_package_id, "frontier_gate", "FrontierGateAuth",
                   []}
                ], _},
               _
             ] = build_opts[:commands]

      assert frontier_gate_auth_package_id == @sigil_package_id
    end
  end

  describe "TransactionBuilder integration" do
    test "PTB encodes to valid BCS via build_kind!" do
      encoded_kind =
        sample_gate_ref()
        |> TxGateExtension.build_authorize_extension(
          sample_owner_cap_ref(),
          sample_character_ref()
        )
        |> TransactionBuilder.build_kind!()

      assert is_binary(encoded_kind)
      assert byte_size(encoded_kind) > 0
    end
  end

  defp sample_gate_ref do
    %{object_id: object_id(0x11), initial_shared_version: 9}
  end

  defp sample_owner_cap_ref do
    {object_id(0x22), 11, object_id(0x44)}
  end

  defp sample_character_ref do
    %{object_id: object_id(0x33), initial_shared_version: 7}
  end

  defp object_id(byte) do
    :binary.copy(<<byte>>, 32)
  end
end
