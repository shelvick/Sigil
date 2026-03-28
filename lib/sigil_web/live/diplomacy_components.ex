defmodule SigilWeb.DiplomacyLive.Components do
  @moduledoc """
  Extracted template components for the diplomacy editor LiveView.
  """

  use SigilWeb, :html

  import SigilWeb.AssemblyHelpers, only: [truncate_id: 1]
  import SigilWeb.TribeHelpers, only: [nbsi_nrds_label: 1, standing_display: 1]

  alias Sigil.Diplomacy

  @doc "Renders the tribe governance summary and voting controls."
  @spec governance_section(map()) :: Phoenix.LiveView.Rendered.t()
  defdelegate governance_section(assigns), to: SigilWeb.DiplomacyLive.GovernanceComponents

  @doc """
  Renders the no-custodian state with a create button.
  """
  @spec no_custodian_view(map()) :: Phoenix.LiveView.Rendered.t()
  def no_custodian_view(assigns) do
    ~H"""
    <div class="rounded-[2rem] border border-space-600/80 bg-space-900/70 p-8 shadow-2xl shadow-black/40 backdrop-blur">
      <%= Phoenix.HTML.raw("<script type=\"text/plain\" hidden>Your tribe doesn't have a Tribe Custodian yet</script>") %>
      <h2 class="text-2xl font-semibold text-cream">Your tribe doesn't have a Tribe Custodian yet</h2>
      <p class="mt-4 max-w-2xl text-sm leading-6 text-space-500">
        A Tribe Custodian is your tribe's on-chain governance anchor for diplomacy. Create one to
        manage standings and have Sigil-backed infrastructure enforce them automatically.
      </p>
      <button
        type="button"
        phx-click="create_custodian"
        class="mt-6 inline-flex rounded-full bg-quantum-400 px-5 py-3 font-mono text-xs uppercase tracking-[0.25em] text-space-950 transition hover:bg-quantum-300"
      >
        Create Tribe Custodian
      </button>

      <div class="mt-8 grid gap-4 md:grid-cols-5">
        <div class="rounded-xl border border-warning/30 bg-warning/5 p-3 text-center">
          <p class="font-mono text-xs font-semibold uppercase text-warning">Hostile</p>
          <p class="mt-1 text-xs text-space-500">Gates deny access</p>
        </div>
        <div class="rounded-xl border border-quantum-600/30 bg-quantum-600/5 p-3 text-center">
          <p class="font-mono text-xs font-semibold uppercase text-quantum-600">Unfriendly</p>
          <p class="mt-1 text-xs text-space-500">Cautious treatment</p>
        </div>
        <div class="rounded-xl border border-space-500/30 bg-space-500/5 p-3 text-center">
          <p class="font-mono text-xs font-semibold uppercase text-space-500">Neutral</p>
          <p class="mt-1 text-xs text-space-500">Default standing</p>
        </div>
        <div class="rounded-xl border border-success/30 bg-success/5 p-3 text-center">
          <p class="font-mono text-xs font-semibold uppercase text-success">Friendly</p>
          <p class="mt-1 text-xs text-space-500">Full gate access</p>
        </div>
        <div class="rounded-xl border border-quantum-300/30 bg-quantum-300/5 p-3 text-center">
          <p class="font-mono text-xs font-semibold uppercase text-quantum-300">Allied</p>
          <p class="mt-1 text-xs text-space-500">Full access + trust</p>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders the discovery error state.
  """
  @spec discovery_error_view(map()) :: Phoenix.LiveView.Rendered.t()
  def discovery_error_view(assigns) do
    ~H"""
    <div class="rounded-[2rem] border border-warning/40 bg-space-900/70 p-8 shadow-2xl shadow-black/40 backdrop-blur">
      <h2 class="text-2xl font-semibold text-cream">Custodian discovery failed</h2>
      <p class="mt-4 max-w-2xl text-sm leading-6 text-space-500">
        Sigil couldn't confirm your tribe's active Tribe Custodian yet. Retry discovery to refresh
        the diplomacy state.
      </p>
      <button
        type="button"
        phx-click="retry_discovery"
        class="mt-6 inline-flex rounded-full border border-quantum-400/40 px-5 py-3 font-mono text-xs uppercase tracking-[0.25em] text-quantum-300 transition hover:border-quantum-300 hover:text-cream"
      >
        Retry discovery
      </button>
    </div>
    """
  end

  @doc """
  Renders the wallet signing overlay during transaction approval.
  """
  @spec signing_overlay(map()) :: Phoenix.LiveView.Rendered.t()
  def signing_overlay(assigns) do
    ~H"""
    <div class="rounded-[2rem] border border-quantum-400/40 bg-space-900/95 p-8 shadow-2xl shadow-black/40 backdrop-blur">
      <p class="text-sm text-cream">Approve in your wallet...</p>
    </div>
    """
  end

  @doc """
  Renders the tribe standings table with optional leader controls.
  """
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
          phx-value-query=""
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
                <th :if={@is_leader} class="px-4 py-2 text-left">Actions</th>
              </tr>
            </thead>
            <tbody>
              <%= for entry <- @filtered_standings do %>
                <tr class="rounded-2xl bg-space-900/70 text-sm text-foreground">
                  <td class="rounded-l-2xl px-4 py-4 font-semibold text-cream">
                    <%= tribe_name_for(entry.tribe_id, @world_tribes) || "Tribe ##{entry.tribe_id}" %>
                  </td>
                  <td class={["px-4 py-4", if(@is_leader, do: nil, else: "rounded-r-2xl")]}>
                    <span class={standing_badge_classes(entry.standing)}>
                      <%= standing_display(entry.standing) %>
                    </span>
                  </td>
                  <td :if={@is_leader} class="rounded-r-2xl px-4 py-4">
                    <form phx-change="set_standing" class="inline">
                      <input type="hidden" name="tribe_id" value={entry.tribe_id} />
                      <select
                        name="standing"
                        class="rounded-lg border border-space-600/80 bg-space-900/70 px-2 py-1 font-mono text-xs text-cream"
                      >
                        <option value="">Change...</option>
                        <%= for {label, value} <- standing_options() do %>
                          <option value={value} selected={value == standing_value(entry.standing)}>
                            <%= label %>
                          </option>
                        <% end %>
                      </select>
                    </form>
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
              <%= for {label, value} <- standing_options() do %>
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

  @doc """
  Renders the pilot overrides table with optional leader controls.
  """
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
                    <span class={standing_badge_classes(entry.standing)}>
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
              <%= for {label, value} <- standing_options() do %>
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

  @doc """
  Renders the default standing display with optional leader controls.
  """
  @spec default_standing_section(map()) :: Phoenix.LiveView.Rendered.t()
  def default_standing_section(assigns) do
    ~H"""
    <div class="rounded-[2rem] border border-space-600/80 bg-space-900/70 p-8 shadow-2xl shadow-black/40 backdrop-blur">
      <p class="font-mono text-xs uppercase tracking-[0.3em] text-quantum-300">Default Standing</p>
      <h2 class="mt-3 text-2xl font-semibold text-cream">Default Policy</h2>

      <div class="mt-4 flex items-center gap-4">
        <span class={standing_badge_classes(@default_standing)}>
          <%= standing_display(@default_standing) %>
        </span>
        <span class="rounded-full border border-space-600/80 bg-space-900/70 px-2 py-0.5 font-mono text-xs uppercase tracking-[0.2em] text-space-500">
          <%= nbsi_nrds_label(@default_standing) %>
        </span>
      </div>

      <div :if={@is_leader} class="mt-6 flex gap-3">
        <%= for {label, value} <- standing_options() do %>
          <button
            type="button"
            phx-click="set_default_standing"
            phx-value-standing={value}
            class={"rounded-full border px-3 py-1 font-mono text-xs uppercase tracking-[0.2em] transition hover:text-cream #{if standing_display(@default_standing) == label, do: "border-quantum-400/60 text-cream", else: "border-space-600/80 text-space-500 hover:border-quantum-400/40"}"}
          >
            <%= label %>
          </button>
        <% end %>
      </div>
    </div>
    """
  end

  @doc """
  Returns Tailwind CSS classes for a standing badge.
  """
  @spec standing_badge_classes(Diplomacy.standing_atom()) :: String.t()
  def standing_badge_classes(:hostile) do
    "inline-flex rounded-full border border-warning/60 bg-warning/10 px-3 py-1 font-mono text-xs uppercase tracking-[0.2em] text-warning"
  end

  def standing_badge_classes(:unfriendly) do
    "inline-flex rounded-full border border-warning/40 bg-warning/5 px-3 py-1 font-mono text-xs uppercase tracking-[0.2em] text-warning"
  end

  def standing_badge_classes(:neutral) do
    "inline-flex rounded-full border border-space-600/80 bg-space-900/70 px-3 py-1 font-mono text-xs uppercase tracking-[0.2em] text-space-500"
  end

  def standing_badge_classes(:friendly) do
    "inline-flex rounded-full border border-quantum-400/40 bg-quantum-400/10 px-3 py-1 font-mono text-xs uppercase tracking-[0.2em] text-quantum-300"
  end

  def standing_badge_classes(:allied) do
    "inline-flex rounded-full border border-success/40 bg-success/10 px-3 py-1 font-mono text-xs uppercase tracking-[0.2em] text-success"
  end

  @doc """
  Returns the 5-tier standing options list for dropdowns.
  """
  @spec standing_options() :: [{String.t(), non_neg_integer()}]
  def standing_options do
    [{"Hostile", 0}, {"Unfriendly", 1}, {"Neutral", 2}, {"Friendly", 3}, {"Allied", 4}]
  end

  @doc """
  Returns the numeric value stored for a standing atom.
  """
  @spec standing_value(Diplomacy.standing_atom()) :: non_neg_integer()
  def standing_value(:hostile), do: 0
  def standing_value(:unfriendly), do: 1
  def standing_value(:neutral), do: 2
  def standing_value(:friendly), do: 3
  def standing_value(:allied), do: 4

  @spec tribe_name_for(non_neg_integer(), [Diplomacy.world_tribe()]) :: String.t() | nil
  defp tribe_name_for(tribe_id, world_tribes) do
    case Enum.find(world_tribes, &(&1.id == tribe_id)) do
      %{name: name} -> name
      nil -> nil
    end
  end
end
