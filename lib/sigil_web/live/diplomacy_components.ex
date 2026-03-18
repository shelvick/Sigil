defmodule SigilWeb.DiplomacyLive.Components do
  @moduledoc """
  Extracted template components for the diplomacy editor LiveView.

  Contains the standings editor panels: no-table CTA, table selection,
  tribe standings table, pilot overrides, default standing selector,
  and the wallet signing overlay.
  """

  use SigilWeb, :html

  import SigilWeb.AssemblyHelpers, only: [truncate_id: 1]

  alias Sigil.Diplomacy

  @doc """
  Renders the no-table state with a create standings table button.
  """
  @spec no_table_view(map()) :: Phoenix.LiveView.Rendered.t()
  def no_table_view(assigns) do
    ~H"""
    <div class="rounded-[2rem] border border-space-600/80 bg-space-900/70 p-8 shadow-2xl shadow-black/40 backdrop-blur">
      <h2 class="text-2xl font-semibold text-cream">No Standings Table</h2>
      <p class="mt-4 text-sm text-space-500">
        Your tribe doesn&#39;t have a Standings Table yet. Create one to manage diplomatic standings with other tribes.
      </p>
      <button
        type="button"
        phx-click="create_table"
        class="mt-6 inline-flex rounded-full bg-quantum-400 px-5 py-3 font-mono text-xs uppercase tracking-[0.25em] text-space-950 transition hover:bg-quantum-300"
      >
        Create Standings Table
      </button>
    </div>
    """
  end

  @doc """
  Renders the table selection list when multiple standings tables exist.
  """
  @spec select_table_view(map()) :: Phoenix.LiveView.Rendered.t()
  def select_table_view(assigns) do
    ~H"""
    <div class="rounded-[2rem] border border-space-600/80 bg-space-900/70 p-8 shadow-2xl shadow-black/40 backdrop-blur">
      <h2 class="text-2xl font-semibold text-cream">Multiple Standings Tables</h2>
      <p class="mt-4 text-sm text-space-500">
        Multiple StandingsTable objects found. Select one to manage.
      </p>
      <div class="mt-6 space-y-3">
        <%= for table <- @available_tables do %>
          <div
            phx-click="select_table"
            phx-value-id={table.object_id}
            class="cursor-pointer rounded-2xl border border-space-600/80 bg-space-800/60 p-4 transition hover:border-quantum-400/40"
          >
            <p class="font-mono text-sm text-cream"><%= truncate_id(table.object_id) %></p>
          </div>
        <% end %>
      </div>
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
  Renders the tribe standings table with search, inline edit, and add form.
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
      <p class="font-mono text-xs uppercase tracking-[0.3em] text-quantum-300">Tribe Standings</p>
      <h2 class="mt-3 text-2xl font-semibold text-cream">Manage Standings</h2>

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
                <th class="px-4 py-2 text-left">Actions</th>
              </tr>
            </thead>
            <tbody>
              <%= for entry <- @filtered_standings do %>
                <tr class="rounded-2xl bg-space-900/70 text-sm text-foreground">
                  <td class="rounded-l-2xl px-4 py-4 font-semibold text-cream">
                    <%= tribe_name_for(entry.tribe_id, @world_tribes) || "Tribe ##{entry.tribe_id}" %>
                  </td>
                  <td class="px-4 py-4">
                    <span class={standing_badge_classes(entry.standing)}>
                      <%= standing_display(entry.standing) %>
                    </span>
                  </td>
                  <td class="rounded-r-2xl px-4 py-4">
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

      <div class="mt-6 rounded-2xl border border-space-600/60 bg-space-800/60 p-4">
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
  Renders the pilot overrides table with add form.
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

      <div class="mt-6 rounded-2xl border border-space-600/60 bg-space-800/60 p-4">
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
  Renders the default standing selector with NBSI/NRDS labels.
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

      <div class="mt-6 flex gap-3">
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

  # ---------------------------------------------------------------------------
  # Shared display helpers
  # ---------------------------------------------------------------------------

  @doc """
  Returns the display label for a standing atom.
  """
  @spec standing_display(Diplomacy.standing_atom()) :: String.t()
  def standing_display(:hostile), do: "Hostile"
  def standing_display(:unfriendly), do: "Unfriendly"
  def standing_display(:neutral), do: "Neutral"
  def standing_display(:friendly), do: "Friendly"
  def standing_display(:allied), do: "Allied"

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
  Returns the NBSI or NRDS policy label for a standing.
  """
  @spec nbsi_nrds_label(Diplomacy.standing_atom()) :: String.t()
  def nbsi_nrds_label(:hostile), do: "NBSI"
  def nbsi_nrds_label(:unfriendly), do: "NBSI"
  def nbsi_nrds_label(:neutral), do: "NRDS"
  def nbsi_nrds_label(:friendly), do: "NRDS"
  def nbsi_nrds_label(:allied), do: "NRDS"

  @doc """
  Returns the 5-tier standing options list for dropdowns.
  """
  @spec standing_options() :: [{String.t(), non_neg_integer()}]
  def standing_options do
    [{"Hostile", 0}, {"Unfriendly", 1}, {"Neutral", 2}, {"Friendly", 3}, {"Allied", 4}]
  end

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
