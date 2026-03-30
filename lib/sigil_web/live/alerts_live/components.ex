defmodule SigilWeb.AlertsLive.Components do
  @moduledoc """
  Template components for the account-scoped alerts feed.
  """

  use SigilWeb, :html

  import SigilWeb.AlertsHelpers

  @doc """
  Renders the alerts page header and unread state controls.
  """
  @spec alerts_header(map()) :: Phoenix.LiveView.Rendered.t()
  def alerts_header(assigns) do
    ~H"""
    <div class="rounded-[2rem] border border-space-600/80 bg-space-900/70 p-8 shadow-2xl shadow-black/40 backdrop-blur">
      <div class="flex flex-col gap-4 md:flex-row md:items-start md:justify-between">
        <div>
          <p class="font-mono text-xs uppercase tracking-[0.35em] text-quantum-300">Alert relay</p>
          <h1 class="mt-3 text-4xl font-semibold text-cream">Alerts</h1>
          <p class="mt-3 max-w-2xl text-sm leading-6 text-space-500">
            Track active warnings, acknowledge them as they are reviewed, and keep dismissed history one toggle away.
          </p>
        </div>

        <div class="flex items-center gap-3 self-start">
          <span class="rounded-full border border-quantum-400/40 bg-quantum-400/10 px-4 py-2 font-mono text-xs uppercase tracking-[0.24em] text-quantum-300">
            <%= @unread_count %> unread
          </span>

          <button
            type="button"
            phx-click="toggle_dismissed"
            class={toggle_button_classes(@show_dismissed)}
          >
            <%= if @show_dismissed, do: "Hide Dismissed", else: "Show Dismissed" %>
          </button>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders the alert feed cards and empty state.
  """
  @spec alerts_feed(map()) :: Phoenix.LiveView.Rendered.t()
  def alerts_feed(assigns) do
    ~H"""
    <div class="rounded-[2rem] border border-space-600/80 bg-space-900/70 p-8 shadow-2xl shadow-black/40 backdrop-blur">
      <%= if @alerts == [] do %>
        <p class="text-sm text-space-500">No alerts yet</p>
      <% else %>
        <div class="space-y-4">
          <article
            :for={alert <- @alerts}
            class={card_classes_with_ownership(alert, @active_character)}
          >
            <div class="space-y-3">
              <div class="flex flex-wrap items-center justify-between gap-3">
                <div class="flex flex-wrap items-center gap-3">
                  <span class={severity_badge_classes(alert.severity)}><%= type_label(alert.type) %></span>
                  <span class="font-mono text-xs uppercase tracking-[0.2em] text-space-500">
                    <%= String.upcase(alert.severity || "info") %>
                  </span>
                  <span :if={alert.status == "new"} class="inline-flex h-2.5 w-2.5 rounded-full bg-quantum-300"></span>
                </div>

                <div class="flex items-center gap-2">
                  <button
                    :if={alert.status == "new"}
                    type="button"
                    phx-click="acknowledge"
                    phx-value-id={alert.id}
                    class="inline-flex rounded-full border border-quantum-400/40 bg-quantum-400/10 px-3 py-1.5 font-mono text-[0.65rem] uppercase tracking-[0.18em] text-quantum-300 transition hover:border-quantum-300 hover:text-cream"
                  >
                    Acknowledge
                  </button>

                  <button
                    :if={alert.status != "dismissed"}
                    type="button"
                    phx-click="dismiss"
                    phx-value-id={alert.id}
                    class="inline-flex rounded-full border border-warning/40 px-3 py-1.5 font-mono text-[0.65rem] uppercase tracking-[0.18em] text-warning transition hover:border-warning hover:text-cream"
                  >
                    Dismiss
                  </button>
                </div>
              </div>

              <div class="min-w-0 space-y-2">
                <%= if alert_linkable?(alert) do %>
                  <.link
                    navigate={~p"/assembly/#{alert.assembly_id}"}
                    title={alert.assembly_id}
                    class="block truncate text-lg font-semibold text-cream transition hover:text-quantum-300"
                  >
                    <%= alert_heading(alert) %>
                  </.link>
                <% else %>
                  <p class="truncate text-lg font-semibold text-cream"><%= alert_heading(alert) %></p>
                <% end %>
                <p class={"break-all #{message_classes(alert.status)}"}><%= alert.message %></p>
              </div>

              <div class="flex flex-wrap items-center gap-3 text-xs text-space-500">
                <%= if character_name = alert_character_name(alert) do %>
                  <span class={ownership_label_classes(alert, @active_character)}>
                    via <%= character_name %>
                  </span>
                <% else %>
                  <span class="font-mono uppercase tracking-[0.2em]"><%= alert_scope_label(alert) %></span>
                <% end %>
                <span><%= timestamp_label(alert) %></span>
              </div>
            </div>
          </article>
        </div>

        <div
          id="alerts-feed-sentinel"
          phx-hook="InfiniteScroll"
          data-has-more={to_string(@has_more)}
          class={sentinel_classes(@has_more)}
        >
          Load more
        </div>
      <% end %>
    </div>
    """
  end

  @doc """
  Renders webhook configuration controls for the tribe leader.
  """
  @spec webhook_panel(map()) :: Phoenix.LiveView.Rendered.t()
  def webhook_panel(assigns) do
    ~H"""
    <div
      :if={@is_leader}
      class="rounded-[2rem] border border-space-600/80 bg-space-900/70 p-8 shadow-2xl shadow-black/40 backdrop-blur"
    >
      <div class="flex flex-col gap-4 md:flex-row md:items-start md:justify-between">
        <div>
          <p class="font-mono text-xs uppercase tracking-[0.3em] text-quantum-300">Notifications</p>
          <h2 class="mt-3 text-2xl font-semibold text-cream">Discord Webhook</h2>
          <p class="mt-2 text-sm text-space-500">Send tribe alerts directly to a Discord channel.</p>
        </div>

        <%= if @webhook_config do %>
          <div class="flex items-center gap-3">
            <span class={webhook_status_classes(@webhook_config.enabled)}>
              <%= if @webhook_config.enabled, do: "Enabled", else: "Disabled" %>
            </span>
            <button
              type="button"
              phx-click="toggle_webhook"
              class="rounded-full border border-space-600/80 px-3 py-1 font-mono text-xs uppercase tracking-[0.2em] text-space-500 transition hover:border-space-400 hover:text-cream"
            >
              <%= if @webhook_config.enabled, do: "Disable", else: "Enable" %>
            </button>
          </div>
        <% end %>
      </div>

      <div :if={@webhook_config} class="mt-4 flex flex-wrap items-center gap-3">
        <p class="font-mono text-xs text-space-500">
          Current endpoint: <%= masked_webhook_url(@webhook_config.webhook_url) %>
        </p>
        <button
          type="button"
          phx-click="test_webhook"
          class="rounded-full border border-quantum-400/40 px-3 py-1 font-mono text-xs uppercase tracking-[0.2em] text-quantum-300 transition hover:border-quantum-300 hover:text-cream"
        >
          Send Test
        </button>
      </div>
      <p :if={!@webhook_config} class="mt-4 text-sm text-space-500">No webhook configured yet.</p>

      <.form id="webhook-config-form" for={@webhook_form} phx-submit="save_webhook" class="mt-5 space-y-3">
        <label class="block space-y-2">
          <span class="font-mono text-xs uppercase tracking-[0.24em] text-space-500">Webhook URL</span>
          <input
            type="url"
            name="webhook[webhook_url]"
            value={@webhook_form.params["webhook_url"] || ""}
            placeholder="https://discord.com/api/webhooks/..."
            class="w-full rounded-2xl border border-space-600/80 bg-space-950/70 px-4 py-3 text-sm text-cream outline-none transition focus:border-quantum-400"
          />
        </label>

        <button
          type="submit"
          class="inline-flex rounded-full bg-quantum-400 px-5 py-2.5 font-mono text-xs uppercase tracking-[0.25em] text-space-950 transition hover:bg-quantum-300"
        >
          Save Webhook
        </button>
      </.form>
    </div>
    """
  end

  @spec webhook_status_classes(boolean()) :: String.t()
  defp webhook_status_classes(true),
    do:
      "rounded-full border border-success/40 bg-success/10 px-3 py-1 font-mono text-xs uppercase tracking-[0.2em] text-success"

  defp webhook_status_classes(false),
    do:
      "rounded-full border border-space-600/80 bg-space-900/70 px-3 py-1 font-mono text-xs uppercase tracking-[0.2em] text-space-500"

  @spec masked_webhook_url(String.t() | nil) :: String.t()
  defp masked_webhook_url(nil), do: "Not set"

  defp masked_webhook_url(url) when is_binary(url) do
    segments = String.split(url, "/", trim: true)

    case Enum.reverse(segments) do
      [token | rest] ->
        masked = token |> String.slice(0, 6) |> Kernel.<>("...")
        Enum.reverse([masked | rest]) |> Enum.join("/")

      _other ->
        url
    end
  end

  @spec toggle_button_classes(boolean()) :: String.t()
  defp toggle_button_classes(true) do
    "rounded-full border border-quantum-300 bg-quantum-400/10 px-4 py-2 font-mono text-xs uppercase tracking-[0.24em] text-cream"
  end

  defp toggle_button_classes(false) do
    "rounded-full border border-space-600/80 bg-space-800/70 px-4 py-2 font-mono text-xs uppercase tracking-[0.24em] text-space-500 transition hover:border-quantum-400 hover:text-cream"
  end

  @spec sentinel_classes(boolean()) :: String.t()
  defp sentinel_classes(true),
    do: "mt-6 text-center font-mono text-xs uppercase tracking-[0.2em] text-space-500"

  defp sentinel_classes(false),
    do: "mt-6 hidden text-center font-mono text-xs uppercase tracking-[0.2em] text-space-500"

  @spec alert_linkable?(map()) :: boolean()
  defp alert_linkable?(%{assembly_id: assembly_id})
       when is_binary(assembly_id) and assembly_id != "",
       do: true

  defp alert_linkable?(_alert), do: false

  @spec alert_heading(map()) :: String.t()
  defp alert_heading(%{assembly_name: assembly_name})
       when is_binary(assembly_name) and assembly_name != "",
       do: assembly_name

  defp alert_heading(alert), do: alert_scope_label(alert)

  @spec alert_scope_label(map()) :: String.t()
  defp alert_scope_label(%{assembly_id: assembly_id})
       when is_binary(assembly_id) and assembly_id != "",
       do: truncate_id(assembly_id)

  defp alert_scope_label(%{metadata: metadata}), do: reputation_scope_label(metadata)
  defp alert_scope_label(_alert), do: "Tribe alert"

  @spec truncate_id(String.t()) :: String.t()
  defp truncate_id(id) when byte_size(id) > 16 do
    String.slice(id, 0, 8) <> "..." <> String.slice(id, -6, 6)
  end

  defp truncate_id(id), do: id

  @spec reputation_scope_label(map() | nil) :: String.t()
  defp reputation_scope_label(metadata) when is_map(metadata) do
    target_tribe_id = Map.get(metadata, :target_tribe_id) || Map.get(metadata, "target_tribe_id")

    case target_tribe_id do
      value when is_integer(value) -> "Tribe ##{value}"
      value when is_binary(value) and value != "" -> "Tribe ##{value}"
      _other -> "Tribe alert"
    end
  end

  defp reputation_scope_label(_metadata), do: "Tribe alert"

  # alert_character_name/1 is imported from SigilWeb.AlertsHelpers

  @spec owns_alert?(map(), map() | nil) :: boolean()
  defp owns_alert?(_alert, nil), do: false

  defp owns_alert?(alert, active_character) do
    char_name = alert_character_name(alert)
    active_name = active_character_name(active_character)
    char_name != nil and active_name != nil and char_name == active_name
  end

  @spec active_character_name(map()) :: String.t() | nil
  defp active_character_name(%{metadata: %{name: name}}) when is_binary(name) and name != "",
    do: name

  defp active_character_name(%{character_name: name}) when is_binary(name) and name != "",
    do: name

  defp active_character_name(_character), do: nil

  @spec card_classes_with_ownership(map(), map() | nil) :: String.t()
  defp card_classes_with_ownership(alert, active_character) do
    base = card_classes(alert)
    char_name = alert_character_name(alert)
    owned = owns_alert?(alert, active_character)
    ownership_border(base, char_name, owned)
  end

  defp ownership_border(base, nil, _owned), do: base
  defp ownership_border(base, _name, true), do: base <> " border-l-4 border-l-quantum-400"
  defp ownership_border(base, _name, false), do: base <> " border-l-4 border-l-space-500"

  @spec ownership_label_classes(map(), map() | nil) :: String.t()
  defp ownership_label_classes(alert, active_character) do
    if owns_alert?(alert, active_character) do
      "font-mono text-xs uppercase tracking-[0.2em] text-quantum-300"
    else
      "font-mono text-xs uppercase tracking-[0.2em] text-space-400"
    end
  end
end
