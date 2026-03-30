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
    <div id="map-panel" class="rounded-[2rem] border border-space-600/80 bg-space-900/70 p-8 shadow-2xl shadow-black/40 backdrop-blur">
      <p class="font-mono text-xs uppercase tracking-[0.35em] text-quantum-300">Navigation map</p>
      <h1 class="mt-3 text-4xl font-semibold text-cream">Galaxy</h1>

      <%= if @static_data_available do %>
        <div class="mt-6 h-[34rem] overflow-hidden rounded-2xl border border-space-600/80 bg-space-950/70">
          <div id="galaxy-map" phx-hook="GalaxyMap" class="h-full w-full"></div>
        </div>
        <div class="mt-3 flex flex-wrap items-center gap-4 font-mono text-[0.6rem] uppercase tracking-[0.2em] text-space-500">
          <span>Click: select system</span>
          <span>Drag: rotate</span>
          <span>Ctrl+Drag: pan</span>
          <span>Scroll: zoom</span>
        </div>
        <div class="mt-3 flex flex-wrap items-center gap-3 text-xs text-space-300">
          <span class="inline-flex items-center gap-1.5"><span class="h-2.5 w-2.5 rounded-full bg-[#4488ff]"></span>Intel</span>
          <span class="inline-flex items-center gap-1.5"><span class="h-2.5 w-2.5 rounded-full bg-[#44cc66]"></span>Tribe assembly</span>
          <span class="inline-flex items-center gap-1.5"><span class="h-2.5 w-2.5 rounded-full bg-[#ff8c00]"></span>Low fuel</span>
          <span class="inline-flex items-center gap-1.5"><span class="h-2.5 w-2.5 rounded-full bg-[#ff4444]"></span>Critical fuel</span>
          <span class="inline-flex items-center gap-1.5"><span class="h-2.5 w-2.5 rounded-full bg-white"></span>Assembly + intel</span>
          <span class="inline-flex items-center gap-1.5"><span class="h-2.5 w-2.5 rounded-full bg-[#445566]"></span>Background systems</span>
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
        <div class="flex items-start justify-between">
          <div>
            <h2 class="text-2xl font-semibold text-cream"><%= @detail_data.system_name %></h2>
            <p class="mt-1 font-mono text-xs uppercase tracking-[0.2em] text-space-500">
              Constellation <%= @detail_data.constellation_name %>
            </p>
          </div>
          <button
            type="button"
            phx-click="deselect_system"
            class="rounded-full border border-space-600/80 px-2.5 py-1 font-mono text-xs text-space-400 transition hover:border-quantum-400 hover:text-cream"
          >
            &times;
          </button>
        </div>

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
              <%= if assembly.label, do: assembly.label, else: assembly.id %>
            </.link>
          </div>
        <% end %>
      </div>
    <% end %>
    """
  end

  @doc "Returns toggle button classes based on active/inactive state."
  @spec overlay_toggle_classes(boolean()) :: String.t()
  def overlay_toggle_classes(true) do
    "rounded-full border border-quantum-400/60 bg-quantum-400/10 px-3 py-1 text-xs text-quantum-300"
  end

  def overlay_toggle_classes(_inactive) do
    "rounded-full border border-space-600/80 px-3 py-1 text-xs text-space-500 transition hover:border-space-400 hover:text-cream"
  end
end
