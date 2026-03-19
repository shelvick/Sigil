defmodule SigilWeb.AssemblyHelpers do
  @moduledoc """
  Shared display helpers for assembly LiveViews.

  Contains formatting functions used by both `DashboardLive` and
  `AssemblyDetailLive` to render assembly type labels, names, statuses,
  fuel gauges, and truncated identifiers.
  """

  alias Sigil.Assemblies
  alias Sigil.Sui.Types.{Assembly, Gate, NetworkNode, StorageUnit, Turret}

  @doc """
  Returns a human-readable type label for the assembly struct.
  """
  @spec assembly_type_label(Assemblies.assembly()) :: String.t()
  def assembly_type_label(%Gate{}), do: "Gate"
  def assembly_type_label(%Turret{}), do: "Turret"
  def assembly_type_label(%NetworkNode{}), do: "NetworkNode"
  def assembly_type_label(%StorageUnit{}), do: "StorageUnit"
  def assembly_type_label(%Assembly{}), do: "Assembly"

  @doc """
  Returns the assembly's metadata name, falling back to a truncated id.
  """
  @spec assembly_name(Assemblies.assembly()) :: String.t()
  def assembly_name(%{metadata: %{name: name}}) when is_binary(name) and byte_size(name) > 0,
    do: name

  def assembly_name(%{id: assembly_id}), do: truncate_id(assembly_id)

  @doc """
  Returns the assembly's online/offline status as a string.
  """
  @spec assembly_status(Assemblies.assembly()) :: String.t()
  def assembly_status(%{status: %{status: status}}), do: to_string(status)

  @doc """
  Returns Tailwind CSS classes for the assembly status badge.
  """
  @spec status_badge_classes(Assemblies.assembly()) :: String.t()
  def status_badge_classes(%{status: %{status: :online}}) do
    "inline-flex rounded-full border border-success/40 bg-success/10 px-3 py-1 font-mono text-xs uppercase tracking-[0.2em] text-success"
  end

  def status_badge_classes(%{status: %{status: :offline}}) do
    "inline-flex rounded-full border border-warning/60 bg-warning/10 px-3 py-1 font-mono text-xs uppercase tracking-[0.2em] text-warning"
  end

  def status_badge_classes(_assembly) do
    "inline-flex rounded-full border border-space-600/80 bg-space-900/70 px-3 py-1 font-mono text-xs uppercase tracking-[0.2em] text-space-500"
  end

  @doc """
  Returns the fuel quantity / max_capacity label string.
  """
  @spec fuel_label(Sigil.Sui.Types.Fuel.t()) :: String.t()
  def fuel_label(fuel), do: "#{fuel.quantity} / #{fuel.max_capacity}"

  @doc """
  Returns the fuel fill percentage as an integer 0..100.
  """
  @spec fuel_percent(Sigil.Sui.Types.Fuel.t()) :: non_neg_integer()
  def fuel_percent(%{max_capacity: 0}), do: 0

  def fuel_percent(%{quantity: quantity, max_capacity: max_capacity}) do
    quantity
    |> Kernel.*(100)
    |> div(max_capacity)
    |> min(100)
  end

  @doc """
  Returns the fuel percentage as a display string (e.g. "75%") or "N/A".
  """
  @spec fuel_percent_label(Sigil.Sui.Types.Fuel.t()) :: String.t()
  def fuel_percent_label(%{max_capacity: 0}), do: "N/A"
  def fuel_percent_label(fuel), do: "#{fuel_percent(fuel)}%"

  @doc """
  Truncates a hex identifier (0x...) to `0xabcd12...ef78` format.

  Returns the original string when it is too short to truncate.
  """
  @spec truncate_id(String.t()) :: String.t()
  def truncate_id("0x" <> _rest = id) when byte_size(id) > 14 do
    prefix = String.slice(id, 0, 8)
    suffix = String.slice(id, -4, 4)
    prefix <> "..." <> suffix
  end

  def truncate_id(id) when is_binary(id), do: id

  @doc """
  Returns the assembly's metadata description, or a placeholder.
  """
  @spec assembly_description(Assemblies.assembly()) :: String.t()
  def assembly_description(%{metadata: %{description: description}})
      when is_binary(description) and byte_size(description) > 0,
      do: description

  def assembly_description(_assembly), do: "No description provided"

  @doc """
  Truncates a value or returns a placeholder for nil.
  """
  @spec truncate_or_placeholder(String.t() | nil) :: String.t()
  def truncate_or_placeholder(nil), do: "Not set"
  def truncate_or_placeholder(value) when is_binary(value), do: truncate_id(value)

  @doc """
  Returns a display label for a linked gate id.
  """
  @spec linked_gate_label(String.t() | nil) :: String.t()
  def linked_gate_label(value) when is_binary(value) and byte_size(value) > 0, do: value
  def linked_gate_label(_value), do: "Not linked"

  @doc """
  Returns a display label for an extension field.
  """
  @spec extension_label(String.t() | nil) :: String.t()
  def extension_label(value) when is_binary(value) and byte_size(value) > 0, do: value
  def extension_label(_value), do: "None"

  @doc """
  Returns whether an extension field has a non-empty value.
  """
  @spec extension_active?(String.t() | nil) :: boolean()
  def extension_active?(value) when is_binary(value), do: byte_size(value) > 0
  def extension_active?(_value), do: false

  @doc """
  Formats a binary location hash as a truncated lowercase hex string.
  """
  @spec format_location_hash(binary()) :: String.t()
  def format_location_hash(hash) when is_binary(hash) do
    hash
    |> Base.encode16(case: :lower)
    |> truncate_or_placeholder()
  end

  @doc """
  Formats a burn rate in milliseconds as a human-readable string.

  Rates >= 3,600,000 ms display as "N per hour", rates >= 60,000 ms
  display as "N per minute", and smaller values display raw milliseconds.
  """
  @spec format_burn_rate(non_neg_integer()) :: String.t()
  def format_burn_rate(rate_in_ms) when rate_in_ms >= 3_600_000 do
    "#{div(rate_in_ms, 3_600_000)} per hour"
  end

  def format_burn_rate(rate_in_ms) when rate_in_ms >= 60_000 do
    "#{div(rate_in_ms, 60_000)} per minute"
  end

  def format_burn_rate(rate_in_ms) do
    "#{rate_in_ms} ms"
  end

  @doc """
  Formats a Sui millisecond timestamp for display.

  Returns `"Not burning"` when the feature flag is false, a formatted
  UTC datetime string for valid timestamps, or the raw integer string
  as a fallback.
  """
  @spec format_timestamp(non_neg_integer(), boolean()) :: String.t()
  def format_timestamp(_timestamp, false), do: "Not burning"

  def format_timestamp(timestamp, true) when is_integer(timestamp) and timestamp > 0 do
    case DateTime.from_unix(timestamp, :millisecond) do
      {:ok, dt} -> Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S UTC")
      {:error, _} -> Integer.to_string(timestamp)
    end
  end

  def format_timestamp(timestamp, true), do: Integer.to_string(timestamp)

  @doc """
  Formats a boolean as "Yes" or "No".
  """
  @spec yes_no(boolean()) :: String.t()
  def yes_no(true), do: "Yes"
  def yes_no(false), do: "No"

  @doc """
  Formats an optional integer value, returning "Not set" for nil.
  """
  @spec optional_integer(non_neg_integer() | nil) :: String.t()
  def optional_integer(nil), do: "Not set"
  def optional_integer(value), do: Integer.to_string(value)

  @doc """
  Returns the current energy production label with percentage.

  Displays "N/A" for the percentage when max production is zero
  to avoid division by zero.
  """
  @spec energy_current_label(Sigil.Sui.Types.EnergySource.t()) :: String.t()
  def energy_current_label(%{max_energy_production: 0, current_energy_production: current}) do
    "#{current} (N/A)"
  end

  def energy_current_label(energy_source) do
    percent =
      div(energy_source.current_energy_production * 100, energy_source.max_energy_production)

    "#{energy_source.current_energy_production} (#{percent}%)"
  end

  @doc """
  Returns the available energy (current production minus reserved).
  """
  @spec available_energy(Sigil.Sui.Types.EnergySource.t()) :: integer()
  def available_energy(energy_source) do
    energy_source.current_energy_production - energy_source.total_reserved_energy
  end
end
