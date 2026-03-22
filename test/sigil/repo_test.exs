defmodule Sigil.RepoTest do
  @moduledoc """
  Verifies Repo connectivity, sandbox isolation, and intel_reports access.
  """

  use Sigil.DataCase, async: true

  @compile {:no_warn_undefined, Sigil.Intel.IntelReport}

  alias Sigil.Intel.IntelReport
  alias Sigil.Repo

  test "repo connects to database" do
    assert Repo.one(from row in "intel_reports", select: count(row.id)) == 0
  end

  test "sandbox isolation between tests" do
    insert_raw_location_report!()

    assert Repo.one(from row in "intel_reports", select: count(row.id)) == 1

    task =
      Task.async(fn ->
        isolated_owner = Ecto.Adapters.SQL.Sandbox.start_owner!(Repo, shared: false)

        try do
          Repo.one(from row in "intel_reports", select: count(row.id))
        after
          Ecto.Adapters.SQL.Sandbox.stop_owner(isolated_owner)
        end
      end)

    assert Task.await(task) == 0
  end

  test "Repo persists intel reports" do
    assert {:ok, report} =
             struct(IntelReport)
             |> IntelReport.location_changeset(valid_location_params())
             |> Repo.insert()

    assert fetched = Repo.get(IntelReport, report.id)
    assert fetched.report_type == :location
    assert fetched.assembly_id == "0xassembly-1"
  end

  test "Repo accesses intel_reports after migration" do
    assert Repo.all(from row in "intel_reports", select: row.id) == []
  end

  defp insert_raw_location_report! do
    timestamp = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    assert {1, nil} =
             Repo.insert_all("intel_reports", [
               %{
                 id: Ecto.UUID.generate(),
                 tribe_id: 77,
                 assembly_id: "0xassembly-raw",
                 solar_system_id: 30_001_042,
                 label: "Forward Base",
                 report_type: "location",
                 notes: "Initial report",
                 reported_by: "0xabc123",
                 reported_by_name: "Scout Prime",
                 reported_by_character_id: "0xcharacter-1",
                 inserted_at: timestamp,
                 updated_at: timestamp
               }
             ])
  end

  defp valid_location_params(overrides \\ %{}) do
    Map.merge(
      %{
        tribe_id: 77,
        assembly_id: "0xassembly-1",
        solar_system_id: 30_001_042,
        label: "Foothold",
        notes: "Gate is online and fueled.",
        reported_by: "0xabc123",
        reported_by_name: "Scout Prime",
        reported_by_character_id: "0xcharacter-1"
      },
      overrides
    )
  end
end
