defmodule Sigil.Sui.Types.Gate do
  @moduledoc """
  A jump gate object.
  """

  alias Sigil.Sui.Types.{AssemblyStatus, Location, Metadata, Parser, TenantItemId}

  @enforce_keys [
    :id,
    :key,
    :owner_cap_id,
    :type_id,
    :linked_gate_id,
    :status,
    :location,
    :energy_source_id,
    :metadata,
    :extension
  ]
  defstruct [
    :id,
    :key,
    :owner_cap_id,
    :type_id,
    :linked_gate_id,
    :status,
    :location,
    :energy_source_id,
    :metadata,
    :extension
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          key: TenantItemId.t(),
          owner_cap_id: String.t(),
          type_id: non_neg_integer(),
          linked_gate_id: String.t() | nil,
          status: AssemblyStatus.t(),
          location: Location.t(),
          energy_source_id: String.t() | nil,
          metadata: Metadata.t() | nil,
          extension: String.t() | nil
        }

  @doc "Builds a gate struct from GraphQL JSON."
  @spec from_json(map()) :: t()
  def from_json(json) when is_map(json) do
    %__MODULE__{
      id: json |> Map.fetch!("id") |> Parser.uid!(),
      key: json |> Map.fetch!("key") |> TenantItemId.from_json(),
      owner_cap_id: json |> Map.fetch!("owner_cap_id") |> Parser.uid!(),
      type_id: json |> Map.fetch!("type_id") |> Parser.integer!(),
      linked_gate_id: Map.get(json, "linked_gate_id"),
      status: json |> Map.fetch!("status") |> AssemblyStatus.from_json(),
      location: json |> Map.fetch!("location") |> Location.from_json(),
      energy_source_id: Map.get(json, "energy_source_id"),
      metadata: json |> Map.get("metadata") |> Parser.optional(&Metadata.from_json/1),
      extension: json |> Map.get("extension") |> parse_extension()
    }
  end

  @spec parse_extension(term()) :: String.t() | nil
  defp parse_extension(%{"name" => name}) when is_binary(name), do: name
  defp parse_extension(value) when is_binary(value), do: value
  defp parse_extension(_other), do: nil
end

defmodule Sigil.Sui.Types.Assembly do
  @moduledoc """
  An assembly object.
  """

  alias Sigil.Sui.Types.{AssemblyStatus, Location, Metadata, Parser, TenantItemId}

  @enforce_keys [
    :id,
    :key,
    :owner_cap_id,
    :type_id,
    :status,
    :location,
    :energy_source_id,
    :metadata
  ]
  defstruct [:id, :key, :owner_cap_id, :type_id, :status, :location, :energy_source_id, :metadata]

  @type t :: %__MODULE__{
          id: String.t(),
          key: TenantItemId.t(),
          owner_cap_id: String.t(),
          type_id: non_neg_integer(),
          status: AssemblyStatus.t(),
          location: Location.t(),
          energy_source_id: String.t() | nil,
          metadata: Metadata.t() | nil
        }

  @doc "Builds an assembly struct from GraphQL JSON."
  @spec from_json(map()) :: t()
  def from_json(json) when is_map(json) do
    %__MODULE__{
      id: json |> Map.fetch!("id") |> Parser.uid!(),
      key: json |> Map.fetch!("key") |> TenantItemId.from_json(),
      owner_cap_id: json |> Map.fetch!("owner_cap_id") |> Parser.uid!(),
      type_id: json |> Map.fetch!("type_id") |> Parser.integer!(),
      status: json |> Map.fetch!("status") |> AssemblyStatus.from_json(),
      location: json |> Map.fetch!("location") |> Location.from_json(),
      energy_source_id: Map.get(json, "energy_source_id"),
      metadata: json |> Map.get("metadata") |> Parser.optional(&Metadata.from_json/1)
    }
  end
end

defmodule Sigil.Sui.Types.NetworkNode do
  @moduledoc """
  A network node object.
  """

  alias Sigil.Sui.Types.{
    AssemblyStatus,
    EnergySource,
    Fuel,
    Location,
    Metadata,
    Parser,
    TenantItemId
  }

  @enforce_keys [
    :id,
    :key,
    :owner_cap_id,
    :type_id,
    :status,
    :location,
    :fuel,
    :energy_source,
    :metadata,
    :connected_assembly_ids
  ]
  defstruct [
    :id,
    :key,
    :owner_cap_id,
    :type_id,
    :status,
    :location,
    :fuel,
    :energy_source,
    :metadata,
    :connected_assembly_ids
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          key: TenantItemId.t(),
          owner_cap_id: String.t(),
          type_id: non_neg_integer(),
          status: AssemblyStatus.t(),
          location: Location.t(),
          fuel: Fuel.t(),
          energy_source: EnergySource.t(),
          metadata: Metadata.t() | nil,
          connected_assembly_ids: [String.t()]
        }

  @doc "Builds a network node struct from GraphQL JSON."
  @spec from_json(map()) :: t()
  def from_json(json) when is_map(json) do
    %__MODULE__{
      id: json |> Map.fetch!("id") |> Parser.uid!(),
      key: json |> Map.fetch!("key") |> TenantItemId.from_json(),
      owner_cap_id: json |> Map.fetch!("owner_cap_id") |> Parser.uid!(),
      type_id: json |> Map.fetch!("type_id") |> Parser.integer!(),
      status: json |> Map.fetch!("status") |> AssemblyStatus.from_json(),
      location: json |> Map.fetch!("location") |> Location.from_json(),
      fuel: json |> Map.fetch!("fuel") |> Fuel.from_json(),
      energy_source: json |> Map.fetch!("energy_source") |> EnergySource.from_json(),
      metadata: json |> Map.get("metadata") |> Parser.optional(&Metadata.from_json/1),
      connected_assembly_ids: Map.fetch!(json, "connected_assembly_ids")
    }
  end
