defmodule Sigil.Diplomacy.ObjectCodec do
  @moduledoc """
  Shared object parsing and conversion helpers for diplomacy state.
  """

  alias Sigil.Sui.TxCustodian

  @standings %{0 => :hostile, 1 => :unfriendly, 2 => :neutral, 3 => :friendly, 4 => :allied}

  @doc "Returns the shared-object version from chain JSON when present."
  @spec parse_shared_version(map()) :: non_neg_integer() | nil
  def parse_shared_version(%{"initial_shared_version" => version}) when is_integer(version),
    do: version

  def parse_shared_version(%{"shared" => %{"initialSharedVersion" => version}})
      when is_binary(version),
      do: String.to_integer(version)

  def parse_shared_version(%{"initialSharedVersion" => version}) when is_binary(version),
    do: String.to_integer(version)

  def parse_shared_version(_object), do: nil

  @doc "Extracts the tribe id from chain JSON when present."
  @spec parse_tribe_id(map()) :: non_neg_integer() | nil
  def parse_tribe_id(%{"tribe_id" => tribe_id}) when is_integer(tribe_id), do: tribe_id

  def parse_tribe_id(%{"tribe_id" => tribe_id}) when is_binary(tribe_id),
    do: String.to_integer(tribe_id)

  def parse_tribe_id(_object), do: nil

  @doc "Converts a stored standing value into the corresponding atom."
  @spec standing_to_atom(0..4) :: :hostile | :unfriendly | :neutral | :friendly | :allied
  def standing_to_atom(value) when is_map_key(@standings, value), do: @standings[value]

  @doc "Decodes a Sui object id into bytes."
  @spec hex_to_bytes(String.t()) :: binary()
  def hex_to_bytes("0x" <> hex), do: Base.decode16!(hex, case: :mixed)

  @doc "Builds a TxCustodian shared-object reference from cached custodian info."
  @spec to_custodian_ref(map()) :: TxCustodian.custodian_ref()
  def to_custodian_ref(custodian) do
    %{
      object_id: custodian.object_id_bytes,
      initial_shared_version: custodian.initial_shared_version
    }
  end

  @doc "Normalizes raw chain JSON into cached custodian info."
  @spec to_custodian_info(map() | nil) :: map() | nil
  def to_custodian_info(nil), do: nil

  def to_custodian_info(object) do
    with object_id when is_binary(object_id) <- object["id"],
         tribe_id when is_integer(tribe_id) <- parse_tribe_id(object),
         current_leader when is_binary(current_leader) <- object["current_leader"],
         version when is_integer(version) <- parse_shared_version(object) do
      %{
        object_id: object_id,
        object_id_bytes: hex_to_bytes(object_id),
        initial_shared_version: version,
        tribe_id: tribe_id,
        current_leader: current_leader
      }
    else
      _invalid -> nil
    end
  end

  @doc "Builds the shared registry reference from a page of chain objects."
  @spec build_registry_ref([map()]) :: {:ok, map()} | {:error, :no_registry_ref}
  def build_registry_ref(objects) do
    case Enum.find_value(objects, &object_to_registry_ref/1) do
      nil -> {:error, :no_registry_ref}
      registry_ref -> {:ok, registry_ref}
    end
  end

  @spec object_to_registry_ref(map()) :: map() | nil
  defp object_to_registry_ref(object) do
    with object_id when is_binary(object_id) <- object["id"],
         version when is_integer(version) <- parse_shared_version(object) do
      %{object_id: hex_to_bytes(object_id), initial_shared_version: version}
    else
      _invalid -> nil
    end
  end
end
