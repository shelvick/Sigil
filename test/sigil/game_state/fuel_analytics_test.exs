defmodule Sigil.GameState.FuelAnalyticsTest do
  @moduledoc """
  Tests fuel depletion calculations and bounded snapshot buffer behavior.
  """

  use ExUnit.Case, async: true

  alias Sigil.GameState.FuelAnalytics
  alias Sigil.Sui.Types.Fuel

  test "compute_depletion/1 returns future depletes_at for burning fuel" do
    fuel = fuel(quantity: 10, burn_rate_in_ms: 1_000, burn_start_time: now_ms())
    before = DateTime.utc_now()

    assert {:depletes_at, depletes_at} = FuelAnalytics.compute_depletion(fuel)

    assert DateTime.compare(depletes_at, before) in [:eq, :gt]
    assert DateTime.compare(depletes_at, DateTime.utc_now()) == :gt
  end

  test "compute_depletion/1 returns :not_burning when fuel is not burning" do
    assert :not_burning =
             FuelAnalytics.compute_depletion(fuel(is_burning: false, burn_start_time: now_ms()))
  end

  test "compute_depletion/1 returns :no_fuel when quantity is zero" do
    assert :no_fuel =
             FuelAnalytics.compute_depletion(fuel(quantity: 0, burn_start_time: now_ms()))
  end

  test "compute_depletion/1 returns :not_burning when burn_rate is zero" do
    assert :not_burning =
             FuelAnalytics.compute_depletion(
               fuel(burn_rate_in_ms: 0, is_burning: true, burn_start_time: now_ms())
             )
  end

  test "compute_depletion/1 accounts for elapsed burn time" do
    now = now_ms()

    fuel =
      fuel(
        quantity: 10,
        burn_rate_in_ms: 1_000,
        burn_start_time: now - 2_500,
        previous_cycle_elapsed_time: 500,
        last_updated: now
      )

    before = DateTime.utc_now()
    assert {:depletes_at, depletes_at} = FuelAnalytics.compute_depletion(fuel)

    # Total fuel capacity = 10 * 1000 = 10_000ms
    # Elapsed = (now - (now-2500)) + 500 = 3000ms
    # Remaining = 10_000 - 3_000 = 7_000ms
    # depletes_at should be ~7s after before, give or take execution time
    diff_ms = DateTime.diff(depletes_at, before, :millisecond)
    assert diff_ms > 5_000, "expected > 5s remaining, got #{diff_ms}ms"
    assert diff_ms < 9_000, "expected < 9s remaining, got #{diff_ms}ms"
  end

  test "ring_buffer_push/3 appends entry within capacity" do
    assert FuelAnalytics.ring_buffer_push([{1, 10}], {2, 20}, 3) == [{1, 10}, {2, 20}]
  end

  test "ring_buffer_push/3 drops oldest entry at capacity" do
    assert FuelAnalytics.ring_buffer_push([{1, 10}, {2, 20}], {3, 30}, 2) == [{2, 20}, {3, 30}]
  end

  test "ring_buffer_push/3 handles empty buffer" do
    assert FuelAnalytics.ring_buffer_push([], {1, 10}, 3) == [{1, 10}]
  end

  test "ring_buffer_push/3 with zero max_size returns empty" do
    assert FuelAnalytics.ring_buffer_push([{1, 10}], {2, 20}, 0) == []
  end

  test "compute_depletion/1 handles already-depleted fuel" do
    fuel = fuel(quantity: 2, burn_rate_in_ms: 1_000, burn_start_time: now_ms() - 5_000)

    assert {:depletes_at, depletes_at} = FuelAnalytics.compute_depletion(fuel)
    assert DateTime.diff(depletes_at, DateTime.utc_now(), :millisecond) <= 100
  end

  defp fuel(overrides) do
    now = now_ms()

    struct!(
      Fuel,
      Keyword.merge(
        [
          max_capacity: 5_000,
          burn_rate_in_ms: 1_000,
          type_id: 42,
          unit_volume: 2,
          quantity: 10,
          is_burning: true,
          previous_cycle_elapsed_time: 0,
          burn_start_time: now,
          last_updated: now
        ],
        overrides
      )
    )
  end

  defp now_ms, do: System.os_time(:millisecond)
end
