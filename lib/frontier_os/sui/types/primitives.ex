defmodule FrontierOS.Sui.Types.TenantItemId do
  @moduledoc """
  Tenant-scoped item identifier.
  """

  alias FrontierOS.Sui.Types.Parser

  @enforce_keys [:item_id, :tenant]
  defstruct [:item_id, :tenant]

  @type t :: %__MODULE__{
          item_id: non_neg_integer(),
          tenant: String.t()
        }

  @doc "Builds a tenant item id struct from GraphQL JSON."
  @spec from_json(map()) :: t()
  def from_json(json) when is_map(json) do
    %__MODULE__{
      item_id: json |> Map.fetch!("item_id") |> Parser.integer!(),
      tenant: Map.fetch!(json, "tenant")
    }
  end
end

defmodule FrontierOS.Sui.Types.AssemblyStatus do
  @moduledoc """
  Assembly status enum wrapper.
  """

  alias FrontierOS.Sui.Types.Parser

  @enforce_keys [:status]
  defstruct [:status]

  @type t :: %__MODULE__{
          status: :null | :offline | :online
        }

  @doc "Builds an assembly status struct from GraphQL JSON."
  @spec from_json(map()) :: t()
  def from_json(json) when is_map(json) do
    %__MODULE__{status: json |> Map.fetch!("status") |> Parser.status!()}
  end
end

defmodule FrontierOS.Sui.Types.Location do
  @moduledoc """
  A hashed location in the Sui world.
  """

  alias FrontierOS.Sui.Types.Parser

  @enforce_keys [:location_hash]
  defstruct [:location_hash]

  @type t :: %__MODULE__{location_hash: binary()}

  @doc "Builds a location struct from GraphQL JSON."
  @spec from_json(map()) :: t()
  def from_json(json) when is_map(json) do
    hash = json |> Map.fetch!("location_hash") |> Parser.bytes!()

    unless byte_size(hash) == 32 do
      raise ArgumentError, "location_hash must be 32 bytes, got: #{byte_size(hash)}"
    end

    %__MODULE__{location_hash: hash}
  end
end

defmodule FrontierOS.Sui.Types.Metadata do
  @moduledoc """
  Common metadata fields shared by Sui objects.
  """

  @enforce_keys [:assembly_id, :name, :description, :url]
  defstruct [:assembly_id, :name, :description, :url]

  @type t :: %__MODULE__{
          assembly_id: String.t(),
          name: String.t(),
          description: String.t(),
          url: String.t()
        }

  @doc "Builds a metadata struct from GraphQL JSON."
  @spec from_json(map()) :: t()
  def from_json(json) when is_map(json) do
    %__MODULE__{
      assembly_id: Map.fetch!(json, "assembly_id"),
      name: Map.fetch!(json, "name"),
      description: Map.fetch!(json, "description"),
      url: Map.fetch!(json, "url")
    }
  end
end

defmodule FrontierOS.Sui.Types.Fuel do
  @moduledoc """
  Fuel state for a network node.
  """

  alias FrontierOS.Sui.Types.Parser

  @enforce_keys [
    :max_capacity,
    :burn_rate_in_ms,
    :type_id,
    :unit_volume,
    :quantity,
    :is_burning,
    :previous_cycle_elapsed_time,
    :burn_start_time,
    :last_updated
  ]
  defstruct [
    :max_capacity,
    :burn_rate_in_ms,
    :type_id,
    :unit_volume,
    :quantity,
    :is_burning,
    :previous_cycle_elapsed_time,
    :burn_start_time,
    :last_updated
  ]

  @type t :: %__MODULE__{
          max_capacity: non_neg_integer(),
          burn_rate_in_ms: non_neg_integer(),
          type_id: non_neg_integer() | nil,
          unit_volume: non_neg_integer() | nil,
          quantity: non_neg_integer(),
          is_burning: boolean(),
          previous_cycle_elapsed_time: non_neg_integer(),
          burn_start_time: non_neg_integer(),
          last_updated: non_neg_integer()
        }

  @doc "Builds a fuel struct from GraphQL JSON."
  @spec from_json(map()) :: t()
  def from_json(json) when is_map(json) do
    %__MODULE__{
      max_capacity: json |> Map.fetch!("max_capacity") |> Parser.integer!(),
      burn_rate_in_ms: json |> Map.fetch!("burn_rate_in_ms") |> Parser.integer!(),
      type_id: json |> Map.get("type_id") |> Parser.optional(&Parser.integer!/1),
      unit_volume: json |> Map.get("unit_volume") |> Parser.optional(&Parser.integer!/1),
      quantity: json |> Map.fetch!("quantity") |> Parser.integer!(),
      is_burning: Map.fetch!(json, "is_burning"),
      previous_cycle_elapsed_time:
        json |> Map.fetch!("previous_cycle_elapsed_time") |> Parser.integer!(),
      burn_start_time: json |> Map.fetch!("burn_start_time") |> Parser.integer!(),
      last_updated: json |> Map.fetch!("last_updated") |> Parser.integer!()
    }
  end
end

defmodule FrontierOS.Sui.Types.EnergySource do
  @moduledoc """
  Energy production values for an energy source.
  """

  alias FrontierOS.Sui.Types.Parser

  @enforce_keys [:max_energy_production, :current_energy_production, :total_reserved_energy]
  defstruct [:max_energy_production, :current_energy_production, :total_reserved_energy]

  @type t :: %__MODULE__{
          max_energy_production: non_neg_integer(),
          current_energy_production: non_neg_integer(),
          total_reserved_energy: non_neg_integer()
        }

  @doc "Builds an energy source struct from GraphQL JSON."
  @spec from_json(map()) :: t()
  def from_json(json) when is_map(json) do
    %__MODULE__{
      max_energy_production: json |> Map.fetch!("max_energy_production") |> Parser.integer!(),
      current_energy_production:
        json |> Map.fetch!("current_energy_production") |> Parser.integer!(),
      total_reserved_energy: json |> Map.fetch!("total_reserved_energy") |> Parser.integer!()
    }
  end
end
