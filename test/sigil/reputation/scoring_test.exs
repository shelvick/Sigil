defmodule Sigil.Reputation.ScoringTest do
  @moduledoc """
  Covers packet 4 reputation scoring algorithm contracts.
  """

  use ExUnit.Case, async: true

  @compile {:no_warn_undefined, Sigil.Reputation.Scoring}

  alias Sigil.Reputation.Scoring

  describe "compute_kill_score/4" do
    test "returns base delta without multipliers" do
      assert Scoring.compute_kill_score(0, 4, false, false) == -50
    end

    test "applies 3x aggressor multiplier" do
      assert Scoring.compute_kill_score(1, 3, true, false) == -75
    end

    test "applies 2x on_our_grid multiplier" do
      assert Scoring.compute_kill_score(1, 3, false, true) == -50
    end

    test "stacks aggressor and on_our_grid multipliers to 6x" do
      assert Scoring.compute_kill_score(0, 4, true, true) == -300
    end

    test "killing ally is worse than killing neutral" do
      neutral_kill_delta = Scoring.compute_kill_score(0, 2, false, false)
      ally_kill_delta = Scoring.compute_kill_score(0, 3, false, false)

      assert ally_kill_delta < neutral_kill_delta
    end
  end

  describe "compute_jump_score/0" do
    test "returns 5" do
      assert Scoring.compute_jump_score() == 5
    end
  end

  describe "apply_decay/3" do
    test "reaches half-life at 14 days with default rate" do
      decayed = Scoring.apply_decay(1000, 336)

      assert decayed >= 475
      assert decayed <= 525
    end

    test "returns 0 for zero score" do
      assert Scoring.apply_decay(0, 336) == 0
    end
  end

  describe "compute_transitive_score/3" do
    test "computes weighted influence from standing graph" do
      our_standings = %{101 => 4, 202 => 0, 303 => 4}
      their_standings_of_target = %{101 => 4, 202 => 0, 303 => 0}

      assert Scoring.compute_transitive_score(our_standings, their_standings_of_target) == 1
    end
  end

  describe "evaluate_tier/2" do
    test "classifies hostile at boundary" do
      assert Scoring.evaluate_tier(-700) == 0
      assert Scoring.evaluate_tier(-699) == 1
    end

    test "classifies neutral at center" do
      assert Scoring.evaluate_tier(0) == 2
    end

    test "classifies friendly at boundary" do
      assert Scoring.evaluate_tier(200) == 3
      assert Scoring.evaluate_tier(199) == 2
    end

    test "classifies allied at boundary" do
      assert Scoring.evaluate_tier(700) == 4
      assert Scoring.evaluate_tier(699) == 3
    end
  end

  describe "aggressor_expired?/2" do
    test "expires after 30 minutes" do
      now = ~U[2026-03-28 12:00:00Z]

      assert Scoring.aggressor_expired?(DateTime.add(now, -(31 * 60), :second), now)
      refute Scoring.aggressor_expired?(DateTime.add(now, -(29 * 60), :second), now)
    end
  end
end
