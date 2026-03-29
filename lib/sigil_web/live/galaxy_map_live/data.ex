defmodule SigilWeb.GalaxyMapLive.Data do
  @moduledoc """
  Data helpers for building galaxy map payloads and detail-panel state.
  """

  @doc """
  Builds detail-panel data for the selected system.
  """
  @spec build_detail_data(integer(), map()) :: map() | nil
  def build_detail_data(system_id, assigns) do
    case Map.get(assigns.system_names, system_id) do
      nil ->
        nil

      system_name ->
        locations = Enum.filter(assigns.tribe_location_overlays, &(&1.system_id == system_id))
        scouting = Enum.filter(assigns.tribe_scouting_overlays, &(&1.system_id == system_id))
        marketplace = Enum.filter(assigns.marketplace_overlays, &(&1.system_id == system_id))

        constellation_name =
          assigns.system_constellations
          |> Map.get(system_id)
          |> then(&Map.get(assigns.constellation_names, &1, "Unknown"))

        assemblies =
          Enum.map(locations, fn %{assembly_id: assembly_id, label: label} ->
            %{id: assembly_id, label: label}
          end)

        %{
          system_name: system_name,
          constellation_name: constellation_name,
          tribe_location_count: length(locations),
          tribe_scouting_count: length(scouting),
          marketplace_count: length(marketplace),
          assemblies: assemblies
        }
    end
  end

  @doc """
  Maps StaticData systems to compact payload entries for the hook.
  """
  @spec map_system_payload([map()]) :: [map()]
  def map_system_payload(systems) do
    Enum.map(systems, fn system ->
      %{
        id: system.id,
        name: system.name,
        constellation_id: system.constellation_id,
        x: system.x,
        y: system.y,
        z: system.z
      }
    end)
  end

  @doc """
  Maps StaticData constellations to compact payload entries for the hook.
  """
  @spec map_constellation_payload([map()]) :: [map()]
  def map_constellation_payload(constellations) do
    Enum.map(constellations, fn constellation ->
      %{
        id: constellation.id,
        name: constellation.name,
        x: constellation.x,
        y: constellation.y,
        z: constellation.z
      }
    end)
  end
end
