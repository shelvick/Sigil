defmodule SigilWeb.AlertsLive do
  @moduledoc """
  Account-scoped alerts feed with lifecycle actions and PubSub refreshes.
  """

  use SigilWeb, :live_view

  alias Sigil.Alerts

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

        <SigilWeb.AlertsLive.Components.alerts_feed alerts={@alerts} has_more={@has_more} />
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
      loaded_count: 0
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

  @spec parse_id(String.t()) :: {:ok, integer()} | :error
  defp parse_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} -> {:ok, id}
      _other -> :error
    end
  end
end
