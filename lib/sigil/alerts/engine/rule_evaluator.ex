defmodule Sigil.Alerts.Engine.RuleEvaluator do
  @moduledoc """
  Internal rule evaluation helpers for transforming monitor payloads into alert attrs.
  """

  @typedoc "Resolved ownership context for a monitor event."
  @type context() :: %{
          account_address: String.t(),
          assembly_name: String.t(),
          tribe_id: integer() | nil
        }

  @doc "Builds the full set of alert attrs triggered by a single monitor payload."
  @spec triggered_alerts(map(), context(), DateTime.t()) :: [map()]
  def triggered_alerts(payload, context, now) do
    offline_alerts(payload, context) ++
      extension_alerts(payload, context) ++
      fuel_alerts(payload, context, now)
  end

  @spec offline_alerts(map(), context()) :: [map()]
  defp offline_alerts(%{changes: changes} = payload, context) when is_list(changes) do
    Enum.flat_map(changes, fn
      {:status_changed, previous_status, :offline} ->
        [
          base_attrs("assembly_offline", "critical", payload, context)
          |> Map.put(:message, "Assembly has gone offline")
          |> Map.put(:metadata, %{previous_status: previous_status})
        ]

      _change ->
        []
    end)
  end

  defp offline_alerts(_payload, _context), do: []

  @spec extension_alerts(map(), context()) :: [map()]
  defp extension_alerts(%{changes: changes} = payload, context) when is_list(changes) do
    Enum.flat_map(changes, fn
      {:extension_changed, previous_extension, new_extension} ->
        [
          base_attrs("extension_changed", "info", payload, context)
          |> Map.put(:message, extension_message(previous_extension, new_extension))
          |> Map.put(:metadata, %{old_extension: previous_extension, new_extension: new_extension})
        ]

      _change ->
        []
    end)
  end

  defp extension_alerts(_payload, _context), do: []

  @spec fuel_alerts(map(), context(), DateTime.t()) :: [map()]
  defp fuel_alerts(payload, context, now) do
    case fuel_critical_alert(payload, context, now) do
      [] -> fuel_low_alert(payload, context)
      critical_alerts -> critical_alerts
    end
  end

  @spec fuel_critical_alert(map(), context(), DateTime.t()) :: [map()]
  defp fuel_critical_alert(
         %{depletion: {:depletes_at, depletes_at}} = payload,
         context,
         %DateTime{} = now
       ) do
    minutes_remaining = DateTime.diff(depletes_at, now, :minute)

    if minutes_remaining > 0 and minutes_remaining < 120 do
      hours = div(minutes_remaining, 60)
      minutes = rem(minutes_remaining, 60)

      [
        base_attrs("fuel_critical", "critical", payload, context)
        |> Map.put(:message, "Fuel depletes in #{hours}h #{minutes}m")
        |> Map.put(:metadata, %{depletes_at: depletes_at})
      ]
    else
      []
    end
  end

  defp fuel_critical_alert(_payload, _context, _now), do: []

  @spec fuel_low_alert(map(), context()) :: [map()]
  defp fuel_low_alert(
         %{assembly: %{fuel: %{quantity: quantity, max_capacity: max_capacity}}} = payload,
         context
       )
       when is_integer(quantity) and is_integer(max_capacity) and max_capacity > 0 do
    ratio = quantity / max_capacity

    if ratio < 0.20 do
      [
        base_attrs("fuel_low", "warning", payload, context)
        |> Map.put(:message, fuel_low_message(quantity, max_capacity))
        |> Map.put(:metadata, %{quantity: quantity, max_capacity: max_capacity, ratio: ratio})
      ]
    else
      []
    end
  end

  defp fuel_low_alert(_payload, _context), do: []

  @spec fuel_low_message(non_neg_integer(), pos_integer()) :: String.t()
  defp fuel_low_message(quantity, max_capacity) do
    percentage = quantity / max_capacity * 100

    "Fuel at #{:erlang.float_to_binary(percentage, decimals: 1)}% (#{quantity}/#{max_capacity} units)"
  end

  @spec extension_message(String.t() | nil, String.t() | nil) :: String.t()
  defp extension_message(nil, new_extension) when is_binary(new_extension),
    do: "Extension installed: #{new_extension}"

  defp extension_message(previous_extension, nil) when is_binary(previous_extension),
    do: "Extension removed: #{previous_extension}"

  defp extension_message(previous_extension, new_extension)
       when is_binary(previous_extension) and is_binary(new_extension),
       do: "Extension changed from #{previous_extension} to #{new_extension}"

  defp extension_message(_previous_extension, _new_extension), do: "Extension changed"

  @spec base_attrs(String.t(), String.t(), map(), context()) :: map()
  defp base_attrs(type, severity, payload, context) do
    %{
      type: type,
      severity: severity,
      assembly_id: payload.assembly.id,
      assembly_name: context.assembly_name,
      account_address: context.account_address,
      tribe_id: context.tribe_id,
      message: nil,
      metadata: %{}
    }
  end
end
