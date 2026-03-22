defmodule Sigil.Alerts.WebhookNotifier.DiscordTest do
  @moduledoc """
  Captures the packet 2 Discord webhook delivery contract.
  """

  use ExUnit.Case, async: true

  @compile {:no_warn_undefined, Sigil.Alerts.WebhookNotifier.Discord}

  import Plug.Conn

  alias Sigil.Alerts.Alert
  alias Sigil.Alerts.WebhookConfig
  alias Sigil.Alerts.WebhookNotifier.Discord

  describe "deliver/3" do
    test "delivers alert to Discord webhook successfully" do
      stub_name = stub_name(:deliver_success)

      Req.Test.expect(stub_name, fn conn ->
        payload = request_body(conn)

        assert payload["embeds"] |> length() == 1
        assert get_embed(payload, "title") == "Assembly Offline"
        assert get_embed(payload, "description") == "Gate Alpha has gone offline"

        Req.Test.json(conn, %{"ok" => true})
      end)

      assert :ok =
               Discord.deliver(
                 alert_fixture(type: "assembly_offline", severity: "critical"),
                 webhook_config_fixture(),
                 req_options: [plug: {Req.Test, stub_name}]
               )

      assert :ok = Req.Test.verify!(stub_name)
    end

    test "builds correct Discord embed JSON" do
      stub_name = stub_name(:embed_json)

      Req.Test.expect(stub_name, fn conn ->
        payload = request_body(conn)
        [embed] = payload["embeds"]

        assert embed["title"] == "Assembly Offline"
        assert embed["description"] == "Gate Alpha has gone offline"
        assert embed["color"] == 15_158_332
        assert embed["timestamp"] == "2026-03-21T04:45:05Z"
        assert embed["footer"] == %{"text" => "Sigil Alert System"}

        assert Enum.find(embed["fields"], &(&1["name"] == "Assembly")) == %{
                 "name" => "Assembly",
                 "value" => "Gate Alpha",
                 "inline" => true
               }

        assert Enum.find(embed["fields"], &(&1["name"] == "Type")) == %{
                 "name" => "Type",
                 "value" => "assembly_offline",
                 "inline" => true
               }

        assert Enum.find(embed["fields"], &(&1["name"] == "Severity")) == %{
                 "name" => "Severity",
                 "value" => "critical",
                 "inline" => true
               }

        Req.Test.json(conn, %{"ok" => true})
      end)

      assert :ok =
               Discord.deliver(
                 alert_fixture(type: "assembly_offline", severity: "critical"),
                 webhook_config_fixture(),
                 req_options: [plug: {Req.Test, stub_name}]
               )

      assert :ok = Req.Test.verify!(stub_name)
    end

    test "maps severity to correct embed color" do
      cases = [
        {"critical", 15_158_332},
        {"warning", 15_105_570},
        {"info", 3_447_003}
      ]

      Enum.each(cases, fn {severity, color} ->
        stub_name = stub_name({:severity, severity})

        Req.Test.expect(stub_name, fn conn ->
          assert get_embed(request_body(conn), "color") == color
          Req.Test.json(conn, %{"ok" => true})
        end)

        assert :ok =
                 Discord.deliver(
                   alert_fixture(type: "fuel_low", severity: severity),
                   webhook_config_fixture(),
                   req_options: [plug: {Req.Test, stub_name}]
                 )

        assert :ok = Req.Test.verify!(stub_name)
      end)
    end

    test "formats alert type as human-readable title" do
      cases = [
        {"fuel_low", "Fuel Low"},
        {"fuel_critical", "Fuel Critical"},
        {"assembly_offline", "Assembly Offline"},
        {"extension_changed", "Extension Changed"}
      ]

      Enum.each(cases, fn {type, expected_title} ->
        stub_name = stub_name({:title, type})

        Req.Test.expect(stub_name, fn conn ->
          assert get_embed(request_body(conn), "title") == expected_title
          Req.Test.json(conn, %{"ok" => true})
        end)

        assert :ok =
                 Discord.deliver(
                   alert_fixture(type: type),
                   webhook_config_fixture(),
                   req_options: [plug: {Req.Test, stub_name}]
                 )

        assert :ok = Req.Test.verify!(stub_name)
      end)
    end

    test "succeeds after 429 rate limit on retry" do
      stub_name = stub_name(:rate_limit_retry)
      parent = self()

      Req.Test.expect(stub_name, fn conn ->
        json_response(conn, 429, %{"retry_after" => 1.25})
      end)

      Req.Test.expect(stub_name, fn conn ->
        assert get_embed(request_body(conn), "title") == "Fuel Low"
        Req.Test.json(conn, %{"ok" => true})
      end)

      delay_fun = fn delay_ms ->
        send(parent, {:delay_called, delay_ms})
        :ok
      end

      assert :ok =
               Discord.deliver(
                 alert_fixture(type: "fuel_low", severity: "warning"),
                 webhook_config_fixture(),
                 req_options: [plug: {Req.Test, stub_name}],
                 delay_fun: delay_fun
               )

      assert_receive {:delay_called, 1_250}
      assert :ok = Req.Test.verify!(stub_name)
    end

    test "uses Retry-After header seconds for 429 retry" do
      stub_name = stub_name(:rate_limit_header_retry)
      parent = self()

      Req.Test.expect(stub_name, fn conn ->
        conn
        |> put_resp_header("retry-after", "1.25")
        |> json_response(429, %{"errors" => [%{"message" => "rate limited"}]})
      end)

      Req.Test.expect(stub_name, fn conn ->
        assert get_embed(request_body(conn), "title") == "Fuel Low"
        Req.Test.json(conn, %{"ok" => true})
      end)

      delay_fun = fn delay_ms ->
        send(parent, {:delay_called, delay_ms})
        :ok
      end

      assert :ok =
               Discord.deliver(
                 alert_fixture(type: "fuel_low", severity: "warning"),
                 webhook_config_fixture(),
                 req_options: [plug: {Req.Test, stub_name}],
                 delay_fun: delay_fun
               )

      assert_receive {:delay_called, 1_250}
      assert :ok = Req.Test.verify!(stub_name)
    end

    test "succeeds after 5xx server error on retry" do
      stub_name = stub_name(:server_retry)
      parent = self()

      Req.Test.expect(stub_name, fn conn ->
        json_response(conn, 503, %{"errors" => [%{"message" => "temporary failure"}]})
      end)

      Req.Test.expect(stub_name, fn conn ->
        assert get_embed(request_body(conn), "title") == "Fuel Critical"
        Req.Test.json(conn, %{"ok" => true})
      end)

      delay_fun = fn delay_ms ->
        send(parent, {:delay_called, delay_ms})
        :ok
      end

      assert :ok =
               Discord.deliver(
                 alert_fixture(type: "fuel_critical", severity: "critical"),
                 webhook_config_fixture(),
                 req_options: [plug: {Req.Test, stub_name}],
                 delay_fun: delay_fun
               )

      assert_receive {:delay_called, 2_000}
      assert :ok = Req.Test.verify!(stub_name)
    end

    test "returns webhook_failed after persistent 5xx" do
      stub_name = stub_name(:persistent_5xx)
      parent = self()

      Req.Test.expect(stub_name, fn conn ->
        json_response(conn, 502, %{"errors" => [%{"message" => "upstream down"}]})
      end)

      Req.Test.expect(stub_name, fn conn ->
        json_response(conn, 502, %{"errors" => [%{"message" => "still down"}]})
      end)

      delay_fun = fn delay_ms ->
        send(parent, {:delay_called, delay_ms})
        :ok
      end

      assert {:error, {:webhook_failed, 502}} =
               Discord.deliver(
                 alert_fixture(type: "fuel_critical", severity: "critical"),
                 webhook_config_fixture(),
                 req_options: [plug: {Req.Test, stub_name}],
                 delay_fun: delay_fun
               )

      assert_receive {:delay_called, 2_000}
      assert :ok = Req.Test.verify!(stub_name)
    end

    test "returns webhook_failed immediately on 4xx" do
      stub_name = stub_name(:client_error)
      parent = self()

      Req.Test.expect(stub_name, fn conn ->
        json_response(conn, 404, %{"errors" => [%{"message" => "not found"}]})
      end)

      delay_fun = fn delay_ms ->
        send(parent, {:delay_called, delay_ms})
        :ok
      end

      assert {:error, {:webhook_failed, 404}} =
               Discord.deliver(
                 alert_fixture(type: "extension_changed", severity: "info"),
                 webhook_config_fixture(),
                 req_options: [plug: {Req.Test, stub_name}],
                 delay_fun: delay_fun
               )

      refute_receive {:delay_called, _delay_ms}
      assert :ok = Req.Test.verify!(stub_name)
    end

    test "returns network_error on transport failure" do
      stub_name = stub_name(:network_error)

      Req.Test.stub(stub_name, fn conn ->
        Req.Test.transport_error(conn, :timeout)
      end)

      assert {:error, {:network_error, :timeout}} =
               Discord.deliver(
                 alert_fixture(type: "extension_changed", severity: "info"),
                 webhook_config_fixture(),
                 req_options: [plug: {Req.Test, stub_name}]
               )
    end
  end

  @tag :acceptance
  test "webhook delivery sends formatted Discord notification" do
    stub_name = stub_name(:acceptance)

    Req.Test.expect(stub_name, fn conn ->
      payload = request_body(conn)
      [embed] = payload["embeds"]

      assert embed["title"] == "Assembly Offline"
      assert embed["description"] == "Gate Alpha has gone offline"
      assert Enum.any?(embed["fields"], &(&1["value"] == "critical"))
      refute embed["description"] =~ "N/A"
      refute embed["description"] =~ "error"

      Req.Test.json(conn, %{"ok" => true})
    end)

    assert :ok =
             Discord.deliver(
               alert_fixture(type: "assembly_offline", severity: "critical"),
               webhook_config_fixture(),
               req_options: [plug: {Req.Test, stub_name}]
             )

    assert :ok = Req.Test.verify!(stub_name)
  end

  defp alert_fixture(overrides) do
    timestamp = ~U[2026-03-21 04:45:05Z]
    unique = System.unique_integer([:positive])

    base = %Alert{
      id: unique,
      type: "assembly_offline",
      severity: "warning",
      status: "new",
      assembly_id: "assembly-#{unique}",
      assembly_name: "Gate Alpha",
      account_address: "0xaccount#{unique}",
      tribe_id: 42,
      message: "Gate Alpha has gone offline",
      metadata: %{"previous_status" => "online"},
      inserted_at: timestamp,
      updated_at: timestamp
    }

    Enum.reduce(overrides, base, fn {key, value}, alert -> Map.put(alert, key, value) end)
  end

  defp webhook_config_fixture(overrides \\ []) do
    unique = System.unique_integer([:positive])

    base = %WebhookConfig{
      tribe_id: 42,
      webhook_url: "https://discord.example/webhooks/#{unique}",
      service_type: "discord",
      enabled: true
    }

    Enum.reduce(overrides, base, fn {key, value}, config -> Map.put(config, key, value) end)
  end

  defp request_body(conn) do
    {:ok, body, _conn} = read_body(conn)
    Jason.decode!(body)
  end

  defp get_embed(payload, key) do
    payload
    |> Map.fetch!("embeds")
    |> List.first()
    |> Map.fetch!(key)
  end

  defp json_response(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end

  defp stub_name(prefix), do: {prefix, System.unique_integer([:positive])}
end
