defmodule SigilWeb.DiplomacyLive.Components.Sections do
  @moduledoc """
  Larger diplomacy page sections extracted from the component root module.
  """

  use SigilWeb, :html

  import SigilWeb.AssemblyHelpers, only: [truncate_id: 1]
  import SigilWeb.TribeHelpers, only: [nbsi_nrds_label: 1, standing_display: 1]

  alias Sigil.Diplomacy
  alias Sigil.Reputation.Scoring
  alias SigilWeb.DiplomacyLive.Components

  @doc "Renders the tribe standings table with optional leader controls."
  @spec tribe_standings_section(map()) :: Phoenix.LiveView.Rendered.t()
  def tribe_standings_section(assigns) do
    filtered =
      if assigns.tribe_filter != "" do
        query = String.downcase(assigns.tribe_filter)

        Enum.filter(assigns.tribe_standings, fn entry ->
          tribe_name = tribe_name_for(entry.tribe_id, assigns.world_tribes)
          name_match = tribe_name && String.contains?(String.downcase(tribe_name), query)
          id_match = Integer.to_string(entry.tribe_id) =~ query
          name_match or id_match
        end)
      else
        assigns.tribe_standings
      end

    filtered_world_tribes =
      if assigns.tribe_filter != "" do
        query = String.downcase(assigns.tribe_filter)

        Enum.filter(assigns.world_tribes, fn tribe ->
          name_match = String.contains?(String.downcase(tribe.name), query)
          id_match = Integer.to_string(tribe.id) =~ query
          name_match or id_match
        end)
      else
        assigns.world_tribes
      end

    assigns =
      assigns
      |> assign(:filtered_standings, filtered)
      |> assign(:filtered_world_tribes, filtered_world_tribes)

    ~H"""
    <div class="rounded-[2rem] border border-space-600/80 bg-space-900/70 p-8 shadow-2xl shadow-black/40 backdrop-blur">
      <p class="font-mono text-xs uppercase tracking-[0.3em] text-quantum-300">Tribe Custodian</p>
      <h2 class="mt-3 text-2xl font-semibold text-cream">Tribe Standings</h2>

      <div
        :if={!@is_leader}
        class="mt-4 rounded-2xl border border-space-600/60 bg-space-800/60 p-4 text-sm text-space-500"
      >
        Only the tribe leader can modify standings
      </div>

      <div class="mt-4">
        <input
          type="text"
          phx-keyup="filter_tribes"
          name="query"
          value={@tribe_filter}
          placeholder="Search tribes..."
          class="w-full rounded-xl border border-space-600/80 bg-space-900/70 px-4 py-2 font-mono text-sm text-cream placeholder:text-space-500 focus:border-quantum-400/60 focus:outline-none"
        />
      </div>

      <%= if @filtered_standings != [] do %>
        <div class="mt-6 overflow-x-auto">
          <table class="min-w-full border-separate border-spacing-y-3">
            <thead>
              <tr class="font-mono text-xs uppercase tracking-[0.25em] text-space-500">
                <th class="px-4 py-2 text-left">Tribe</th>
                <th class="px-4 py-2 text-left">Standing</th>
                <th class="px-4 py-2 text-left">Score</th>
                <th :if={@is_leader} class="px-4 py-2 text-left">Actions</th>
              </tr>
            </thead>
            <tbody>
              <%= for entry <- @filtered_standings do %>
                <% reputation = Map.get(@reputation_scores || %{}, entry.tribe_id) %>
                <% pinned = reputation && reputation.pinned %>
                <tr class="rounded-2xl bg-space-900/70 text-sm text-foreground">
                  <td class="rounded-l-2xl px-4 py-4 font-semibold text-cream">
                    <%= tribe_name_for(entry.tribe_id, @world_tribes) || "Tribe ##{entry.tribe_id}" %>
                  </td>
                  <td class="px-4 py-4">
                    <span class={Components.standing_badge_classes(entry.standing)}>
                      <%= standing_display(entry.standing) %>
                    </span>
                  </td>
                  <td class={["px-4 py-4", if(@is_leader, do: nil, else: "rounded-r-2xl")] }>
                    <div class="flex items-center gap-2">
                      <Components.score_badge reputation={reputation} />
                      <Components.auto_manual_chip pinned={pinned} />
                    </div>
                  </td>
                  <td :if={@is_leader} class="rounded-r-2xl px-4 py-4">
                    <div class="flex items-center gap-2">
                      <form phx-change="set_standing" class="inline">
                        <input type="hidden" name="tribe_id" value={entry.tribe_id} />
                        <select
                          name="standing"
                          class="rounded-lg border border-space-600/80 bg-space-900/70 px-2 py-1 font-mono text-xs text-cream"
                        >
                          <option value="">Change...</option>
                          <%= for {label, value} <- Components.standing_options() do %>
                            <option value={value} selected={value == Components.standing_value(entry.standing)}>
                              <%= label %>
                            </option>
                          <% end %>
                        </select>
                      </form>
                      <Components.pin_toggle
                        target_tribe_id={entry.tribe_id}
                        pinned={pinned}
                        standing={entry.standing}
                      />
                    </div>
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      <% else %>
        <p class="mt-6 text-sm text-space-500">No standings set yet.</p>
      <% end %>

      <div :if={@is_leader} class="mt-6 rounded-2xl border border-space-600/60 bg-space-800/60 p-4">
        <p class="font-mono text-xs uppercase tracking-[0.2em] text-space-500">Add Standing</p>
        <form id="add-tribe-standing-form" phx-submit="add_tribe_standing" class="mt-3 flex items-end gap-3">
          <div class="flex-1">
            <label class="block font-mono text-xs uppercase tracking-[0.2em] text-space-500">Tribe ID</label>
            <input
              type="text"
              name="tribe_id"
              class="mt-1 w-full rounded-lg border border-space-600/80 bg-space-900/70 px-3 py-2 font-mono text-sm text-cream focus:border-quantum-400/60 focus:outline-none"
            />
          </div>
          <div>
            <label class="block font-mono text-xs uppercase tracking-[0.2em] text-space-500">Standing</label>
            <select
              name="standing"
              class="mt-1 rounded-lg border border-space-600/80 bg-space-900/70 px-3 py-2 font-mono text-sm text-cream"
            >
              <%= for {label, value} <- Components.standing_options() do %>
                <option value={value}><%= label %></option>
              <% end %>
            </select>
          </div>
          <button
            type="submit"
            class="rounded-full bg-quantum-400 px-4 py-2 font-mono text-xs uppercase tracking-[0.25em] text-space-950 transition hover:bg-quantum-300"
          >
            Add
          </button>
        </form>
      </div>

      <%= for tribe <- @filtered_world_tribes do %>
        <span class="hidden"><%= tribe.name %></span>
      <% end %>
    </div>
    """
  end

  @doc "Renders the pilot overrides table with optional leader controls."
  @spec pilot_overrides_section(map()) :: Phoenix.LiveView.Rendered.t()
  def pilot_overrides_section(assigns) do
    ~H"""
    <div class="rounded-[2rem] border border-space-600/80 bg-space-900/70 p-8 shadow-2xl shadow-black/40 backdrop-blur">
      <p class="font-mono text-xs uppercase tracking-[0.3em] text-quantum-300">Pilot Overrides</p>
      <h2 class="mt-3 text-2xl font-semibold text-cream">Individual Pilots</h2>

      <%= if @pilot_standings != [] do %>
        <div class="mt-6 overflow-x-auto">
          <table class="min-w-full border-separate border-spacing-y-3">
            <thead>
              <tr class="font-mono text-xs uppercase tracking-[0.25em] text-space-500">
                <th class="px-4 py-2 text-left">Pilot</th>
                <th class="px-4 py-2 text-left">Standing</th>
              </tr>
            </thead>
            <tbody>
              <%= for entry <- @pilot_standings do %>
                <tr class="rounded-2xl bg-space-900/70 text-sm text-foreground">
                  <td class="rounded-l-2xl px-4 py-4 font-mono text-sm text-cream">
                    <%= truncate_id(entry.pilot) %>
                  </td>
                  <td class="rounded-r-2xl px-4 py-4">
                    <span class={Components.standing_badge_classes(entry.standing)}>
                      <%= standing_display(entry.standing) %>
                    </span>
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      <% else %>
        <p class="mt-6 text-sm text-space-500">No pilot overrides set.</p>
      <% end %>

      <div :if={@is_leader} class="mt-6 rounded-2xl border border-space-600/60 bg-space-800/60 p-4">
        <p class="font-mono text-xs uppercase tracking-[0.2em] text-space-500">Add Pilot Override</p>
        <form id="add-pilot-override-form" phx-submit="add_pilot_override" class="mt-3 flex items-end gap-3">
          <div class="flex-1">
            <label class="block font-mono text-xs uppercase tracking-[0.2em] text-space-500">Pilot Address</label>
            <input
              type="text"
              name="pilot_address"
              placeholder="0x..."
              class="mt-1 w-full rounded-lg border border-space-600/80 bg-space-900/70 px-3 py-2 font-mono text-sm text-cream placeholder:text-space-500 focus:border-quantum-400/60 focus:outline-none"
            />
          </div>
          <div>
            <label class="block font-mono text-xs uppercase tracking-[0.2em] text-space-500">Standing</label>
            <select
              name="standing"
              class="mt-1 rounded-lg border border-space-600/80 bg-space-900/70 px-3 py-2 font-mono text-sm text-cream"
            >
              <%= for {label, value} <- Components.standing_options() do %>
                <option value={value}><%= label %></option>
              <% end %>
            </select>
          </div>
          <button
            type="submit"
            class="rounded-full bg-quantum-400 px-4 py-2 font-mono text-xs uppercase tracking-[0.25em] text-space-950 transition hover:bg-quantum-300"
          >
            Add
          </button>
        </form>
        <p :if={@pilot_error} class="mt-2 text-sm text-warning"><%= @pilot_error %></p>
      </div>
    </div>
    """
  end

  @doc "Renders oracle enablement controls for leaders."
  @spec oracle_controls_section(map()) :: Phoenix.LiveView.Rendered.t()
  def oracle_controls_section(assigns) do
    ~H"""
    <div class="rounded-[2rem] border border-space-600/80 bg-space-900/70 p-8 shadow-2xl shadow-black/40 backdrop-blur">
      <p class="font-mono text-xs uppercase tracking-[0.3em] text-quantum-300">Reputation engine</p>
      <h2 class="mt-3 text-2xl font-semibold text-cream">Auto-Standings</h2>

      <p class="mt-4 text-sm text-space-500">
        Monitors chain events (kills, jumps) and automatically updates tribe standings based on reputation scores.
      </p>

      <%= if @oracle_enabled and @oracle_address do %>
        <div class="mt-4 rounded-2xl border border-success/30 bg-success/10 p-4">
          <p class="text-sm font-semibold text-success">Active</p>
          <p class="mt-1 font-mono text-xs text-space-500">Oracle: <%= truncate_id(@oracle_address) %></p>
        </div>
      <% else %>
        <div class="mt-4 rounded-2xl border border-space-600/60 bg-space-800/60 p-4">
          <p class="text-sm text-space-500">Not active — enable to let the server manage standings automatically.</p>
        </div>
      <% end %>

      <div class="mt-4 flex flex-wrap items-center gap-3">
        <button
          :if={!@oracle_enabled}
          type="button"
          phx-click="set_oracle"
          phx-value-oracle_address={Sigil.Sui.GasRelay.relay_address()}
          class="rounded-full border border-quantum-400/40 px-4 py-2 font-mono text-xs uppercase tracking-[0.24em] text-quantum-300 transition hover:border-quantum-300 hover:text-cream"
        >
          Enable Auto-Standings
        </button>

        <button
          :if={@oracle_enabled}
          type="button"
          phx-click="remove_oracle"
          class="rounded-full border border-warning/40 px-4 py-2 font-mono text-xs uppercase tracking-[0.24em] text-warning transition hover:border-warning hover:text-cream"
        >
          Disable
        </button>

        <.link
          patch={~p"/tribe/#{@tribe_id}/diplomacy?view=reputation"}
          class="rounded-full border border-space-600/80 px-4 py-2 font-mono text-xs uppercase tracking-[0.24em] text-space-500 transition hover:border-quantum-300 hover:text-cream"
        >
          View Scoring Rules
        </.link>
      </div>
    </div>
    """
  end

  @doc "Renders the detailed reputation scoring configuration panel."
  @spec reputation_config_panel(map()) :: Phoenix.LiveView.Rendered.t()
  def reputation_config_panel(assigns) do
    thresholds = Scoring.default_thresholds()
    assigns = assign(assigns, :thresholds, thresholds)

    ~H"""
    <div class="rounded-[2rem] border border-space-600/80 bg-space-900/70 p-8 shadow-2xl shadow-black/40 backdrop-blur">
      <p class="font-mono text-xs uppercase tracking-[0.3em] text-quantum-300">Reference</p>
      <h2 class="mt-3 text-2xl font-semibold text-cream">Scoring Rules</h2>
      <p class="mt-2 text-sm text-space-500">Standing thresholds and scoring parameters used by the reputation engine.</p>

      <div class="mt-4 grid gap-3 md:grid-cols-2">
        <div class="rounded-xl border border-space-600/60 bg-space-800/60 p-3 text-sm text-cream">
          Hostile: &lt;= <%= @thresholds.hostile_max %>
        </div>
        <div class="rounded-xl border border-space-600/60 bg-space-800/60 p-3 text-sm text-cream">
          Unfriendly: &lt;= <%= @thresholds.unfriendly_max %>
        </div>
        <div class="rounded-xl border border-space-600/60 bg-space-800/60 p-3 text-sm text-cream">
          Friendly: &gt;= <%= @thresholds.friendly_min %>
        </div>
        <div class="rounded-xl border border-space-600/60 bg-space-800/60 p-3 text-sm text-cream">
          Allied: &gt;= <%= @thresholds.allied_min %>
        </div>
      </div>

      <ul class="mt-4 space-y-2 text-sm text-space-500">
        <li>Decay half-life: ~14 days</li>
        <li>Transitive weight: 0.25</li>
        <li>Jump bonus: +5</li>
        <li>Kill multipliers: aggressor 3x / grid 2x</li>
      </ul>
    </div>
    """
  end

  @doc "Renders the default standing display with optional leader controls."
  @spec default_standing_section(map()) :: Phoenix.LiveView.Rendered.t()
  def default_standing_section(assigns) do
    ~H"""
    <div class="rounded-[2rem] border border-space-600/80 bg-space-900/70 p-8 shadow-2xl shadow-black/40 backdrop-blur">
      <p class="font-mono text-xs uppercase tracking-[0.3em] text-quantum-300">Default Standing</p>
      <h2 class="mt-3 text-2xl font-semibold text-cream">Default Policy</h2>

      <div class="mt-4 flex items-center gap-4">
        <span class={Components.standing_badge_classes(@default_standing)}>
          <%= standing_display(@default_standing) %>
        </span>
        <span class="rounded-full border border-space-600/80 bg-space-900/70 px-2 py-0.5 font-mono text-xs uppercase tracking-[0.2em] text-space-500">
          <%= nbsi_nrds_label(@default_standing) %>
        </span>
      </div>

      <div :if={@is_leader} class="mt-6 flex gap-3">
        <%= for {label, value} <- Components.standing_options() do %>
          <button
            type="button"
            phx-click="set_default_standing"
            phx-value-standing={value}
            class={[
              "rounded-full border px-3 py-1 font-mono text-xs uppercase tracking-[0.2em] transition hover:text-cream",
              if(standing_display(@default_standing) == label,
                do: "border-quantum-400/60 text-cream",
                else: "border-space-600/80 text-space-500 hover:border-quantum-400/40"
              )
            ]}
          >
            <%= label %>
          </button>
        <% end %>
      </div>
    </div>
    """
  end

  @spec tribe_name_for(non_neg_integer(), [Diplomacy.world_tribe()]) :: String.t() | nil
  defp tribe_name_for(tribe_id, world_tribes) do
    case Enum.find(world_tribes, &(&1.id == tribe_id)) do
      %{name: name} -> name
      nil -> nil
    end
  end
end
