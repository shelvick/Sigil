defmodule FrontierOSWeb.AssemblyHelpers do
  @moduledoc """
  Shared display helpers for assembly LiveViews.

  Contains formatting functions used by both `DashboardLive` and
  `AssemblyDetailLive` to render assembly type labels, names, statuses,
  fuel gauges, and truncated identifiers.
  """

  alias FrontierOS.Assemblies
  alias FrontierOS.Sui.Types.{Assembly, Gate, NetworkNode, StorageUnit, Turret}

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
  @spec fuel_label(FrontierOS.Sui.Types.Fuel.t()) :: String.t()
  def fuel_label(fuel), do: "#{fuel.quantity} / #{fuel.max_capacity}"

  @doc """
  Returns the fuel fill percentage as an integer 0..100.
  """
  @spec fuel_percent(FrontierOS.Sui.Types.Fuel.t()) :: non_neg_integer()
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
  @spec fuel_percent_label(FrontierOS.Sui.Types.Fuel.t()) :: String.t()
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
end
