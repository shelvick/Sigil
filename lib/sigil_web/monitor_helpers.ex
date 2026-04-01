defmodule SigilWeb.MonitorHelpers do
  @moduledoc """
  Shared helpers for resolving monitor infrastructure and computing
  fuel depletion display values in LiveViews.
  """

  alias Sigil.GameState.FuelAnalytics
  alias Sigil.Sui.Types.NetworkNode
  alias SigilWeb.CacheResolver

  @doc """
  Resolves the monitor supervisor PID and registry name from socket assigns
  or the application supervision tree.
  """
  @spec monitor_dependencies(Phoenix.LiveView.Socket.t()) ::
          {:ok, pid(), atom()} | {:error, :not_available}
  def monitor_dependencies(socket) do
    case {socket.assigns[:monitor_supervisor], socket.assigns[:monitor_registry]} do
      {supervisor, registry} when is_pid(supervisor) and is_atom(registry) ->
        {:ok, supervisor, registry}

      _other ->
        world = socket.assigns[:world] || Sigil.Worlds.default_world()

        case {CacheResolver.application_monitor_supervisor(world),
              CacheResolver.application_monitor_registry(world)} do
          {supervisor, registry} when is_pid(supervisor) and is_atom(registry) ->
            {:ok, supervisor, registry}

          _other ->
            {:error, :not_available}
        end
    end
  end

  @doc """
  Computes the initial fuel depletion estimate for an assembly on mount.
  Returns nil for non-NetworkNode assemblies.
  """
  @spec initial_depletion(term()) :: FuelAnalytics.depletion_result() | nil
  def initial_depletion(%NetworkNode{fuel: fuel}), do: FuelAnalytics.compute_depletion(fuel)
  def initial_depletion(_assembly), do: nil

  @doc """
  Formats a depletion DateTime as a relative countdown string.
  """
  @spec relative_depletion_label(DateTime.t()) :: String.t()
  def relative_depletion_label(%DateTime{} = depletes_at) do
    seconds_remaining = max(DateTime.diff(depletes_at, DateTime.utc_now(), :second), 0)
    hours = div(seconds_remaining, 3600)
    minutes = div(rem(seconds_remaining, 3600), 60)
    seconds = rem(seconds_remaining, 60)

    "#{hours}h #{minutes}m #{seconds}s"
  end
end
