defmodule Sigil.AlertsTest do
  @moduledoc """
  Covers the packet 1 alerts context contract from the approved spec.
  """

  use Sigil.DataCase, async: true

  alias Sigil.Alerts, as: AlertsContext
  alias Sigil.Alerts.{Alert, WebhookConfig}
  alias Sigil.Repo

  setup do
    pubsub = unique_pubsub_name()
    start_supervised!({Phoenix.PubSub, name: pubsub})

    {:ok, pubsub: pubsub}
  end

  describe "create_alert/2" do
    test "creates alert with valid attributes", %{pubsub: pubsub} do
      # Omit status from attrs — context must force status to "new"
      attrs = valid_alert_attrs() |> Map.delete("status")

      assert {:ok, %{__struct__: Alert} = alert} =
               AlertsContext.create_alert(attrs, pubsub: pubsub)

      assert alert.status == "new"
      assert alert.type == attrs["type"]
      assert alert.severity == attrs["severity"]
      assert alert.assembly_id == attrs["assembly_id"]
      assert alert.account_address == attrs["account_address"]
      assert alert.message == attrs["message"]
    end

    test "broadcasts alert_created on account topic", %{pubsub: pubsub} do
      attrs = valid_alert_attrs()
      :ok = Phoenix.PubSub.subscribe(pubsub, "alerts:#{attrs["account_address"]}")

      assert {:ok, %{__struct__: Alert} = alert} =
               AlertsContext.create_alert(attrs, pubsub: pubsub)

      alert_id = alert.id
      assert_receive {:alert_created, %{__struct__: Alert, id: ^alert_id}}
    end

    test "returns duplicate for active alert", %{pubsub: pubsub} do
      attrs = valid_alert_attrs(%{"assembly_id" => "assembly-duplicate", "type" => "fuel_low"})
      insert_alert!(attrs)

      assert AlertsContext.create_alert(attrs, pubsub: pubsub) == {:ok, :duplicate}
    end

    test "returns cooldown for recently dismissed alert", %{pubsub: pubsub} do
      attrs =
        valid_alert_attrs(%{"assembly_id" => "assembly-cooldown", "type" => "fuel_critical"})

      insert_alert!(
        Map.merge(attrs, %{
          "status" => "dismissed",
          "dismissed_at" => DateTime.add(DateTime.utc_now(), -30, :second)
        })
      )

      assert AlertsContext.create_alert(attrs, pubsub: pubsub, cooldown_ms: 60_000) ==
               {:ok, :cooldown}
    end

    test "creates new alert after cooldown expires", %{pubsub: pubsub} do
      attrs =
        valid_alert_attrs(%{"assembly_id" => "assembly-after-cooldown", "type" => "fuel_low"})

      insert_alert!(
        Map.merge(attrs, %{
          "status" => "dismissed",
          "dismissed_at" => DateTime.add(DateTime.utc_now(), -3_601, :second)
        })
      )

      assert {:ok, %{__struct__: Alert} = alert} =
               AlertsContext.create_alert(attrs, pubsub: pubsub, cooldown_ms: 3_600_000)

      assert alert.status == "new"
      assert alert.id
    end

    test "returns changeset error for invalid attributes", %{pubsub: pubsub} do
      assert {:error, changeset} = AlertsContext.create_alert(%{}, pubsub: pubsub)
      assert errors_on(changeset).type == ["can't be blank"]
    end
  end

  describe "list_alerts/2" do
    test "lists account alerts newest first" do
      older =
        insert_alert!(
          valid_alert_attrs(%{"account_address" => "0xaccount-list", "message" => "older"})
        )

      newer =
        insert_alert!(
          valid_alert_attrs(%{"account_address" => "0xaccount-list", "message" => "newer"})
        )

      _other =
        insert_alert!(
          valid_alert_attrs(%{"account_address" => "0xother-account", "message" => "other"})
        )

      alerts = AlertsContext.list_alerts([account_address: "0xaccount-list"], [])

      assert Enum.map(alerts, & &1.id) == [newer.id, older.id]
      refute Enum.any?(alerts, &(&1.account_address == "0xother-account"))
    end

    test "filters alerts by status" do
      account = "0xaccount-status"
      insert_alert!(valid_alert_attrs(%{"account_address" => account, "status" => "new"}))

      insert_alert!(
        valid_alert_attrs(%{"account_address" => account, "status" => "acknowledged"})
      )

      insert_alert!(valid_alert_attrs(%{"account_address" => account, "status" => "dismissed"}))

      alerts =
        AlertsContext.list_alerts([account_address: account, status: ["new", "acknowledged"]], [])

      assert Enum.map(alerts, & &1.status) == ["acknowledged", "new"]
      refute Enum.any?(alerts, &(&1.status == "dismissed"))
    end
  end

  describe "get_alert/2" do
    test "returns alert by id" do
      alert = insert_alert!()
      alert_id = alert.id

      assert %{__struct__: Alert, id: ^alert_id} = AlertsContext.get_alert(alert.id, [])
    end
  end

  describe "acknowledge_alert/2" do
    test "acknowledges new alert", %{pubsub: pubsub} do
      alert = insert_alert!(%{"status" => "new"})

      assert {:ok, %{__struct__: Alert} = acknowledged} =
               AlertsContext.acknowledge_alert(alert.id, pubsub: pubsub)

      assert acknowledged.status == "acknowledged"
      assert Repo.get!(Alert, alert.id).status == "acknowledged"
    end

    test "acknowledge dismissed alert is idempotent", %{pubsub: pubsub} do
      dismissed_at = DateTime.add(DateTime.utc_now(), -300, :second)
      alert = insert_alert!(%{"status" => "dismissed", "dismissed_at" => dismissed_at})

      assert {:ok, %{__struct__: Alert} = same_alert} =
               AlertsContext.acknowledge_alert(alert.id, pubsub: pubsub)

      assert same_alert.status == "dismissed"
      assert same_alert.dismissed_at == dismissed_at
    end

    test "acknowledge already-acknowledged alert is idempotent", %{pubsub: pubsub} do
      alert = insert_alert!(%{"status" => "acknowledged"})

      assert {:ok, %{__struct__: Alert} = same_alert} =
               AlertsContext.acknowledge_alert(alert.id, pubsub: pubsub)

      assert same_alert.id == alert.id
      assert same_alert.status == "acknowledged"
    end

    test "broadcasts alert_acknowledged on account topic", %{pubsub: pubsub} do
      alert = insert_alert!()
      :ok = Phoenix.PubSub.subscribe(pubsub, "alerts:#{alert.account_address}")

      assert {:ok, %{id: id}} = AlertsContext.acknowledge_alert(alert.id, pubsub: pubsub)
      assert_receive {:alert_acknowledged, %{__struct__: Alert, id: ^id}}
    end

    test "returns not_found for unknown alert id", %{pubsub: pubsub} do
      assert AlertsContext.acknowledge_alert(-1, pubsub: pubsub) == {:error, :not_found}
    end
  end

  describe "dismiss_alert/2" do
    test "dismisses alert and stores dismissed_at", %{pubsub: pubsub} do
      alert = insert_alert!(%{"status" => "acknowledged"})

      assert {:ok, %{__struct__: Alert} = dismissed} =
               AlertsContext.dismiss_alert(alert.id, pubsub: pubsub)

      assert dismissed.status == "dismissed"
      assert %DateTime{} = dismissed.dismissed_at
      assert Repo.get!(Alert, alert.id).dismissed_at == dismissed.dismissed_at
    end

    test "broadcasts alert_dismissed on account topic", %{pubsub: pubsub} do
      alert = insert_alert!()
      :ok = Phoenix.PubSub.subscribe(pubsub, "alerts:#{alert.account_address}")

      assert {:ok, %{id: id}} = AlertsContext.dismiss_alert(alert.id, pubsub: pubsub)
      assert_receive {:alert_dismissed, %{__struct__: Alert, id: ^id}}
    end

    test "re-dismiss preserves original dismissed_at", %{pubsub: pubsub} do
      dismissed_at = DateTime.add(DateTime.utc_now(), -600, :second)
      alert = insert_alert!(%{"status" => "dismissed", "dismissed_at" => dismissed_at})

      assert {:ok, %{__struct__: Alert} = same_alert} =
               AlertsContext.dismiss_alert(alert.id, pubsub: pubsub)

      assert same_alert.status == "dismissed"
      assert same_alert.dismissed_at == dismissed_at
    end

    test "returns not_found for unknown alert id", %{pubsub: pubsub} do
      assert AlertsContext.dismiss_alert(-1, pubsub: pubsub) == {:error, :not_found}
    end
  end

  describe "query helpers" do
    test "counts unread alerts for account" do
      account = "0xaccount-unread"
      insert_alert!(valid_alert_attrs(%{"account_address" => account, "status" => "new"}))
      insert_alert!(valid_alert_attrs(%{"account_address" => account, "status" => "new"}))

      insert_alert!(
        valid_alert_attrs(%{"account_address" => account, "status" => "acknowledged"})
      )

      insert_alert!(
        valid_alert_attrs(%{"account_address" => "0xother-unread", "status" => "new"})
      )

      assert AlertsContext.unread_count(account, []) == 2
    end

    test "active_alert_exists returns true for active alert" do
      assembly_id = "assembly-active-check"
      type = "fuel_low"

      insert_alert!(%{"assembly_id" => assembly_id, "type" => type, "status" => "acknowledged"})

      # Dismissed alert of same assembly but different type
      insert_alert!(%{
        "assembly_id" => assembly_id,
        "type" => "fuel_critical",
        "status" => "dismissed"
      })

      assert AlertsContext.active_alert_exists?(assembly_id, type, [])
      # Different type with no alert at all → false
      refute AlertsContext.active_alert_exists?(assembly_id, "assembly_offline", [])
      # Dismissed same-type alert on a different assembly → false
      dismissed_assembly = "assembly-dismissed-only"

      insert_alert!(%{
        "assembly_id" => dismissed_assembly,
        "type" => "fuel_low",
        "status" => "dismissed"
      })

      refute AlertsContext.active_alert_exists?(dismissed_assembly, "fuel_low", [])
    end
  end

  describe "webhook config" do
    test "gets webhook config for tribe" do
      config = insert_webhook_config!(%{"tribe_id" => 314})
      config_id = config.id

      assert %{__struct__: WebhookConfig, id: ^config_id} =
               AlertsContext.get_webhook_config(314, [])
    end

    test "upserts webhook config for tribe" do
      insert_webhook_config!(%{
        "tribe_id" => 271,
        "webhook_url" => "https://discord.example/webhooks/original",
        "enabled" => true
      })

      assert {:ok, %{__struct__: WebhookConfig} = config} =
               AlertsContext.upsert_webhook_config(
                 271,
                 %{
                   "webhook_url" => "https://discord.example/webhooks/updated",
                   "enabled" => false,
                   "service_type" => "discord"
                 },
                 []
               )

      assert config.tribe_id == 271
      assert config.webhook_url == "https://discord.example/webhooks/updated"
      refute config.enabled

      assert Repo.aggregate(from(w in WebhookConfig, where: w.tribe_id == 271), :count, :id) == 1
    end
  end

  describe "purge_old_dismissed/2" do
    test "purges dismissed alerts older than threshold" do
      old_dismissed =
        insert_alert!(%{
          "status" => "dismissed",
          "dismissed_at" => DateTime.add(DateTime.utc_now(), -3_456_000, :second)
        })

      recent_dismissed =
        insert_alert!(%{
          "status" => "dismissed",
          "dismissed_at" => DateTime.add(DateTime.utc_now(), -432_000, :second)
        })

      active_alert = insert_alert!(%{"status" => "new"})

      assert AlertsContext.purge_old_dismissed(30, []) == {1, nil}

      refute Repo.get(Alert, old_dismissed.id)
      assert Repo.get(Alert, recent_dismissed.id)
      assert Repo.get(Alert, active_alert.id)
    end
  end

  describe "concurrency" do
    test "concurrent duplicate insert returns duplicate", %{
      pubsub: pubsub,
      sandbox_owner: sandbox_owner
    } do
      attrs = valid_alert_attrs(%{"assembly_id" => "assembly-race", "type" => "fuel_critical"})
      parent = self()

      tasks =
        for _ <- 1..2 do
          task =
            Task.async(fn ->
              send(parent, {:task_ready, self()})

              receive do
                :go -> AlertsContext.create_alert(attrs, pubsub: pubsub)
              end
            end)

          Ecto.Adapters.SQL.Sandbox.allow(Repo, sandbox_owner, task.pid)
          task_pid = task.pid
          assert_receive {:task_ready, ^task_pid}
          task
        end

      Enum.each(tasks, &send(&1.pid, :go))
      results = Enum.map(tasks, &Task.await(&1, 5_000))

      assert Enum.count(results, &match?({:ok, %{__struct__: Alert}}, &1)) == 1
      assert Enum.count(results, &(&1 == {:ok, :duplicate})) == 1
      assert Repo.aggregate(Alert, :count, :id) == 1
    end
  end

  @tag :acceptance
  test "alert lifecycle enforces active dedup and cooldown", %{pubsub: pubsub} do
    attrs = valid_alert_attrs(%{"assembly_id" => "assembly-acceptance", "type" => "fuel_low"})

    assert {:ok, %{__struct__: Alert} = first_alert} =
             AlertsContext.create_alert(attrs, pubsub: pubsub, cooldown_ms: 5_000)

    assert AlertsContext.create_alert(attrs, pubsub: pubsub, cooldown_ms: 5_000) ==
             {:ok, :duplicate}

    assert {:ok, %{__struct__: Alert} = dismissed_alert} =
             AlertsContext.dismiss_alert(first_alert.id, pubsub: pubsub)

    assert %DateTime{} = dismissed_alert.dismissed_at

    assert AlertsContext.create_alert(attrs, pubsub: pubsub, cooldown_ms: 5_000) ==
             {:ok, :cooldown}

    expired_at = DateTime.add(dismissed_alert.dismissed_at, -10, :second)

    Repo.update_all(
      from(a in Alert, where: a.id == ^dismissed_alert.id),
      set: [dismissed_at: expired_at, updated_at: expired_at]
    )

    assert {:ok, %{__struct__: Alert} = recreated_alert} =
             AlertsContext.create_alert(attrs, pubsub: pubsub, cooldown_ms: 5_000)

    active_alerts =
      AlertsContext.list_alerts(
        [account_address: attrs["account_address"], status: ["new", "acknowledged"]],
        []
      )

    assert Enum.map(active_alerts, & &1.id) == [recreated_alert.id]
    refute recreated_alert.id == first_alert.id
    refute Enum.any?(active_alerts, &(&1.status == "dismissed"))
  end

  defp insert_alert!(overrides \\ %{}) do
    new_alert_struct()
    |> Alert.changeset(valid_alert_attrs(overrides))
    |> Repo.insert!()
  end

  defp insert_webhook_config!(overrides) do
    new_webhook_struct()
    |> WebhookConfig.changeset(valid_webhook_attrs(overrides))
    |> Repo.insert!()
  end

  defp new_alert_struct do
    apply(Alert, :__struct__, [])
  end

  defp new_webhook_struct do
    apply(WebhookConfig, :__struct__, [])
  end

  defp unique_pubsub_name do
    :"alerts_pubsub_#{System.unique_integer([:positive])}"
  end

  defp valid_alert_attrs(overrides \\ %{}) do
    unique = System.unique_integer([:positive])

    Map.merge(
      %{
        "type" => "fuel_low",
        "severity" => "warning",
        "status" => "new",
        "assembly_id" => "assembly-#{unique}",
        "assembly_name" => "Assembly #{unique}",
        "account_address" => "0xaccount#{unique}",
        "tribe_id" => 42,
        "message" => "Fuel is trending low",
        "metadata" => %{"source" => "monitor"}
      },
      overrides
    )
  end

  defp valid_webhook_attrs(overrides) do
    unique = System.unique_integer([:positive])

    Map.merge(
      %{
        "tribe_id" => unique,
        "webhook_url" => "https://discord.example/webhooks/#{unique}",
        "service_type" => "discord",
        "enabled" => true
      },
      overrides
    )
  end
end
