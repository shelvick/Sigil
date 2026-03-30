defmodule Sigil.IntelTest do
  @moduledoc """
  Covers the packet 2 intel context contract from the approved spec.
  """

  use Sigil.DataCase, async: true

  @compile {:no_warn_undefined, Sigil.Intel}

  alias Sigil.{Cache, Repo}
  alias Sigil.Intel
  alias Sigil.Intel.IntelReport

  setup do
    cache_pid = start_supervised!({Cache, tables: [:intel]})
    pubsub = unique_pubsub_name()

    start_supervised!({Phoenix.PubSub, name: pubsub})
    :ok = Phoenix.PubSub.subscribe(pubsub, intel_topic(77))
    :ok = Phoenix.PubSub.subscribe(pubsub, intel_topic(88))

    {:ok,
     tables: Cache.tables(cache_pid),
     pubsub: pubsub,
     tribe_id: 77,
     other_tribe_id: 88,
     assembly_id: "0xassembly-1"}
  end

  describe "report_location/2" do
    test "report_location creates location intel report", context do
      assert {:ok, %IntelReport{} = report} =
               Intel.report_location(valid_location_params(context), intel_opts(context))

      assert report.tribe_id == context.tribe_id
      assert report.assembly_id == context.assembly_id
      assert report.report_type == :location

      assert %IntelReport{id: persisted_id, solar_system_id: 30_001_042, report_type: :location} =
               Repo.get(IntelReport, report.id)

      assert persisted_id == report.id
    end

    test "report_location upserts existing location for same tribe+assembly", context do
      existing =
        insert_location_report!(%{
          tribe_id: context.tribe_id,
          assembly_id: context.assembly_id,
          solar_system_id: 30_001_042,
          notes: "Initial sighting"
        })

      assert {:ok, %IntelReport{} = updated} =
               Intel.report_location(
                 valid_location_params(context, %{
                   solar_system_id: 30_009_999,
                   notes: "Updated sighting"
                 }),
                 intel_opts(context)
               )

      reports =
        Repo.all(
          from report in IntelReport,
            where:
              report.tribe_id == ^context.tribe_id and report.assembly_id == ^context.assembly_id
        )

      assert length(reports) == 1
      assert hd(reports).solar_system_id == 30_009_999
      assert hd(reports).notes == "Updated sighting"
      refute updated.id == nil
      refute existing.id == nil
    end

    test "report_location writes through to ETS cache", context do
      assert {:ok, %IntelReport{} = report} =
               Intel.report_location(valid_location_params(context), intel_opts(context))

      assert Cache.get(context.tables.intel, {:location, context.tribe_id, context.assembly_id}) ==
               report
    end

    test "report_location broadcasts intel_updated on PubSub", context do
      assert {:ok, %IntelReport{} = report} =
               Intel.report_location(valid_location_params(context), intel_opts(context))

      report_id = report.id
      tribe_id = context.tribe_id

      assert_receive {:intel_updated, %IntelReport{id: ^report_id, tribe_id: ^tribe_id}}
    end

    test "report_location rejects invalid params", context do
      assert {:error, changeset} =
               Intel.report_location(
                 valid_location_params(context, %{
                   assembly_id: nil,
                   solar_system_id: nil,
                   reported_by: nil,
                   reported_by_character_id: nil
                 }),
                 intel_opts(context)
               )

      assert errors_on(changeset) == %{
               reported_by: ["can't be blank"],
               reported_by_character_id: ["can't be blank"]
             }
    end
  end

  describe "report_scouting/2" do
    test "report_scouting creates scouting intel report", context do
      assert {:ok, %IntelReport{} = report} =
               Intel.report_scouting(valid_scouting_params(context), intel_opts(context))

      assert report.tribe_id == context.tribe_id
      assert report.report_type == :scouting
      assert report.assembly_id == nil

      assert %IntelReport{id: persisted_id, notes: "Observed hostile scouts near the gate."} =
               Repo.get(IntelReport, report.id)

      assert persisted_id == report.id
    end

    test "report_scouting allows multiple reports per system", context do
      assert {:ok, first} =
               Intel.report_scouting(
                 valid_scouting_params(context, %{notes: "First report"}),
                 intel_opts(context)
               )

      assert {:ok, second} =
               Intel.report_scouting(
                 valid_scouting_params(context, %{
                   notes: "Second report",
                   reported_by: "0xdef456",
                   reported_by_character_id: "0xcharacter-2"
                 }),
                 intel_opts(context)
               )

      reports =
        Repo.all(
          from report in IntelReport,
            where:
              report.tribe_id == ^context.tribe_id and
                report.solar_system_id == 30_001_042 and
                report.report_type == :scouting,
            order_by: [asc: report.notes]
        )

      assert Enum.map(reports, & &1.id) == [first.id, second.id]
      assert Enum.map(reports, & &1.notes) == ["First report", "Second report"]
    end
  end

  describe "list_intel/2" do
    test "list_intel returns only reports for the specified tribe", context do
      older =
        insert_location_report!(%{
          tribe_id: context.tribe_id,
          assembly_id: "0xassembly-older",
          notes: "Older report"
        })

      newer =
        insert_scouting_report!(%{
          tribe_id: context.tribe_id,
          notes: "Newer report"
        })

      _other =
        insert_location_report!(%{
          tribe_id: context.other_tribe_id,
          assembly_id: "0xassembly-other",
          notes: "Other tribe report"
        })

      {1, nil} =
        Repo.update_all(
          from(report in IntelReport, where: report.id == ^older.id),
          set: [updated_at: ~U[2026-03-20 00:00:00.000000Z]]
        )

      {1, nil} =
        Repo.update_all(
          from(report in IntelReport, where: report.id == ^newer.id),
          set: [updated_at: ~U[2026-03-21 00:00:00.000000Z]]
        )

      reports = Intel.list_intel(context.tribe_id, intel_opts(context))

      assert Enum.map(reports, & &1.id) == [newer.id, older.id]
    end

    test "list_intel excludes reports from other tribes", context do
      own_report =
        insert_location_report!(%{
          tribe_id: context.tribe_id,
          assembly_id: context.assembly_id,
          notes: "Own tribe report"
        })

      _other_report =
        insert_location_report!(%{
          tribe_id: context.other_tribe_id,
          assembly_id: "0xassembly-other",
          notes: "Other tribe report"
        })

      reports = Intel.list_intel(context.tribe_id, intel_opts(context))

      assert Enum.map(reports, & &1.id) == [own_report.id]
      refute Enum.any?(reports, &(&1.tribe_id == context.other_tribe_id))
    end

    test "full workflow: report location, list intel, verify report present", context do
      assert {:ok, %IntelReport{} = report} =
               Intel.report_location(valid_location_params(context), intel_opts(context))

      reports = Intel.list_intel(context.tribe_id, intel_opts(context))

      assert Enum.map(reports, & &1.id) == [report.id]
      assert Enum.map(reports, & &1.solar_system_id) == [30_001_042]
    end
  end

  describe "authorized tribe scope enforcement" do
    test "CTX_Intel rejects mismatched authorized tribe scope", context do
      unauthorized_opts = intel_opts(context, authorized_tribe_id: context.other_tribe_id)

      assert Intel.report_location(valid_location_params(context), unauthorized_opts) ==
               {:error, :unauthorized}

      assert Intel.report_scouting(valid_scouting_params(context), unauthorized_opts) ==
               {:error, :unauthorized}

      assert Intel.list_intel(context.tribe_id, unauthorized_opts) == []
      assert Intel.get_location(context.tribe_id, context.assembly_id, unauthorized_opts) == nil

      report =
        insert_location_report!(%{
          tribe_id: context.tribe_id,
          assembly_id: context.assembly_id
        })

      assert Intel.delete_intel(
               report.id,
               %{
                 tribe_id: context.tribe_id,
                 reported_by: report.reported_by,
                 is_leader_or_operator: false
               },
               unauthorized_opts
             ) == {:error, :unauthorized}

      assert :ok = Intel.load_cache(context.tribe_id, unauthorized_opts)

      assert Cache.get(context.tables.intel, {:location, context.tribe_id, context.assembly_id}) ==
               nil
    end
  end

  describe "get_location/3" do
    test "get_location returns cached location report", context do
      report =
        insert_location_report!(%{
          tribe_id: context.tribe_id,
          assembly_id: context.assembly_id
        })

      Cache.put(context.tables.intel, {:location, context.tribe_id, context.assembly_id}, report)

      assert Intel.get_location(context.tribe_id, context.assembly_id, intel_opts(context)) ==
               report
    end

    test "get_location falls back to database on cache miss", context do
      report =
        insert_location_report!(%{
          tribe_id: context.tribe_id,
          assembly_id: context.assembly_id
        })

      assert Intel.get_location(context.tribe_id, context.assembly_id, intel_opts(context)) ==
               report

      assert Cache.get(context.tables.intel, {:location, context.tribe_id, context.assembly_id}) ==
               report
    end

    test "get_location returns nil for unreported assembly", context do
      assert Intel.get_location(context.tribe_id, "0xassembly-missing", intel_opts(context)) ==
               nil
    end
  end

  describe "delete_intel/3" do
    test "delete_intel succeeds for report author", context do
      report =
        insert_location_report!(%{
          tribe_id: context.tribe_id,
          assembly_id: context.assembly_id
        })

      Cache.put(context.tables.intel, {:location, context.tribe_id, context.assembly_id}, report)

      assert :ok =
               Intel.delete_intel(
                 report.id,
                 %{
                   tribe_id: context.tribe_id,
                   reported_by: report.reported_by,
                   is_leader_or_operator: false
                 },
                 intel_opts(context)
               )

      assert Repo.get(IntelReport, report.id) == nil

      assert Cache.get(context.tables.intel, {:location, context.tribe_id, context.assembly_id}) ==
               nil
    end

    test "delete_intel rejects non-author non-leader", context do
      report =
        insert_location_report!(%{
          tribe_id: context.tribe_id,
          assembly_id: context.assembly_id,
          reported_by: "0xauthor"
        })

      assert Intel.delete_intel(
               report.id,
               %{
                 tribe_id: context.tribe_id,
                 reported_by: "0xintruder",
                 is_leader_or_operator: false
               },
               intel_opts(context)
             ) == {:error, :unauthorized}

      assert Repo.get(IntelReport, report.id).id == report.id
    end

    test "delete_intel succeeds for leader or operator", context do
      report =
        insert_location_report!(%{
          tribe_id: context.tribe_id,
          assembly_id: context.assembly_id,
          reported_by: "0xauthor"
        })

      assert :ok =
               Intel.delete_intel(
                 report.id,
                 %{
                   tribe_id: context.tribe_id,
                   reported_by: "0xleader",
                   is_leader_or_operator: true
                 },
                 intel_opts(context)
               )

      assert Repo.get(IntelReport, report.id) == nil
    end

    test "delete_intel returns not_found for unknown id", context do
      assert Intel.delete_intel(
               Ecto.UUID.generate(),
               %{
                 tribe_id: context.tribe_id,
                 reported_by: "0xauthor",
                 is_leader_or_operator: false
               },
               intel_opts(context)
             ) == {:error, :not_found}
    end

    test "delete_intel blocks cross-tribe deletion", context do
      report =
        insert_location_report!(%{
          tribe_id: context.other_tribe_id,
          assembly_id: "0xassembly-other"
        })

      assert Intel.delete_intel(
               report.id,
               %{
                 tribe_id: context.tribe_id,
                 reported_by: report.reported_by,
                 is_leader_or_operator: true
               },
               intel_opts(context)
             ) == {:error, :unauthorized}

      assert Repo.get(IntelReport, report.id).id == report.id
    end

    test "delete_intel broadcasts intel_deleted on PubSub", context do
      report =
        insert_location_report!(%{
          tribe_id: context.tribe_id,
          assembly_id: context.assembly_id
        })

      Cache.put(context.tables.intel, {:location, context.tribe_id, context.assembly_id}, report)

      assert :ok =
               Intel.delete_intel(
                 report.id,
                 %{
                   tribe_id: context.tribe_id,
                   reported_by: report.reported_by,
                   is_leader_or_operator: false
                 },
                 intel_opts(context)
               )

      report_id = report.id
      tribe_id = context.tribe_id

      assert_receive {:intel_deleted, %IntelReport{id: ^report_id, tribe_id: ^tribe_id}}
    end
  end

  describe "load_cache/2" do
    test "load_cache populates ETS with location reports from database", context do
      cached_one =
        insert_location_report!(%{
          tribe_id: context.tribe_id,
          assembly_id: context.assembly_id,
          notes: "Cached one"
        })

      cached_two =
        insert_location_report!(%{
          tribe_id: context.tribe_id,
          assembly_id: "0xassembly-2",
          notes: "Cached two"
        })

      _scouting =
        insert_scouting_report!(%{
          tribe_id: context.tribe_id,
          notes: "Do not cache"
        })

      _other_tribe =
        insert_location_report!(%{
          tribe_id: context.other_tribe_id,
          assembly_id: "0xassembly-other"
        })

      assert :ok = Intel.load_cache(context.tribe_id, intel_opts(context))

      assert Cache.get(context.tables.intel, {:location, context.tribe_id, context.assembly_id}) ==
               cached_one

      assert Cache.get(context.tables.intel, {:location, context.tribe_id, "0xassembly-2"}) ==
               cached_two

      assert Cache.get(
               context.tables.intel,
               {:location, context.other_tribe_id, "0xassembly-other"}
             ) ==
               nil
    end
  end

  defp intel_opts(context, overrides \\ []) do
    Keyword.merge(
      [
        tables: context.tables,
        pubsub: context.pubsub,
        authorized_tribe_id: context.tribe_id
      ],
      overrides
    )
  end

  defp valid_location_params(context, overrides \\ %{}) do
    Map.merge(
      %{
        tribe_id: context.tribe_id,
        assembly_id: context.assembly_id,
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

  defp valid_scouting_params(context, overrides \\ %{}) do
    Map.merge(
      %{
        tribe_id: context.tribe_id,
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

  defp insert_location_report!(attrs) do
    %IntelReport{}
    |> IntelReport.location_changeset(location_seed_params(attrs))
    |> Repo.insert!()
  end

  defp insert_scouting_report!(attrs) do
    %IntelReport{}
    |> IntelReport.scouting_changeset(scouting_seed_params(attrs))
    |> Repo.insert!()
  end

  defp location_seed_params(overrides) do
    Map.merge(
      %{
        tribe_id: 77,
        assembly_id: "0xassembly-seed",
        solar_system_id: 30_001_042,
        label: "Foothold",
        notes: "Seeded location report.",
        reported_by: "0xabc123",
        reported_by_name: "Scout Prime",
        reported_by_character_id: "0xcharacter-1"
      },
      overrides
    )
  end

  defp scouting_seed_params(overrides) do
    Map.merge(
      %{
        tribe_id: 77,
        assembly_id: nil,
        solar_system_id: 30_001_042,
        label: "Advance patrol",
        notes: "Seeded scouting report.",
        reported_by: "0xabc123",
        reported_by_name: "Scout Prime",
        reported_by_character_id: "0xcharacter-1"
      },
      overrides
    )
  end

  defp unique_pubsub_name do
    :"intel_pubsub_#{System.unique_integer([:positive])}"
  end

  defp intel_topic(tribe_id), do: "intel:#{tribe_id}"
end
