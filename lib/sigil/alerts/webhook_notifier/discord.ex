defmodule Sigil.Alerts.WebhookNotifier.Discord do
  @moduledoc """
  Discord webhook notifier for persisted alerts.
  """

  @behaviour Sigil.Alerts.WebhookNotifier

  alias Sigil.Alerts.{Alert, WebhookConfig}

  @critical_color 15_158_332
  @warning_color 15_105_570
  @info_color 3_447_003
  @server_retry_delay_ms 2_000
  @default_footer_text "Sigil Alert System"

  @doc "Posts an alert to a Discord webhook and retries once for retryable failures."
  @spec deliver(Alert.t(), WebhookConfig.t(), Sigil.Alerts.WebhookNotifier.options()) ::
          :ok
          | {:error, {:webhook_failed, pos_integer()}}
          | {:error, {:network_error, term()}}
  def deliver(%Alert{} = alert, %WebhookConfig{} = config, opts \\ []) when is_list(opts) do
    req_options = Keyword.get(opts, :req_options, [])
    delay_fun = Keyword.get(opts, :delay_fun, &:timer.sleep/1)

    alert
    |> request_options(config.webhook_url, req_options)
    |> post_with_retry(delay_fun, true)
  end

  @spec post_with_retry(keyword(), (non_neg_integer() -> term()), boolean()) ::
          :ok
          | {:error, {:webhook_failed, pos_integer()}}
          | {:error, {:network_error, term()}}
  defp post_with_retry(request_options, delay_fun, retry?) do
    case Req.post(request_options) do
      {:ok, %Req.Response{status: status}} when status in 200..299 ->
        :ok

      {:ok, %Req.Response{status: 429} = response} when retry? ->
        delay_fun.(retry_after_ms(response))
        post_with_retry(request_options, delay_fun, false)

      {:ok, %Req.Response{status: status}} when status >= 500 and retry? ->
        delay_fun.(@server_retry_delay_ms)
        post_with_retry(request_options, delay_fun, false)

      {:ok, %Req.Response{status: status}} ->
        {:error, {:webhook_failed, status}}

      {:error, %Req.TransportError{reason: reason}} ->
        {:error, {:network_error, reason}}

      {:error, reason} ->
        {:error, {:network_error, reason}}
    end
  end

  @spec request_options(Alert.t(), String.t() | nil, keyword()) :: keyword()
  defp request_options(alert, webhook_url, req_options) do
    Keyword.merge(req_options,
      url: webhook_url,
      json: build_payload(alert)
    )
  end

  @spec build_payload(Alert.t()) :: map()
  defp build_payload(alert) do
    %{"embeds" => [build_embed(alert)]}
  end

  @spec build_embed(Alert.t()) :: map()
  defp build_embed(%Alert{} = alert) do
    %{
      "title" => alert_title(alert.type),
      "description" => alert.message,
      "color" => severity_color(alert.severity),
      "fields" => [
        %{"name" => "Assembly", "value" => assembly_field_value(alert), "inline" => true},
        %{"name" => "Type", "value" => to_string(alert.type), "inline" => true},
        %{"name" => "Severity", "value" => to_string(alert.severity), "inline" => true}
      ],
      "timestamp" => timestamp(alert.inserted_at),
      "footer" => %{"text" => @default_footer_text}
    }
  end

  @spec assembly_field_value(Alert.t()) :: String.t()
  defp assembly_field_value(%Alert{assembly_name: assembly_name})
       when is_binary(assembly_name) and assembly_name != "",
       do: assembly_name

  defp assembly_field_value(%Alert{metadata: metadata}) when is_map(metadata) do
    case Map.get(metadata, :target_tribe_id) || Map.get(metadata, "target_tribe_id") do
      value when is_integer(value) -> "Tribe ##{value}"
      value when is_binary(value) and value != "" -> "Tribe ##{value}"
      _other -> "N/A"
    end
  end

  defp assembly_field_value(_alert), do: "N/A"

  @spec severity_color(String.t() | nil) :: non_neg_integer()
  defp severity_color("critical"), do: @critical_color
  defp severity_color("warning"), do: @warning_color
  defp severity_color("info"), do: @info_color
  defp severity_color(_severity), do: @info_color

  @spec alert_title(String.t() | nil) :: String.t()
  defp alert_title("fuel_low"), do: "Fuel Low"
  defp alert_title("fuel_critical"), do: "Fuel Critical"
  defp alert_title("assembly_offline"), do: "Assembly Offline"
  defp alert_title("extension_changed"), do: "Extension Changed"
  defp alert_title("hostile_activity"), do: "Hostile Activity"

  defp alert_title(type) when is_binary(type) do
    type
    |> String.split("_", trim: true)
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp alert_title(_type), do: "Sigil Alert"

  @spec timestamp(DateTime.t() | nil) :: String.t()
  defp timestamp(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  defp timestamp(_datetime), do: DateTime.utc_now() |> DateTime.to_iso8601()

  @spec retry_after_ms(Req.Response.t()) :: non_neg_integer()
  defp retry_after_ms(%Req.Response{body: %{"retry_after" => retry_after}}) do
    normalize_retry_after(retry_after) || @server_retry_delay_ms
  end

  defp retry_after_ms(%Req.Response{headers: headers}) when is_map(headers) do
    headers
    |> retry_after_header_value()
    |> normalize_retry_after()
    |> Kernel.||(@server_retry_delay_ms)
  end

  @spec retry_after_header_value(map()) :: term() | nil
  defp retry_after_header_value(headers) do
    case Map.get(headers, "retry-after") || Map.get(headers, "Retry-After") do
      [value | _] -> value
      _other -> nil
    end
  end

  @spec normalize_retry_after(term()) :: non_neg_integer() | nil
  defp normalize_retry_after(retry_after) when is_integer(retry_after) and retry_after >= 0,
    do: retry_after * 1_000

  defp normalize_retry_after(retry_after) when is_float(retry_after) and retry_after >= 0,
    do: round(retry_after * 1_000)

  defp normalize_retry_after(retry_after) when is_binary(retry_after) do
    case Float.parse(retry_after) do
      {value, ""} when value >= 0 -> round(value * 1_000)
      _other -> nil
    end
  end

  defp normalize_retry_after(_retry_after), do: nil
end
