defmodule SigilWeb.IntelHelpersTest do
  @moduledoc """
  Tests the shared relative timestamp formatting helpers for intel views.
  """

  use ExUnit.Case, async: true

  alias SigilWeb.IntelHelpers

  describe "relative_timestamp_label/2" do
    test "returns Just now for recent timestamps" do
      now = ~U[2026-03-22 12:00:00Z]
      timestamp = ~U[2026-03-22 11:59:31Z]

      assert IntelHelpers.relative_timestamp_label(timestamp, now) == "Just now"
    end

    test "returns minutes for timestamps under one hour" do
      now = ~U[2026-03-22 12:00:00Z]
      timestamp = ~U[2026-03-22 11:15:00Z]

      assert IntelHelpers.relative_timestamp_label(timestamp, now) == "45m ago"
    end

    test "returns hours for timestamps under one day" do
      now = ~U[2026-03-22 12:00:00Z]
      timestamp = ~U[2026-03-22 09:00:00Z]

      assert IntelHelpers.relative_timestamp_label(timestamp, now) == "3h ago"
    end

    test "returns days for timestamps under one week" do
      now = ~U[2026-03-22 12:00:00Z]
      timestamp = ~U[2026-03-19 12:00:00Z]

      assert IntelHelpers.relative_timestamp_label(timestamp, now) == "3d ago"
    end

    test "falls back to absolute timestamp after one week" do
      now = ~U[2026-03-22 12:00:00Z]
      timestamp = ~U[2026-03-14 08:30:00Z]

      assert IntelHelpers.relative_timestamp_label(timestamp, now) == "Mar 14, 2026 08:30 UTC"
    end
  end
end
