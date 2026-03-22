defmodule Sigil.Alerts.AlertTest do
  @moduledoc """
  Covers the packet 1 alert schema and migration contract from the approved spec.
  """

  use Sigil.DataCase, async: true

  alias Sigil.Alerts.{Alert, WebhookConfig}
  alias Sigil.Repo

  describe "Alert.changeset/2" do
    test "alert changeset accepts valid attributes" do
      changeset = Alert.changeset(new_alert_struct(), valid_alert_attrs())

      assert changeset.valid?
      assert get_change(changeset, :type) == "fuel_low"
      assert get_change(changeset, :severity) == "warning"
      assert get_change(changeset, :status) == "new"
    end

    test "alert changeset requires mandatory fields" do
      changeset = Alert.changeset(new_alert_struct(), %{})

      assert errors_on(changeset) == %{
               account_address: ["can't be blank"],
               assembly_id: ["can't be blank"],
               assembly_name: ["can't be blank"],
               message: ["can't be blank"],
               severity: ["can't be blank"],
               status: ["can't be blank"],
               type: ["can't be blank"]
             }
    end

    test "alert changeset rejects invalid type" do
      changeset = Alert.changeset(new_alert_struct(), valid_alert_attrs(%{"type" => "unknown"}))

      refute changeset.valid?
      assert errors_on(changeset).type == ["is invalid"]
    end

    test "alert changeset rejects invalid severity" do
      changeset =
        Alert.changeset(new_alert_struct(), valid_alert_attrs(%{"severity" => "urgent"}))

      refute changeset.valid?
      assert errors_on(changeset).severity == ["is invalid"]
    end

    test "alert changeset rejects invalid status" do
      changeset =
        Alert.changeset(new_alert_struct(), valid_alert_attrs(%{"status" => "resolved"}))

      refute changeset.valid?
      assert errors_on(changeset).status == ["is invalid"]
    end

    test "status changeset updates lifecycle fields" do
      dismissed_at = DateTime.utc_now()

      alert =
        new_alert_struct()
        |> Map.merge(%{
          status: "new",
          dismissed_at: nil,
          assembly_name: "Original assembly"
        })

      changeset =
        Alert.status_changeset(alert, %{
          "status" => "dismissed",
          "dismissed_at" => dismissed_at,
          "assembly_name" => "Ignored assembly name"
        })

      assert changeset.valid?
      assert changeset.changes == %{status: "dismissed", dismissed_at: dismissed_at}
      refute Map.has_key?(changeset.changes, :assembly_name)
    end
  end

  describe "WebhookConfig.changeset/2" do
    test "webhook config changeset accepts valid attributes" do
      changeset = WebhookConfig.changeset(new_webhook_struct(), valid_webhook_attrs())

      assert changeset.valid?
      assert get_change(changeset, :tribe_id) == 42
      assert get_change(changeset, :webhook_url) == "https://discord.example/webhooks/42"
      assert get_change(changeset, :service_type) == "discord"
    end

    test "webhook config changeset requires tribe and url" do
      changeset = WebhookConfig.changeset(new_webhook_struct(), %{})

      assert errors_on(changeset) == %{
               tribe_id: ["can't be blank"],
               webhook_url: ["can't be blank"]
             }
    end

    test "webhook config changeset rejects invalid service type" do
      changeset =
        WebhookConfig.changeset(
          new_webhook_struct(),
          valid_webhook_attrs(%{"service_type" => "slack"})
        )

      refute changeset.valid?
      assert errors_on(changeset).service_type == ["is invalid"]
    end
  end

  describe "alert persistence" do
    test "migration creates usable alert and webhook tables" do
      inserted_alert = insert_alert!()
      inserted_config = insert_webhook_config!()

      assert Repo.get(Alert, inserted_alert.id).assembly_id == inserted_alert.assembly_id
      assert Repo.get(WebhookConfig, inserted_config.id).tribe_id == inserted_config.tribe_id
    end

    test "partial unique index rejects duplicate active alerts" do
      inserted_alert =
        insert_alert!(%{"assembly_id" => "assembly-duplicate", "type" => "fuel_low"})

      assert_raise Ecto.ConstraintError, fn ->
        insert_alert!(%{
          "assembly_id" => inserted_alert.assembly_id,
          "type" => inserted_alert.type,
          "status" => "acknowledged",
          "message" => "Second active alert"
        })
      end
    end

    test "unique index rejects duplicate webhook tribe_id" do
      inserted_config = insert_webhook_config!(%{"tribe_id" => 777})

      assert_raise Ecto.ConstraintError, fn ->
        new_webhook_struct()
        |> WebhookConfig.changeset(%{
          "tribe_id" => inserted_config.tribe_id,
          "webhook_url" => "https://discord.example/webhooks/replaced",
          "service_type" => "discord",
          "enabled" => true
        })
        |> Repo.insert!()
      end
    end
  end

  defp insert_alert!(overrides \\ %{}) do
    new_alert_struct()
    |> Alert.changeset(valid_alert_attrs(overrides))
    |> Repo.insert!()
  end

  defp insert_webhook_config!(overrides \\ %{}) do
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

  defp valid_webhook_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        "tribe_id" => 42,
        "webhook_url" => "https://discord.example/webhooks/42",
        "service_type" => "discord",
        "enabled" => true
      },
      overrides
    )
  end
end
