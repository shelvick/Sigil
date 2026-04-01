defmodule SigilWeb.AssemblyDetailLive.IntelHelpers do
  @moduledoc """
  Shared intel-related helpers for the assembly detail LiveView.
  """

  alias Sigil.Intel
  alias Sigil.Intel.IntelReport
  alias Sigil.StaticData
  alias Sigil.Sui.Types.Character

  @doc """
  Resolves the effective tribe id for the current assembly detail session.
  """
  @spec current_tribe_id(Character.t() | nil, map() | nil) :: integer() | nil
  def current_tribe_id(%{tribe_id: tribe_id}, _current_account)
      when is_integer(tribe_id) and tribe_id > 0,
      do: tribe_id

  def current_tribe_id(_active_character, %{tribe_id: tribe_id})
      when is_integer(tribe_id) and tribe_id > 0,
      do: tribe_id

  def current_tribe_id(_active_character, _current_account), do: nil

  @doc """
  Returns whether intel features are available for the current tribe.
  """
  @spec intel_enabled?(map() | nil, integer() | nil) :: boolean()
  def intel_enabled?(cache_tables, tribe_id) do
    is_map(cache_tables) and is_integer(tribe_id) and Map.has_key?(cache_tables, :intel)
  end

  @doc """
  Builds intel context options from LiveView assigns.
  """
  @spec intel_opts(map(), atom() | module(), integer(), String.t()) :: Intel.options()
  def intel_opts(cache_tables, pubsub, tribe_id, world) when is_binary(world) do
    [tables: cache_tables, pubsub: pubsub, authorized_tribe_id: tribe_id, world: world]
  end

  @doc """
  Returns the character display name from metadata when available.
  """
  @spec character_name(Character.t()) :: String.t() | nil
  def character_name(%Character{metadata: %{name: name}}) when is_binary(name), do: name
  def character_name(_character), do: nil

  @doc """
  Resolves the displayed solar system name for a location report.
  """
  @spec resolve_location_name(pid() | nil, IntelReport.t() | nil) :: String.t() | nil
  def resolve_location_name(static_data_pid, %IntelReport{solar_system_id: solar_system_id})
      when is_pid(static_data_pid) and is_integer(solar_system_id) do
    case StaticData.get_solar_system(static_data_pid, solar_system_id) do
      %{name: name} -> name
      _other -> nil
    end
  end

  def resolve_location_name(_static_data_pid, _report), do: nil
end
