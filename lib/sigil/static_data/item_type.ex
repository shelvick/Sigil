defmodule Sigil.StaticData.ItemType do
  @moduledoc """
  Typed World API item type data.
  """

  @enforce_keys [
    :id,
    :name,
    :description,
    :mass,
    :radius,
    :volume,
    :portion_size,
    :group_name,
    :group_id,
    :category_name,
    :category_id,
    :icon_url
  ]
  defstruct [
    :id,
    :name,
    :description,
    :mass,
    :radius,
    :volume,
    :portion_size,
    :group_name,
    :group_id,
    :category_name,
    :category_id,
    :icon_url
  ]

  @type t :: %__MODULE__{
          id: integer(),
          name: String.t(),
          description: String.t(),
          mass: float(),
          radius: float(),
          volume: float(),
          portion_size: integer(),
          group_name: String.t(),
          group_id: integer(),
          category_name: String.t(),
          category_id: integer(),
          icon_url: String.t()
        }

  @doc "Builds an item type struct from World API JSON."
  @spec from_json(map()) :: t()
  def from_json(json) when is_map(json) do
    %__MODULE__{
      id: Map.fetch!(json, "id"),
      name: Map.fetch!(json, "name"),
      description: Map.fetch!(json, "description"),
      mass: Map.fetch!(json, "mass"),
      radius: Map.fetch!(json, "radius"),
      volume: Map.fetch!(json, "volume"),
      portion_size: Map.fetch!(json, "portionSize"),
      group_name: Map.fetch!(json, "groupName"),
      group_id: Map.fetch!(json, "groupId"),
      category_name: Map.fetch!(json, "categoryName"),
      category_id: Map.fetch!(json, "categoryId"),
      icon_url: Map.fetch!(json, "iconUrl")
    }
  end
end
