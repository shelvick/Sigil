defmodule Sigil.StaticData.Constellation do
  @moduledoc """
  Typed World API constellation data.
  """

  @enforce_keys [:id, :name, :region_id, :x, :y, :z]
  defstruct [:id, :name, :region_id, :x, :y, :z]

  @type t :: %__MODULE__{
          id: integer(),
          name: String.t(),
          region_id: integer(),
          x: integer(),
          y: integer(),
          z: integer()
        }

  @doc "Builds a constellation struct from World API JSON."
  @spec from_json(map()) :: t()
  def from_json(json) when is_map(json) do
    location = Map.fetch!(json, "location")

    %__MODULE__{
      id: Map.fetch!(json, "id"),
      name: Map.fetch!(json, "name"),
      region_id: Map.fetch!(json, "regionId"),
      x: Map.fetch!(location, "x"),
      y: Map.fetch!(location, "y"),
      z: Map.fetch!(location, "z")
    }
  end
end
