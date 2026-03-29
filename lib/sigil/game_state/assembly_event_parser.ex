defmodule Sigil.GameState.AssemblyEventParser do
  @moduledoc """
  Pure helpers for identifying assembly lifecycle events and extracting assembly IDs.
  """

  @assembly_event_types [
    :assembly_status_changed,
    :assembly_fuel_changed,
    :assembly_extension_authorized
  ]

  @typedoc "Supported assembly lifecycle event atoms."
  @type assembly_event_type() ::
          :assembly_status_changed
          | :assembly_fuel_changed
          | :assembly_extension_authorized

  @typedoc "Error reasons returned when extracting assembly IDs."
  @type extract_error() :: :missing_assembly_id | :not_assembly_event

  @doc "Returns true when the event type is an assembly lifecycle event."
  @spec assembly_event?(atom()) :: boolean()
  def assembly_event?(event_type), do: event_type in @assembly_event_types

  @doc "Extracts assembly_id from normalized raw event data for assembly events."
  @spec extract_assembly_id(atom(), map()) :: {:ok, String.t()} | {:error, extract_error()}
  def extract_assembly_id(event_type, raw_data) when is_map(raw_data) do
    if assembly_event?(event_type) do
      case Map.get(raw_data, "assembly_id") do
        assembly_id when is_binary(assembly_id) and assembly_id != "" -> {:ok, assembly_id}
        _other -> {:error, :missing_assembly_id}
      end
    else
      {:error, :not_assembly_event}
    end
  end

  def extract_assembly_id(_event_type, _raw_data), do: {:error, :not_assembly_event}

  @doc "Returns all assembly lifecycle event type atoms used by the router."
  @spec assembly_event_types() :: [assembly_event_type()]
  def assembly_event_types, do: @assembly_event_types
end
