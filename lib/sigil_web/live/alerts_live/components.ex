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
          <article :for={alert <- @alerts} class={card_classes(alert)}>
            <div class="flex flex-col gap-4 md:flex-row md:items-start md:justify-between">
              <div class="space-y-3">
                <div class="flex flex-wrap items-center gap-3">
                  <span class={severity_badge_classes(alert.severity)}><%= type_label(alert.type) %></span>
                  <span class="font-mono text-xs uppercase tracking-[0.2em] text-space-500">
                    <%= String.upcase(alert.severity || "info") %>
                  </span>
                  <span :if={alert.status == "new"} class="inline-flex h-2.5 w-2.5 rounded-full bg-quantum-300"></span>
                </div>

                <div class="space-y-2">
                  <.link
                    navigate={~p"/assembly/#{alert.assembly_id}"}
                    title={alert.assembly_id}
                    class="text-lg font-semibold text-cream transition hover:text-quantum-300"
                  >
                    <%= alert.assembly_name %>
                  </.link>
                  <p class={message_classes(alert.status)}><%= alert.message %></p>
                </div>

                <div class="flex flex-wrap items-center gap-3 text-xs text-space-500">
                  <span class="font-mono uppercase tracking-[0.2em]"><%= alert.assembly_id %></span>
                  <span><%= timestamp_label(alert) %></span>
                </div>
              </div>

              <div class="flex items-center gap-2 self-start">
                <button
                  :if={alert.status == "new"}
                  type="button"
                  phx-click="acknowledge"
                  phx-value-id={alert.id}
                  class="inline-flex rounded-full border border-quantum-400/40 bg-quantum-400/10 px-4 py-2 font-mono text-xs uppercase tracking-[0.22em] text-quantum-300 transition hover:border-quantum-300 hover:text-cream"
                >
                  Acknowledge
                </button>

                <button
                  :if={alert.status != "dismissed"}
                  type="button"
                  phx-click="dismiss"
                  phx-value-id={alert.id}
                  class="inline-flex rounded-full border border-warning/40 px-4 py-2 font-mono text-xs uppercase tracking-[0.22em] text-warning transition hover:border-warning hover:text-cream"
                >
                  Dismiss
                </button>
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
end
