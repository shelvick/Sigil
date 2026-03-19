defmodule Sigil.Sui.TxGateExtension do
  @moduledoc """
  Builds programmable transaction options for gate extension authorization.
  """

  alias Sigil.Sui.TransactionBuilder
  alias Sigil.Sui.TransactionBuilder.PTB

  @typedoc "Shared object reference for gate or character."
  @type shared_ref() :: %{
          object_id: PTB.bytes32(),
          initial_shared_version: non_neg_integer()
        }

  @typedoc "On-chain object reference for receiving objects such as OwnerCap."
  @type object_ref() :: PTB.object_ref()

  @doc "Builds transaction kind options for `character::borrow_owner_cap` gate extension auth flow."
  @spec build_authorize_extension(shared_ref(), object_ref(), shared_ref()) ::
          TransactionBuilder.kind_opts()
  def build_authorize_extension(
        %{object_id: <<_::binary-size(32)>>, initial_shared_version: gate_version} = gate_ref,
        {<<_::binary-size(32)>>, owner_cap_version, <<_::binary-size(32)>>} = owner_cap_ref,
        %{object_id: <<_::binary-size(32)>>, initial_shared_version: character_version} =
          character_ref
      )
      when is_integer(gate_version) and gate_version >= 0 and is_integer(owner_cap_version) and
             owner_cap_version >= 0 and is_integer(character_version) and character_version >= 0 do
    [
      inputs: [
        shared_input(character_ref),
        receiving_input(owner_cap_ref),
        shared_input(gate_ref)
      ],
      commands: [
        move_call(
          world_package_id_bytes(),
          "character",
          "borrow_owner_cap",
          [gate_type()],
          [{:input, 0}, {:input, 1}]
        ),
        move_call(
          world_package_id_bytes(),
          "gate",
          "authorize_extension",
          [frontier_gate_auth_type()],
          [{:input, 2}, {:nested_result, 0, 0}]
        ),
        move_call(
          world_package_id_bytes(),
          "character",
          "return_owner_cap",
          [gate_type()],
          [{:input, 0}, {:nested_result, 0, 0}, {:nested_result, 0, 1}]
        )
      ]
    ]
  end

  defp move_call(package, module, function, type_arguments, arguments) do
    {:move_call, package, module, function, type_arguments, arguments}
  end

  @spec shared_input(shared_ref()) :: PTB.call_arg()
  defp shared_input(%{
         object_id: <<_::binary-size(32)>> = object_id,
         initial_shared_version: version
       })
       when is_integer(version) and version >= 0 do
    {:object, {:shared, object_id, version, true}}
  end

  @spec receiving_input(object_ref()) :: PTB.call_arg()
  defp receiving_input(
         {<<_::binary-size(32)>> = object_id, version, <<_::binary-size(32)>> = digest}
       )
       when is_integer(version) and version >= 0 do
    {:object, {:receiving, {object_id, version, digest}}}
  end

  @spec gate_type() :: PTB.type_tag()
  defp gate_type do
    {:struct, world_package_id_bytes(), "gate", "Gate", []}
  end

  @spec frontier_gate_auth_type() :: PTB.type_tag()
  defp frontier_gate_auth_type do
    {:struct, sigil_package_id_bytes(), "frontier_gate", "FrontierGateAuth", []}
  end

  @spec world_package_id_bytes() :: PTB.bytes32()
  defp world_package_id_bytes do
    package_id_bytes(world_package_id())
  end

  @spec world_package_id() :: String.t()
  defp world_package_id do
    world = Application.fetch_env!(:sigil, :eve_world)
    worlds = Application.fetch_env!(:sigil, :eve_worlds)
    %{package_id: id} = Map.fetch!(worlds, world)
    id
  end

  @spec sigil_package_id_bytes() :: PTB.bytes32()
  defp sigil_package_id_bytes do
    package_id_bytes(sigil_package_id())
  end

  @spec sigil_package_id() :: String.t()
  defp sigil_package_id do
    world = Application.fetch_env!(:sigil, :eve_world)
    worlds = Application.fetch_env!(:sigil, :eve_worlds)
    %{sigil_package_id: id} = Map.fetch!(worlds, world)
    id
  end

  @spec package_id_bytes(String.t()) :: PTB.bytes32()
  defp package_id_bytes("0x" <> hex) do
    Base.decode16!(hex, case: :mixed)
  end
end
