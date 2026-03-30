defmodule SigilWeb.AlertsHelpers do
  @moduledoc """
  Shared display helpers for alerts LiveViews.
  """

  alias Sigil.Alerts.Alert
  alias SigilWeb.IntelHelpers

  @doc """
  Returns the card classes for an alert based on its status.
  """
  @spec card_classes(Alert.t() | map()) :: String.t()
  def card_classes(%{status: "new"}),
    do: "overflow-hidden rounded-2xl border border-quantum-400/60 bg-space-800/90 p-5"

  def card_classes(%{status: "acknowledged"}),
    do: "overflow-hidden rounded-2xl border border-space-600/80 bg-space-800/70 p-5"

  def card_classes(%{status: "dismissed"}),
    do: "overflow-hidden rounded-2xl border border-space-700/50 bg-space-900/50 p-5"

  def card_classes(_alert),
    do: "overflow-hidden rounded-2xl border border-space-600/80 bg-space-800/70 p-5"

  @doc """
  Returns the severity badge classes for an alert severity.
  """
  @spec severity_badge_classes(String.t() | nil) :: String.t()
  def severity_badge_classes("critical") do
    "rounded-full border border-red-500/40 bg-red-500/10 px-3 py-1 font-mono text-xs uppercase tracking-[0.2em] text-red-400"
  end

  def severity_badge_classes("warning") do
    "rounded-full border border-warning/40 bg-warning/10 px-3 py-1 font-mono text-xs uppercase tracking-[0.2em] text-warning"
  end

  def severity_badge_classes(_severity) do
    "rounded-full border border-quantum-400/40 bg-quantum-400/10 px-3 py-1 font-mono text-xs uppercase tracking-[0.2em] text-quantum-300"
  end

  @doc """
  Returns the display label for an alert type.
  """
  @spec type_label(String.t() | nil) :: String.t()
  def type_label("fuel_low"), do: "Fuel Low"
  def type_label("fuel_critical"), do: "Fuel Critical"
  def type_label("assembly_offline"), do: "Assembly Offline"
  def type_label("extension_changed"), do: "Extension Changed"
  def type_label("hostile_activity"), do: "Hostile Activity"
  def type_label(_type), do: "Alert"

  @doc """
  Returns the message classes for an alert status.
  """
  @spec message_classes(String.t() | nil) :: String.t()
  def message_classes("acknowledged"), do: "text-sm leading-6 text-space-400"
  def message_classes("dismissed"), do: "text-sm leading-6 text-space-500"
  def message_classes(_status), do: "text-sm leading-6 text-foreground"

  @doc """
  Formats an alert timestamp using the shared relative timestamp buckets.
  """
  @spec timestamp_label(Alert.t() | map()) :: String.t()
  def timestamp_label(%{inserted_at: %DateTime{} = inserted_at}) do
    IntelHelpers.relative_timestamp_label(inserted_at)
  end

  def timestamp_label(_alert), do: "Just now"

  @doc "Returns the owning character name from alert metadata, if present."
  @spec alert_character_name(Alert.t() | map()) :: String.t() | nil
  def alert_character_name(%{metadata: metadata}) when is_map(metadata) do
    Map.get(metadata, :character_name) || Map.get(metadata, "character_name")
  end

  def alert_character_name(_alert), do: nil
end
