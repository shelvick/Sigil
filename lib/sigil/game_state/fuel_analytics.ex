defmodule Sigil.GameState.FuelAnalytics do
  @moduledoc """
  Computes fuel depletion estimates and maintains bounded fuel snapshot buffers.
  """

  alias Sigil.Sui.Types.Fuel

  @typedoc "Predicted depletion state for a network node fuel tank."
  @type depletion_result() :: {:depletes_at, DateTime.t()} | :not_burning | :no_fuel

  @typedoc "Timestamped fuel quantity sample stored in monitor history."
  @type fuel_snapshot() :: {timestamp_ms :: non_neg_integer(), quantity :: non_neg_integer()}

  @doc """
  Returns the estimated depletion time for a fuel tank.
  """
  @spec compute_depletion(Fuel.t()) :: depletion_result()
  def compute_depletion(%Fuel{} = fuel) do
    cond do
      fuel.quantity == 0 ->
        :no_fuel

      not fuel.is_burning or fuel.burn_rate_in_ms == 0 ->
        :not_burning

      true ->
        total_remaining_ms = fuel.quantity * fuel.burn_rate_in_ms

        elapsed_ms =
          (System.os_time(:millisecond) - fuel.burn_start_time + fuel.previous_cycle_elapsed_time)
          |> max(0)

        now = DateTime.utc_now()
        adjusted_remaining_ms = total_remaining_ms - elapsed_ms

        depletes_at =
          if adjusted_remaining_ms <= 0 do
            now
          else
            DateTime.add(now, adjusted_remaining_ms, :millisecond)
          end

        {:depletes_at, depletes_at}
    end
  end

  @doc """
  Appends a fuel snapshot while keeping only the most recent entries.
  """
  @spec ring_buffer_push([fuel_snapshot()], fuel_snapshot(), non_neg_integer()) :: [
          fuel_snapshot()
        ]
  def ring_buffer_push(buffer, entry, max_size \\ 60) do
    case max_size do
      size when size <= 0 ->
        []

      size ->
        buffer
        |> Kernel.++([entry])
        |> Enum.take(-size)
    end
  end
end
