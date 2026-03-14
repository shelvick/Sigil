defmodule FrontierOS.StaticData.SolarSystem do
  @moduledoc """
  Typed World API solar system data.
  """

  @enforce_keys [:id, :name, :constellation_id, :region_id, :x, :y, :z]
  defstruct [:id, :name, :constellation_id, :region_id, :x, :y, :z]

  @type t :: %__MODULE__{
          id: integer(),
          name: String.t(),
          constellation_id: integer(),
          region_id: integer(),
          x: integer(),
          y: integer(),
          z: integer()
        }

  @doc "Builds a solar system struct from World API JSON."
  @spec from_json(map()) :: t()
  def from_json(json) when is_map(json) do
    location = Map.fetch!(json, "location")

    %__MODULE__{
      id: Map.fetch!(json, "id"),
      name: Map.fetch!(json, "name"),
      constellation_id: Map.fetch!(json, "constellationId"),
      region_id: Map.fetch!(json, "regionId"),
      x: Map.fetch!(location, "x"),
      y: Map.fetch!(location, "y"),
      z: Map.fetch!(location, "z")
    }
  end
end