end

defmodule Sigil.Sui.Types.Character do
  @moduledoc """
  A character object.
  """

  alias Sigil.Sui.Types.{Metadata, Parser, TenantItemId}

  @enforce_keys [:id, :key, :tribe_id, :character_address, :metadata, :owner_cap_id]
  defstruct [:id, :key, :tribe_id, :character_address, :metadata, :owner_cap_id]

  @type t :: %__MODULE__{
          id: String.t(),
          key: TenantItemId.t(),
          tribe_id: non_neg_integer(),
          character_address: String.t(),
          metadata: Metadata.t() | nil,
          owner_cap_id: String.t()
        }

  @doc "Builds a character struct from GraphQL JSON."
  @spec from_json(map()) :: t()
  def from_json(json) when is_map(json) do
    %__MODULE__{
      id: json |> Map.fetch!("id") |> Parser.uid!(),
      key: json |> Map.fetch!("key") |> TenantItemId.from_json(),
      tribe_id: json |> Map.fetch!("tribe_id") |> Parser.integer!(),
      character_address: Map.fetch!(json, "character_address"),
      metadata: json |> Map.get("metadata") |> Parser.optional(&Metadata.from_json/1),
      owner_cap_id: json |> Map.fetch!("owner_cap_id") |> Parser.uid!()
    }
  end
end

defmodule Sigil.Sui.Types.Turret do
  @moduledoc """
  A turret object.
  """

  alias Sigil.Sui.Types.{AssemblyStatus, Location, Metadata, Parser, TenantItemId}

  @enforce_keys [
    :id,
    :key,
    :owner_cap_id,
    :type_id,
    :status,
    :location,
    :energy_source_id,
    :metadata,
    :extension
  ]
  defstruct [
    :id,
    :key,
    :owner_cap_id,
    :type_id,
    :status,
    :location,
    :energy_source_id,
    :metadata,
    :extension
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          key: TenantItemId.t(),
          owner_cap_id: String.t(),
          type_id: non_neg_integer(),
          status: AssemblyStatus.t(),
          location: Location.t(),
          energy_source_id: String.t() | nil,
          metadata: Metadata.t() | nil,
          extension: String.t() | nil
        }

  @doc "Builds a turret struct from GraphQL JSON."
  @spec from_json(map()) :: t()
  def from_json(json) when is_map(json) do
    %__MODULE__{
      id: json |> Map.fetch!("id") |> Parser.uid!(),
      key: json |> Map.fetch!("key") |> TenantItemId.from_json(),
      owner_cap_id: json |> Map.fetch!("owner_cap_id") |> Parser.uid!(),
      type_id: json |> Map.fetch!("type_id") |> Parser.integer!(),
      status: json |> Map.fetch!("status") |> AssemblyStatus.from_json(),
      location: json |> Map.fetch!("location") |> Location.from_json(),
      energy_source_id: Map.get(json, "energy_source_id"),
      metadata: json |> Map.get("metadata") |> Parser.optional(&Metadata.from_json/1),
      extension: json |> Map.get("extension") |> parse_extension()
    }
  end

  @spec parse_extension(term()) :: String.t() | nil
  defp parse_extension(%{"name" => name}) when is_binary(name), do: name
  defp parse_extension(value) when is_binary(value), do: value
  defp parse_extension(_other), do: nil
end

defmodule Sigil.Sui.Types.StorageUnit do
  @moduledoc """
  A storage unit object.
  """

  alias Sigil.Sui.Types.{AssemblyStatus, Location, Metadata, Parser, TenantItemId}

  @enforce_keys [
    :id,
    :key,
    :owner_cap_id,
    :type_id,
    :status,
    :location,
    :inventory_keys,
    :energy_source_id,
    :metadata,
    :extension
  ]
  defstruct [
    :id,
    :key,
    :owner_cap_id,
    :type_id,
    :status,
    :location,
    :inventory_keys,
    :energy_source_id,
    :metadata,
    :extension
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          key: TenantItemId.t(),
          owner_cap_id: String.t(),
          type_id: non_neg_integer(),
          status: AssemblyStatus.t(),
          location: Location.t(),
          inventory_keys: [String.t()],
          energy_source_id: String.t() | nil,
          metadata: Metadata.t() | nil,
          extension: String.t() | nil
        }

  @doc "Builds a storage unit struct from GraphQL JSON."
  @spec from_json(map()) :: t()
  def from_json(json) when is_map(json) do
    %__MODULE__{
      id: json |> Map.fetch!("id") |> Parser.uid!(),
      key: json |> Map.fetch!("key") |> TenantItemId.from_json(),
      owner_cap_id: json |> Map.fetch!("owner_cap_id") |> Parser.uid!(),
      type_id: json |> Map.fetch!("type_id") |> Parser.integer!(),
      status: json |> Map.fetch!("status") |> AssemblyStatus.from_json(),
      location: json |> Map.fetch!("location") |> Location.from_json(),
      inventory_keys: Map.fetch!(json, "inventory_keys"),
      energy_source_id: Map.get(json, "energy_source_id"),
      metadata: json |> Map.get("metadata") |> Parser.optional(&Metadata.from_json/1),
      extension: json |> Map.get("extension") |> parse_extension()
    }
  end

  @spec parse_extension(term()) :: String.t() | nil
  defp parse_extension(%{"name" => name}) when is_binary(name), do: name
  defp parse_extension(value) when is_binary(value), do: value
  defp parse_extension(_other), do: nil
end
