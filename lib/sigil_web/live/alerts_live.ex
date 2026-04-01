defmodule SigilWeb.AlertsLive do
  @moduledoc """
  Account-scoped alerts feed with lifecycle actions and PubSub refreshes.
  """

  use SigilWeb, :live_view

  import SigilWeb.TransactionHelpers, only: [localnet_signer_address: 1]

  alias Sigil.{Alerts, Diplomacy}
  alias Sigil.Alerts.{Alert, WebhookConfig}

  @notifier Application.compile_env(:sigil, :webhook_notifier, Alerts.WebhookNotifier.Discord)

  @doc """
  Mounts the alerts feed for the authenticated account.
  """
  @impl true
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) ::
          {:ok, Phoenix.LiveView.Socket.t()}
  def mount(_params, _session, socket) do
    case socket.assigns.current_account do
      %{address: _address} ->
        socket =
          socket
          |> assign_base_state()
          |> load_alerts()
          |> load_unread_count()
          |> load_webhook_state()
          |> maybe_subscribe()

        {:ok, socket}

      _other ->
        {:ok, redirect(socket, to: ~p"/")}
    end
  end

  @doc false
  @impl true
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("acknowledge", %{"id" => id}, socket) do
    socket =
      case parse_id(id) do
        {:ok, alert_id} ->
          case Alerts.acknowledge_alert(alert_id,
                 pubsub: socket.assigns.pubsub,
                 authorized_account_address: socket.assigns.current_account.address
               ) do
            {:ok, _alert} ->
              socket
              |> refresh_loaded_window()
              |> load_unread_count()

            {:error, :not_found} ->
              put_flash(socket, :error, "Alert not found")
          end

        :error ->
          put_flash(socket, :error, "Alert not found")
      end

    {:noreply, socket}
  end

  def handle_event("dismiss", %{"id" => id}, socket) do
    socket =
      case parse_id(id) do
        {:ok, alert_id} ->
          case Alerts.dismiss_alert(alert_id,
                 pubsub: socket.assigns.pubsub,
                 authorized_account_address: socket.assigns.current_account.address
               ) do
            {:ok, _alert} ->
              socket
              |> refresh_loaded_window()
              |> load_unread_count()

            {:error, :not_found} ->
              put_flash(socket, :error, "Alert not found")
          end

        :error ->
          put_flash(socket, :error, "Alert not found")
      end

    {:noreply, socket}
  end

  def handle_event("toggle_dismissed", _params, socket) do
    socket =
      socket
      |> assign(:show_dismissed, !socket.assigns.show_dismissed)
      |> load_alerts()
      |> load_unread_count()

    {:noreply, socket}
  end

  def handle_event("load_more", _params, %{assigns: %{alerts: []}} = socket) do
    {:noreply, assign(socket, has_more: false)}
  end

  def handle_event("load_more", _params, socket) do
    before_id = socket.assigns.alerts |> List.last() |> Map.fetch!(:id)

    new_alerts =
      socket
      |> current_filters()
      |> Keyword.put(:before_id, before_id)
      |> Keyword.put(:limit, socket.assigns.page_limit)
      |> Alerts.list_alerts([])

    {:noreply,
     assign(socket,
       alerts: socket.assigns.alerts ++ new_alerts,
       loaded_count: socket.assigns.loaded_count + length(new_alerts),
       has_more: length(new_alerts) == socket.assigns.page_limit
     )}
  end

  def handle_event("save_webhook", %{"webhook" => params}, socket) do
    if socket.assigns.is_leader do
      {:noreply, save_webhook(socket, params)}
    else
      {:noreply, put_flash(socket, :error, "Only the tribe leader can configure webhooks")}
    end
  end

  def handle_event("toggle_webhook", _params, socket) do
    if socket.assigns.is_leader do
      {:noreply, toggle_webhook(socket)}
    else
      {:noreply, put_flash(socket, :error, "Only the tribe leader can configure webhooks")}
    end
  end

  def handle_event("test_webhook", _params, socket) do
    if socket.assigns.is_leader do
      {:noreply, test_webhook(socket)}
    else
      {:noreply, put_flash(socket, :error, "Only the tribe leader can test webhooks")}
    end
  end

  @doc false
  @impl true
  @spec handle_info(term(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_info({:alert_created, _alert}, socket) do
    {:noreply, socket |> refresh_loaded_window() |> load_unread_count()}
  end

  def handle_info({:alert_acknowledged, _alert}, socket) do
    {:noreply, socket |> refresh_loaded_window() |> load_unread_count()}
  end

  def handle_info({:alert_dismissed, _alert}, socket) do
    {:noreply, socket |> refresh_loaded_window() |> load_unread_count()}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  @doc false
  @impl true
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <section class="relative overflow-hidden px-4 py-12 sm:px-6 lg:px-8">
      <div class="mx-auto max-w-6xl space-y-8">
        <SigilWeb.AlertsLive.Components.alerts_header
          unread_count={@unread_count}
          show_dismissed={@show_dismissed}
        />

        <SigilWeb.AlertsLive.Components.webhook_panel
          is_leader={@is_leader}
          webhook_config={@webhook_config}
          webhook_form={@webhook_form}
        />

        <SigilWeb.AlertsLive.Components.alerts_feed
          alerts={@alerts}
          has_more={@has_more}
          active_character={@active_character}
        />
      </div>
    </section>
    """
  end

  @spec assign_base_state(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp assign_base_state(socket) do
    assign(socket,
      page_title: "Alerts",
      alerts: [],
      unread_count: 0,
      show_dismissed: false,
      has_more: false,
      page_limit: 25,
      loaded_count: 0,
      is_leader: false,
      webhook_config: nil,
      webhook_form: webhook_form(nil)
    )
  end

  @spec maybe_subscribe(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp maybe_subscribe(socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(
        socket.assigns.pubsub,
        Alerts.topic(socket.assigns.current_account.address)
      )
    end

    socket
  end

  @spec load_alerts(Phoenix.LiveView.Socket.t(), pos_integer() | nil) ::
          Phoenix.LiveView.Socket.t()
  defp load_alerts(socket, limit \\ nil) do
    limit = limit || socket.assigns.page_limit

    alerts =
      socket
      |> current_filters()
      |> Keyword.put(:limit, limit)
      |> Alerts.list_alerts([])

    assign(socket,
      alerts: alerts,
      loaded_count: length(alerts),
      has_more: length(alerts) == limit
    )
  end

  @spec load_unread_count(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp load_unread_count(socket) do
    assign(socket, :unread_count, Alerts.unread_count(socket.assigns.current_account.address, []))
  end

  @spec refresh_loaded_window(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp refresh_loaded_window(socket), do: load_alerts(socket, visible_limit(socket))

  @spec visible_limit(Phoenix.LiveView.Socket.t()) :: pos_integer()
  defp visible_limit(socket), do: max(socket.assigns.loaded_count, 1)

  @spec current_filters(Phoenix.LiveView.Socket.t()) :: keyword()
  defp current_filters(socket) do
    filters = [account_address: socket.assigns.current_account.address]

    if socket.assigns.show_dismissed do
      filters
    else
      Keyword.put(filters, :status, ["new", "acknowledged"])
    end
  end

  @spec active_tribe_id(Phoenix.LiveView.Socket.t()) :: integer() | nil
  defp active_tribe_id(socket) do
    case socket.assigns[:active_character] do
      %{tribe_id: tribe_id} when is_integer(tribe_id) and tribe_id > 0 -> tribe_id
      _other -> socket.assigns.current_account.tribe_id
    end
  end

  @spec load_webhook_state(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp load_webhook_state(socket) do
    tribe_id = active_tribe_id(socket)
    cache_tables = socket.assigns[:cache_tables]

    if is_integer(tribe_id) and is_map(cache_tables) and is_map_key(cache_tables, :standings) do
      opts = [
        tables: cache_tables,
        sender:
          localnet_signer_address(socket.assigns.world) || socket.assigns.current_account.address,
        tribe_id: tribe_id,
        world: socket.assigns.world
      ]

      if connected?(socket) and is_nil(Diplomacy.get_active_custodian(opts)) do
        Diplomacy.discover_custodian(tribe_id, opts)
      end

      is_leader = Diplomacy.leader?(opts)
      config = if is_leader, do: Alerts.get_webhook_config(tribe_id, [])

      assign(socket,
        is_leader: is_leader,
        webhook_config: config,
        webhook_form: webhook_form(config)
      )
    else
      socket
    end
  end

  @spec save_webhook(Phoenix.LiveView.Socket.t(), map()) :: Phoenix.LiveView.Socket.t()
  defp save_webhook(socket, params) do
    tribe_id = active_tribe_id(socket)
    url = Map.get(params, "webhook_url", "")

    attrs = %{
      "webhook_url" => url,
      "enabled" => current_webhook_enabled(socket.assigns.webhook_config)
    }

    case Alerts.upsert_webhook_config(tribe_id, attrs, []) do
      {:ok, _config} ->
        socket
        |> put_flash(:info, "Webhook configuration saved")
        |> load_webhook_state()

      {:error, %Ecto.Changeset{}} ->
        socket
        |> put_flash(:error, "Webhook URL is required")
        |> assign(:webhook_form, webhook_form(%{"webhook_url" => url}))
    end
  end

  @spec toggle_webhook(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp toggle_webhook(%{assigns: %{webhook_config: %WebhookConfig{} = config}} = socket) do
    tribe_id = active_tribe_id(socket)

    attrs = %{
      "webhook_url" => config.webhook_url,
      "enabled" => !config.enabled
    }

    case Alerts.upsert_webhook_config(tribe_id, attrs, []) do
      {:ok, _updated} ->
        socket
        |> put_flash(:info, webhook_toggle_message(!config.enabled))
        |> load_webhook_state()

      {:error, %Ecto.Changeset{}} ->
        put_flash(socket, :error, "Unable to update webhook delivery state")
    end
  end

  defp toggle_webhook(socket) do
    put_flash(socket, :error, "Set a webhook URL before toggling delivery")
  end

  @spec current_webhook_enabled(WebhookConfig.t() | nil) :: boolean()
  defp current_webhook_enabled(%WebhookConfig{enabled: enabled}), do: enabled
  defp current_webhook_enabled(_config), do: true

  @spec webhook_toggle_message(boolean()) :: String.t()
  defp webhook_toggle_message(true), do: "Webhook delivery enabled"
  defp webhook_toggle_message(false), do: "Webhook delivery disabled"

  @spec webhook_form(WebhookConfig.t() | map() | nil) :: Phoenix.HTML.Form.t()
  defp webhook_form(%WebhookConfig{webhook_url: url}),
    do: to_form(%{"webhook_url" => url || ""}, as: :webhook)

  defp webhook_form(%{"webhook_url" => _} = params), do: to_form(params, as: :webhook)
  defp webhook_form(_config), do: to_form(%{"webhook_url" => ""}, as: :webhook)

  @spec test_webhook(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp test_webhook(%{assigns: %{webhook_config: %WebhookConfig{} = config}} = socket) do
    test_alert = %Alert{
      type: "fuel_low",
      severity: "info",
      status: "new",
      assembly_id: nil,
      assembly_name: "Test Delivery",
      account_address: socket.assigns.current_account.address,
      tribe_id: active_tribe_id(socket),
      message: "This is a test alert from Sigil to verify your webhook configuration.",
      metadata: %{},
      inserted_at: DateTime.utc_now()
    }

    case @notifier.deliver(test_alert, config, []) do
      :ok ->
        put_flash(socket, :info, "Test alert sent to Discord")

      {:error, {:webhook_failed, status}} ->
        put_flash(socket, :error, "Webhook returned HTTP #{status} — check your URL")

      {:error, {:network_error, _reason}} ->
        put_flash(socket, :error, "Could not reach webhook endpoint — check your URL")
    end
  end

  defp test_webhook(socket) do
    put_flash(socket, :error, "Save a webhook URL before sending a test")
  end

  @spec parse_id(String.t()) :: {:ok, integer()} | :error
  defp parse_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} -> {:ok, id}
      _other -> :error
    end
  end
end
