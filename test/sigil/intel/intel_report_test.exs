defmodule Sigil.Intel.IntelReportTest do
  @moduledoc """
  Verifies intel report schema validations and migration-backed constraints.
  """

  use Sigil.DataCase, async: true

  @compile {:no_warn_undefined, Sigil.Intel.IntelReport}

  alias Sigil.Intel.IntelReport
  alias Sigil.Repo

  describe "location_changeset/2" do
    test "location_changeset rejects missing required fields" do
      changeset = IntelReport.location_changeset(struct(IntelReport), %{})

      refute changeset.valid?

      assert errors_on(changeset) == %{
               assembly_id: ["can't be blank"],
               reported_by: ["can't be blank"],
               reported_by_character_id: ["can't be blank"],
               tribe_id: ["can't be blank"]
             }
    end

    test "location_changeset accepts valid location params" do
      changeset = IntelReport.location_changeset(struct(IntelReport), valid_location_params())

      assert changeset.valid?
      assert get_change(changeset, :report_type) == :location
      assert get_change(changeset, :assembly_id) == "0xassembly-1"
      assert get_change(changeset, :solar_system_id) == 30_001_042
    end

    test "location_changeset rejects blank assembly_id" do
      changeset =
        IntelReport.location_changeset(
          struct(IntelReport),
          valid_location_params(%{assembly_id: "   "})
        )

      refute changeset.valid?
      assert errors_on(changeset).assembly_id == ["can't be blank"]
    end
  end

  describe "scouting_changeset/2" do
    test "scouting_changeset requires non-empty notes" do
      blank_changeset =
        IntelReport.scouting_changeset(
          struct(IntelReport),
          Map.delete(valid_scouting_params(), :notes)
        )

      empty_changeset =
        IntelReport.scouting_changeset(
          struct(IntelReport),
          valid_scouting_params(%{notes: "   "})
        )

      refute blank_changeset.valid?
      refute empty_changeset.valid?
      assert errors_on(blank_changeset).notes == ["can't be blank"]
      assert errors_on(empty_changeset).notes == ["can't be blank"]
    end

    test "scouting_changeset accepts valid scouting params" do
      changeset = IntelReport.scouting_changeset(struct(IntelReport), valid_scouting_params())

      assert changeset.valid?
      assert get_change(changeset, :report_type) == :scouting
      assert get_change(changeset, :notes) == "Observed hostile scouts near the gate."
      assert get_change(changeset, :assembly_id) == nil
    end
  end

  describe "shared validations" do
    test "changeset rejects notes exceeding 1000 characters" do
      params = valid_scouting_params(%{notes: String.duplicate("n", 1001)})
      changeset = IntelReport.scouting_changeset(struct(IntelReport), params)

      refute changeset.valid?
      assert errors_on(changeset).notes == ["should be at most 1000 character(s)"]
    end

    test "changeset rejects labels exceeding 120 characters" do
      params = valid_location_params(%{label: String.duplicate("l", 121)})
      changeset = IntelReport.location_changeset(struct(IntelReport), params)

      refute changeset.valid?
      assert errors_on(changeset).label == ["should be at most 120 character(s)"]
    end

    test "changeset allows zero solar_system_id and rejects negative" do
      zero_changeset =
        IntelReport.location_changeset(
          struct(IntelReport),
          valid_location_params(%{solar_system_id: 0})
        )

      negative_changeset =
        IntelReport.scouting_changeset(
          struct(IntelReport),
          valid_scouting_params(%{solar_system_id: -42})
        )

      assert zero_changeset.valid?
      refute negative_changeset.valid?

      assert errors_on(negative_changeset).solar_system_id == [
               "must be greater than or equal to 0"
             ]
    end
  end

  describe "repo integration" do
    test "location uniqueness constraint prevents duplicate active rows" do
      first_report = insert_location_report!(%{notes: "Initial sighting"})

      duplicate_changeset =
        struct(IntelReport)
        |> IntelReport.location_changeset(valid_location_params(%{notes: "Updated sighting"}))
        |> Repo.insert()

      assert {:error, changeset} = duplicate_changeset
      assert errors_on(changeset).assembly_id == ["has already been taken"]

      reports = Repo.all(IntelReport)
      assert Enum.map(reports, & &1.id) == [first_report.id]
    end

    test "multiple scouting reports for same system are allowed" do
      assert {:ok, first} =
               struct(IntelReport)
               |> IntelReport.scouting_changeset(valid_scouting_params(%{notes: "First report"}))
               |> Repo.insert()

      assert {:ok, second} =
               struct(IntelReport)
               |> IntelReport.scouting_changeset(valid_scouting_params(%{notes: "Second report"}))
               |> Repo.insert()

      reports =
        IntelReport
        |> Repo.all()
        |> Enum.sort_by(& &1.notes)

      assert Enum.map(reports, & &1.id) == [first.id, second.id]
      assert Enum.map(reports, & &1.notes) == ["First report", "Second report"]
    end

    test "intel_reports table exists after migration" do
      columns =
        Repo.query!("""
        SELECT column_name
        FROM information_schema.columns
        WHERE table_schema = current_schema()
          AND table_name = 'intel_reports'
        ORDER BY ordinal_position
        """).rows
        |> List.flatten()

      indexes =
        Repo.query!("""
        SELECT indexname, indexdef
        FROM pg_indexes
        WHERE schemaname = current_schema()
          AND tablename = 'intel_reports'
        ORDER BY indexname
        """).rows

      assert columns == [
               "id",
               "tribe_id",
               "assembly_id",
               "solar_system_id",
               "label",
               "report_type",
               "notes",
               "reported_by",
               "reported_by_name",
               "reported_by_character_id",
               "inserted_at",
               "updated_at"
             ]

      assert Enum.any?(indexes, fn [indexname, _indexdef] ->
               indexname == "intel_reports_tribe_id_index"
             end)

      assert Enum.any?(indexes, fn [indexname, indexdef] ->
               indexname == "intel_reports_tribe_assembly_location_idx" and
                 String.contains?(indexdef, "UNIQUE INDEX") and
                 String.contains?(indexdef, "(tribe_id, assembly_id)") and
                 String.contains?(indexdef, "report_type") and
                 String.contains?(indexdef, "location") and
                 String.contains?(indexdef, "assembly_id IS NOT NULL")
             end)
    end
  end

  defp insert_location_report!(attrs) do
    struct(IntelReport)
    |> IntelReport.location_changeset(valid_location_params(attrs))
    |> Repo.insert!()
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

  defp valid_scouting_params(overrides \\ %{}) do
    Map.merge(
      %{
        tribe_id: 77,
        assembly_id: nil,
        solar_system_id: 30_001_042,
        label: "Advance patrol",
        notes: "Observed hostile scouts near the gate.",
        reported_by: "0xabc123",
        reported_by_name: "Scout Prime",
        reported_by_character_id: "0xcharacter-1"
      },
      overrides
    )
  end
end
