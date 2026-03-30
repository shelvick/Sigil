defmodule SigilWeb.GalaxyMapLive.Data do
  @moduledoc """
  Data helpers for building galaxy map payloads and detail-panel state.
  """

  alias Sigil.{Assemblies, GameState.FuelAnalytics}
  alias Sigil.Sui.Types.NetworkNode

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

  @doc """
  Builds per-system category values for map point color coding.
  """
  @spec build_system_categories(map()) :: %{optional(String.t()) => String.t()}
  def build_system_categories(assigns) do
    system_names = Map.get(assigns, :system_names, %{})
    now = DateTime.utc_now()

    assembly_categories =
      assigns
      |> Map.get(:tribe_location_overlays, [])
      |> Enum.reduce(%{}, fn entry, acc ->
        put_assembly_category(acc, entry, assigns, system_names, now)
      end)

    intel_categories =
      (Map.get(assigns, :tribe_scouting_overlays, []) ++
         Map.get(assigns, :marketplace_overlays, []))
      |> Enum.reduce(%{}, fn entry, acc -> put_intel_category(acc, entry, system_names) end)

    assembly_categories
    |> Map.merge(intel_categories, fn
      _system_id, :fuel_critical, :intel -> :fuel_critical
      _system_id, :fuel_low, :intel -> :fuel_low
      _system_id, :assembly, :intel -> :both
      _system_id, category, _intel -> category
    end)
    |> Map.new(fn {system_id, category} ->
      {Integer.to_string(system_id), Atom.to_string(category)}
    end)
  end

  @spec put_assembly_category(map(), map(), map(), map(), DateTime.t()) :: map()
  defp put_assembly_category(
         acc,
         %{system_id: system_id, assembly_id: assembly_id},
         assigns,
         system_names,
         now
       )
       when is_integer(system_id) and is_binary(assembly_id) do
    if Map.has_key?(system_names, system_id) do
      merge_category(acc, system_id, assembly_category(assigns, assembly_id, now))
    else
      acc
    end
  end

  defp put_assembly_category(acc, _entry, _assigns, _system_names, _now), do: acc

  @spec put_intel_category(map(), map(), map()) :: map()
  defp put_intel_category(acc, %{system_id: system_id}, system_names)
       when is_integer(system_id) do
    if Map.has_key?(system_names, system_id) do
      Map.put(acc, system_id, :intel)
    else
      acc
    end
  end

  defp put_intel_category(acc, _entry, _system_names), do: acc

  @spec merge_category(map(), integer(), atom()) :: map()
  defp merge_category(categories, system_id, category) do
    current = Map.get(categories, system_id, :default)

    chosen =
      if category_rank(category) >= category_rank(current) do
        category
      else
        current
      end

    Map.put(categories, system_id, chosen)
  end

  @spec category_rank(atom()) :: integer()
  defp category_rank(:fuel_critical), do: 3
  defp category_rank(:fuel_low), do: 2
  defp category_rank(:assembly), do: 1
  defp category_rank(_other), do: 0

  @spec assembly_category(map(), String.t(), DateTime.t()) :: atom()
  defp assembly_category(assigns, assembly_id, now) do
    with %{assemblies: _table_id} = tables <- Map.get(assigns, :cache_tables),
         {:ok, assembly} <- Assemblies.get_assembly(assembly_id, tables: tables) do
      category_from_assembly(assembly, now)
    else
      _other -> :assembly
    end
  end

  @spec category_from_assembly(term(), DateTime.t()) :: atom()
  defp category_from_assembly(%NetworkNode{fuel: fuel}, now), do: fuel_category(fuel, now)
  defp category_from_assembly(_assembly, _now), do: :assembly

  @spec fuel_category(map(), DateTime.t()) :: atom()
  defp fuel_category(%{quantity: quantity, max_capacity: max_capacity} = fuel, now)
       when is_integer(quantity) and is_integer(max_capacity) and max_capacity > 0 do
    ratio = quantity / max_capacity

    case FuelAnalytics.compute_depletion(fuel) do
      {:depletes_at, depletes_at} ->
        minutes_remaining = DateTime.diff(depletes_at, now, :minute)
        fuel_category_from_state(minutes_remaining, ratio)

      _other ->
        fuel_category_from_ratio(ratio)
    end
  end

  defp fuel_category(_fuel, _now), do: :assembly

  @spec fuel_category_from_state(integer(), float()) :: atom()
  defp fuel_category_from_state(minutes_remaining, _ratio)
       when minutes_remaining > 0 and minutes_remaining < 120,
       do: :fuel_critical

  defp fuel_category_from_state(_minutes_remaining, ratio), do: fuel_category_from_ratio(ratio)

  @spec fuel_category_from_ratio(float()) :: atom()
  defp fuel_category_from_ratio(ratio) when ratio < 0.20, do: :fuel_low
  defp fuel_category_from_ratio(_ratio), do: :assembly
end
