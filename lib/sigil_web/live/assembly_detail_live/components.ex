defmodule SigilWeb.AssemblyDetailLive.Components do
  @moduledoc """
  Template components for the assembly detail LiveView.
  """

  use SigilWeb, :html

  import SigilWeb.AssemblyHelpers
  import SigilWeb.DiplomacyLive.Components, only: [signing_overlay: 1]
  import SigilWeb.MonitorHelpers, only: [relative_depletion_label: 1]

  @doc """
  Renders the shared location panel for an assembly.
  """
  @spec location_panel(map()) :: Phoenix.LiveView.Rendered.t()
  def location_panel(assigns) do
    ~H"""
    <div class="mt-8 rounded-2xl border border-space-600/80 bg-space-800/70 p-5">
      <div class="flex flex-col gap-4 md:flex-row md:items-start md:justify-between">
        <div class="space-y-3">
          <div>
            <p class="font-mono text-xs uppercase tracking-[0.3em] text-quantum-300">Location</p>
            <p class="mt-3 text-sm text-cream"><%= @location_name || "Location unknown" %></p>
          </div>

          <.link
            :if={is_integer(@location_solar_system_id)}
            navigate={~p"/map?system_id=#{@location_solar_system_id}"}
            class="inline-flex rounded-full border border-quantum-400/40 bg-quantum-400/10 px-3 py-1 font-mono text-xs uppercase tracking-[0.2em] text-quantum-300 transition hover:border-quantum-300 hover:text-cream"
          >
            View on Map
          </.link>
        </div>

        <%= if @can_edit_location do %>
          <.form id="set-location-form" for={@form} phx-submit="set_location" phx-change="filter_solar_systems" class="w-full max-w-md space-y-3">
            <p class="font-mono text-xs uppercase tracking-[0.24em] text-space-500"><%= if @location_name, do: "Update Location", else: "Set Location" %></p>
            <div class="relative">
              <label class="block space-y-2">
                <span class="font-mono text-xs uppercase tracking-[0.24em] text-space-500"><%= if @location_name, do: "New system name", else: "Solar system name" %></span>
                <input
                  type="text"
                  name="location[solar_system_name]"
                  value={@solar_system_query}
                  placeholder="Type to search…"
                  autocomplete="off"
                  phx-debounce="150"
                  class="w-full rounded-2xl border border-space-600/80 bg-space-950/70 px-4 py-3 text-sm text-cream outline-none transition focus:border-quantum-400"
                />
              </label>
              <div
                :if={@filtered_solar_systems != []}
                class="absolute z-50 mt-1 max-h-48 w-full overflow-y-auto rounded-2xl border border-space-600/80 bg-space-900/95 shadow-2xl backdrop-blur"
              >
                <button
                  :for={system <- @filtered_solar_systems}
                  type="button"
                  phx-click="select_solar_system"
                  phx-value-name={system.name}
                  class="block w-full px-4 py-2.5 text-left text-sm text-cream transition first:rounded-t-2xl last:rounded-b-2xl hover:bg-space-800/80 hover:text-quantum-300"
                >
                  <%= system.name %>
                </button>
              </div>
            </div>

            <button
              type="submit"
              class="inline-flex rounded-full bg-quantum-400 px-4 py-2 font-mono text-xs uppercase tracking-[0.22em] text-space-950 transition hover:bg-quantum-300"
            >
              <%= if @location_name, do: "Update Location", else: "Set Location" %>
            </button>
          </.form>
        <% end %>
      </div>
    </div>
    """
  end

  @doc """
  Renders the type-specific detail section for the current assembly.
  """
  @spec type_specific_section(map()) :: Phoenix.LiveView.Rendered.t()
  def type_specific_section(assigns) do
    ~H"""
    <%= case @assembly_type do %>
      <% :gate -> %>
        <div class="mt-8 space-y-4">
          <div class="grid gap-4 md:grid-cols-2">
            <div class="rounded-2xl border border-space-600/80 bg-space-800/70 p-4">
              <p class="font-mono text-xs uppercase tracking-[0.3em] text-quantum-300">Linked Gate</p>
              <%= if @assembly.linked_gate_id && byte_size(@assembly.linked_gate_id) > 0 do %>
                <.link
                  navigate={~p"/assembly/#{@assembly.linked_gate_id}"}
                  class="mt-3 block text-sm text-quantum-300 transition hover:text-cream"
                  title={@assembly.linked_gate_id}
                >
                  <%= resolve_intel_label(@assembly.linked_gate_id, @intel_opts) || truncate_id(@assembly.linked_gate_id) %>
                </.link>
              <% else %>
                <p class="mt-3 font-mono text-sm text-foreground">Not linked</p>
              <% end %>
            </div>
            <.detail_card
              title="Extension"
              value={extension_label(@assembly.extension)}
              mono
              full_value={@assembly.extension}
            />
          </div>

          <.gate_extension_panel
            :if={@is_owner}
            assembly={@assembly}
            active_character={@active_character}
          />

          <.signing_overlay :if={@signing_state == :signing_tx} />
        </div>

      <% :turret -> %>
        <div class="mt-8 grid gap-4 md:grid-cols-2">
          <.detail_card title="Extension" value={extension_label(@assembly.extension)} mono full_value={@assembly.extension} />
        </div>

      <% :storage_unit -> %>
        <div class="mt-8 grid gap-4 lg:grid-cols-[1.2fr_0.8fr]">
          <div class="rounded-2xl border border-space-600/80 bg-space-800/70 p-5">
            <p class="font-mono text-xs uppercase tracking-[0.3em] text-quantum-300">Inventory Slots</p>
            <%= if @assembly.inventory_keys == [] do %>
              <p class="mt-4 text-sm text-space-500">Empty</p>
            <% else %>
              <div class="mt-4 space-y-2">
                <p :for={inventory_key <- @assembly.inventory_keys} class="font-mono text-sm text-foreground" title={inventory_key}>
                  <%= truncate_id(inventory_key) %>
                </p>
              </div>
            <% end %>
          </div>
          <div class="grid gap-4">
            <.detail_card title="Item Count" value={Integer.to_string(length(@assembly.inventory_keys))} mono />
            <.detail_card title="Extension" value={extension_label(@assembly.extension)} mono full_value={@assembly.extension} />
          </div>
        </div>

      <% :network_node -> %>
        <div class="mt-8 grid gap-4 xl:grid-cols-[1.2fr_1fr]">
          <div class="space-y-4 rounded-2xl border border-space-600/80 bg-space-800/70 p-5">
            <div>
              <p class="font-mono text-xs uppercase tracking-[0.3em] text-quantum-300">Fuel Panel</p>
              <div class="mt-4 flex items-center justify-between gap-3 font-mono text-xs uppercase tracking-[0.15em] text-space-500">
                <span><%= fuel_label(@assembly.fuel) %></span>
                <span><%= fuel_percent_label(@assembly.fuel) %></span>
              </div>
              <div class="mt-3 h-3 rounded-full bg-space-700">
                <div class={["h-full rounded-full", fuel_bar_color(@assembly.fuel)]} style={"width: #{fuel_bar_width(@assembly.fuel)}%"}></div>
              </div>
            </div>

            <%= if @depletion do %>
              <div class="rounded-2xl border border-space-600/80 bg-space-900/60 p-4">
                <p class="font-mono text-xs uppercase tracking-[0.3em] text-quantum-300">Fuel Forecast</p>
                <%= case @depletion do %>
                  <% {:depletes_at, depletes_at} -> %>
                    <p class="mt-3 text-sm text-cream">Depletes at <%= Calendar.strftime(depletes_at, "%Y-%m-%d %H:%M:%S UTC") %></p>
                    <div
                      id={"fuel-countdown-#{@assembly.id}"}
                      class="mt-2 text-sm text-space-500"
                      phx-hook="FuelCountdown"
                      data-depletes-at={DateTime.to_iso8601(depletes_at)}
                    >
                      in <%= relative_depletion_label(depletes_at) %>
                    </div>
                  <% :not_burning -> %>
                    <p class="mt-3 text-sm text-space-500">Not burning</p>
                  <% :no_fuel -> %>
                    <p class="mt-3 text-sm text-space-500">No fuel</p>
                <% end %>
              </div>
            <% end %>

            <div class="grid gap-4 md:grid-cols-2">
              <.detail_card title="Burn Rate" value={format_burn_rate(@assembly.fuel.burn_rate_in_ms)} mono />
              <.detail_card title="Is Burning" value={yes_no(@assembly.fuel.is_burning)} mono />
              <.detail_card title="Fuel Type" value={@fuel_type_name || optional_integer(@assembly.fuel.type_id)} mono />
              <.detail_card title="Unit Volume" value={optional_integer(@assembly.fuel.unit_volume)} mono />
              <.detail_card title="Burn Start Time" value={format_timestamp(@assembly.fuel.burn_start_time, @assembly.fuel.is_burning)} mono />
              <.detail_card title="Last Updated" value={format_timestamp(@assembly.fuel.last_updated, true)} mono />
            </div>
          </div>

          <div class="space-y-4">
            <div class="rounded-2xl border border-space-600/80 bg-space-800/70 p-5">
              <p class="font-mono text-xs uppercase tracking-[0.3em] text-quantum-300">Energy Panel</p>
              <div class="mt-4 grid gap-4">
                <.detail_card title="Max Energy Production" value={Integer.to_string(@assembly.energy_source.max_energy_production)} mono />
                <.detail_card title="Current Energy Production" value={energy_current_label(@assembly.energy_source)} mono />
                <.detail_card title="Total Reserved Energy" value={Integer.to_string(@assembly.energy_source.total_reserved_energy)} mono />
                <.detail_card title="Available Energy" value={Integer.to_string(available_energy(@assembly.energy_source))} mono />
              </div>
            </div>

            <div class="rounded-2xl border border-space-600/80 bg-space-800/70 p-5">
              <p class="font-mono text-xs uppercase tracking-[0.3em] text-quantum-300">Connections</p>
              <div class="mt-4 flex items-center justify-between gap-3">
                <p class="text-sm text-space-500">Connection Count</p>
                <p class="font-mono text-sm text-foreground"><%= length(@assembly.connected_assembly_ids) %></p>
              </div>
              <%= if @assembly.connected_assembly_ids == [] do %>
                <p class="mt-4 text-sm text-space-500">No connections</p>
              <% else %>
                <div class="mt-4 space-y-2">
                  <.link
                    :for={assembly_id <- @assembly.connected_assembly_ids}
                    navigate={~p"/assembly/#{assembly_id}"}
                    class="block text-sm text-quantum-300 transition hover:text-cream"
                  >
                    <%= resolve_intel_label(assembly_id, @intel_opts) || truncate_id(assembly_id) %>
                  </.link>
                </div>
              <% end %>
            </div>
          </div>
        </div>

      <% :assembly -> %>
        <div class="mt-8 rounded-2xl border border-space-600/80 bg-space-800/70 p-5">
          <p class="font-mono text-xs uppercase tracking-[0.3em] text-quantum-300">Unknown assembly type</p>
          <p class="mt-4 text-sm leading-6 text-space-500">
            No type-specific telemetry is available for this assembly yet.
          </p>
        </div>
    <% end %>
    """
  end
end
