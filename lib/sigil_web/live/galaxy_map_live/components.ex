defmodule SigilWeb.GalaxyMapLive.Components do
  @moduledoc """
  Template components for the galaxy map LiveView.
  """

  use SigilWeb, :html

  @doc """
  Renders the map canvas panel and overlay toggles.
  """
  @spec map_panel(map()) :: Phoenix.LiveView.Rendered.t()
  def map_panel(assigns) do
    ~H"""
    <div class="rounded-[2rem] border border-space-600/80 bg-space-900/70 p-8 shadow-2xl shadow-black/40 backdrop-blur">
      <p class="font-mono text-xs uppercase tracking-[0.35em] text-quantum-300">Navigation map</p>
      <h1 class="mt-3 text-4xl font-semibold text-cream">Galaxy</h1>

      <%= if @static_data_available do %>
        <div class="mt-6 flex flex-wrap gap-2">
          <%= if is_integer(@tribe_id) do %>
            <button
              type="button"
              phx-click="toggle_overlay"
              phx-value-layer="tribe_locations"
              class="rounded-full border border-space-500/80 px-3 py-1 text-xs text-cream"
            >
              Tribe Locations
            </button>
            <button
              type="button"
              phx-click="toggle_overlay"
              phx-value-layer="tribe_scouting"
              class="rounded-full border border-space-500/80 px-3 py-1 text-xs text-cream"
            >
              Tribe Scouting
            </button>
          <% end %>
          <button
            type="button"
            phx-click="toggle_overlay"
            phx-value-layer="marketplace"
            class="rounded-full border border-space-500/80 px-3 py-1 text-xs text-cream"
          >
            Marketplace
          </button>
        </div>

        <div class="mt-6 h-[34rem] overflow-hidden rounded-2xl border border-space-600/80 bg-space-950/70">
          <div id="galaxy-map" phx-hook="GalaxyMap" class="h-full w-full"></div>
        </div>
      <% else %>
        <div class="mt-6 rounded-2xl border border-warning/40 bg-warning/10 p-4 text-sm text-warning">
          Galaxy data unavailable
        </div>
      <% end %>
    </div>
    """
  end

  @doc """
  Renders the selected-system detail panel.
  """
  @spec detail_panel(map()) :: Phoenix.LiveView.Rendered.t()
  def detail_panel(assigns) do
    ~H"""
    <%= if @detail_data do %>
      <div class="rounded-[2rem] border border-space-600/80 bg-space-900/70 p-6 shadow-2xl shadow-black/30 backdrop-blur">
        <h2 class="text-2xl font-semibold text-cream"><%= @detail_data.system_name %></h2>
        <p class="mt-1 font-mono text-xs uppercase tracking-[0.2em] text-space-500">
          <%= @detail_data.constellation_name %>
        </p>

        <%= if is_integer(@tribe_id) do %>
          <p class="mt-4 text-sm text-foreground">
            <%= @detail_data.tribe_location_count %> assembly locations, <%= @detail_data.tribe_scouting_count %> scouting reports
          </p>
        <% end %>

        <p class="mt-2 text-sm text-foreground">
          <%= @detail_data.marketplace_count %> marketplace intel entries
        </p>

        <%= if @detail_data.assemblies != [] do %>
          <div class="mt-4 space-y-2">
            <.link
              :for={assembly <- @detail_data.assemblies}
              navigate={~p"/assembly/#{assembly.id}"}
              class="block rounded-xl border border-space-600/80 bg-space-950/50 px-3 py-2 text-sm text-quantum-300 transition hover:border-quantum-300 hover:text-cream"
            >
              <%= assembly.id %><%= if assembly.label, do: " - #{assembly.label}" %>
            </.link>
          </div>
        <% end %>
      </div>
    <% end %>
    """
  end
end
