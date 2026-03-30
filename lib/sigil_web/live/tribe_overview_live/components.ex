defmodule SigilWeb.TribeOverviewLive.Components do
  @moduledoc """
  Template components for the tribe overview LiveView.
  """

  use SigilWeb, :html

  import SigilWeb.AssemblyHelpers
  import SigilWeb.TribeHelpers, only: [nbsi_nrds_label: 1, standing_display: 1]

  alias Sigil.Diplomacy

  @doc """
  Renders the tribe overview header.
  """
  @spec tribe_header(map()) :: Phoenix.LiveView.Rendered.t()
  def tribe_header(assigns) do
    ~H"""
    <div class="rounded-[2rem] border border-space-600/80 bg-space-900/70 p-8 shadow-2xl shadow-black/40 backdrop-blur">
      <div class="flex items-center justify-between gap-4">
        <div>
          <p class="font-mono text-xs uppercase tracking-[0.35em] text-quantum-300">
            Tribe overview
          </p>
          <h1 class="mt-3 text-4xl font-semibold text-cream">
            <%= @tribe_name || "Tribe ##{@tribe_id}" %>
          </h1>
          <span :if={@tribe_short_name} class="mt-2 inline-flex rounded-full border border-quantum-600/60 bg-quantum-700/40 px-3 py-1 font-mono text-xs uppercase tracking-[0.25em] text-quantum-300">
            <%= @tribe_short_name %>
          </span>
        </div>
        <div class="flex items-center gap-3">
          <span class="rounded-full border border-space-600/80 bg-space-900/70 px-3 py-1 font-mono text-xs uppercase tracking-[0.2em] text-space-500">
            <%= length(@members) %> <%= if length(@members) == 1, do: "member", else: "members" %>
          </span>
          <.link
            navigate={~p"/tribe/#{@tribe_id}/diplomacy"}
            class="rounded-full border border-quantum-400/40 px-4 py-2 font-mono text-xs uppercase tracking-[0.24em] text-quantum-300 transition hover:border-quantum-300 hover:text-cream"
          >
            Diplomacy
          </.link>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders the tribe member list.
  """
  @spec members_panel(map()) :: Phoenix.LiveView.Rendered.t()
  def members_panel(assigns) do
    sorted_members =
      assigns.members
      |> Enum.sort_by(fn m -> {!m.connected, m.character_name || ""} end)

    assigns = assign(assigns, :sorted_members, sorted_members)

    ~H"""
    <div class="rounded-[2rem] border border-space-600/80 bg-space-900/70 p-8 shadow-2xl shadow-black/40 backdrop-blur">
      <p class="font-mono text-xs uppercase tracking-[0.3em] text-quantum-300">Members</p>
      <h2 class="mt-3 text-2xl font-semibold text-cream">Tribe Members</h2>

      <%= if @sorted_members == [] do %>
        <p class="mt-6 text-sm text-space-500">No members found</p>
      <% else %>
        <div class="mt-6 overflow-x-auto">
          <table class="min-w-full border-separate border-spacing-y-3">
            <thead>
              <tr class="font-mono text-xs uppercase tracking-[0.25em] text-space-500">
                <th class="px-4 py-2 text-left">Name</th>
                <th class="px-4 py-2 text-left">Status</th>
              </tr>
            </thead>
            <tbody>
              <%= for member <- @sorted_members do %>
                <tr class="rounded-2xl bg-space-900/70 text-sm text-foreground">
                  <td class="rounded-l-2xl px-4 py-4">
                    <p class="font-semibold text-cream">
                      <%= member.character_name || "Unknown" %>
                      <span
                        :if={@active_character && member.character_id == @active_character.id}
                        class="ml-2 font-mono text-xs text-quantum-300"
                      >
                        (you)
                      </span>
                    </p>
                    <p class="mt-0.5 font-mono text-xs text-space-500"><%= truncate_id(member.character_address) %></p>
                  </td>
                  <td class="rounded-r-2xl px-4 py-4">
                    <%= if member.connected do %>
                      <span class="inline-flex rounded-full border border-success/40 bg-success/10 px-3 py-1 font-mono text-xs uppercase tracking-[0.2em] text-success">
                        Connected
                      </span>
                    <% else %>
                      <span class="inline-flex rounded-full border border-space-600/80 bg-space-900/70 px-3 py-1 font-mono text-xs uppercase tracking-[0.2em] text-space-500">
                        Chain-only
                      </span>
                    <% end %>
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      <% end %>
    </div>
    """
  end

  @doc """
  Renders the grouped assembly list.
  """
  @spec assemblies_panel(map()) :: Phoenix.LiveView.Rendered.t()
  def assemblies_panel(assigns) do
    all_assemblies =
      Enum.flat_map(assigns.member_assemblies, fn {_member, assemblies} -> assemblies end)

    has_assemblies = all_assemblies != []

    type_counts =
      all_assemblies
      |> Enum.group_by(&assembly_type_label(&1, assigns[:static_data]))
      |> Enum.map(fn {type, list} -> {type, length(list)} end)
      |> Enum.sort_by(fn {type, _count} -> type end)

    assigns =
      assigns
      |> assign(:has_assemblies, has_assemblies)
      |> assign(:type_counts, type_counts)
      |> assign(:total_count, length(all_assemblies))

    ~H"""
    <div class="rounded-[2rem] border border-space-600/80 bg-space-900/70 p-8 shadow-2xl shadow-black/40 backdrop-blur">
      <div class="flex items-center justify-between gap-4">
        <div>
          <p class="font-mono text-xs uppercase tracking-[0.3em] text-quantum-300">Fleet</p>
          <h2 class="mt-3 text-2xl font-semibold text-cream">Assemblies</h2>
        </div>
        <span :if={@has_assemblies} class="rounded-full border border-space-600/80 bg-space-900/70 px-3 py-1 font-mono text-xs uppercase tracking-[0.2em] text-space-500">
          <%= @total_count %> total
        </span>
      </div>

      <%= if @has_assemblies do %>
        <div class="mt-4 flex flex-wrap gap-3">
          <%= for {type, count} <- @type_counts do %>
            <span class="rounded-full border border-quantum-600/60 bg-quantum-700/40 px-3 py-1 font-mono text-xs uppercase tracking-[0.25em] text-quantum-300">
              <%= type %>: <%= count %>
            </span>
          <% end %>
        </div>

        <div class="mt-6 space-y-6">
          <%= for {member, assemblies} <- @member_assemblies do %>
            <div :if={assemblies != []} class="rounded-2xl border border-space-600/60 bg-space-800/60 p-4">
              <p class="font-semibold text-cream"><%= member.character_name || "Unknown" %></p>
              <div class="mt-3 overflow-x-auto">
                <table class="min-w-full border-separate border-spacing-y-2">
                  <tbody>
                    <%= for assembly <- assemblies do %>
                      <tr class="cursor-pointer rounded-2xl bg-space-900/70 text-sm text-foreground transition hover:bg-space-800/80" phx-click={JS.navigate(~p"/assembly/#{assembly.id}")}>
                        <td class={["rounded-l-2xl px-3 py-3 font-mono text-xs uppercase tracking-[0.2em]", type_text_color(assembly)]}>
                          <%= assembly_type_label(assembly, assigns[:static_data]) %>
                        </td>
                        <td class="px-3 py-3">
                          <.link navigate={~p"/assembly/#{assembly.id}"} class="font-semibold text-cream hover:text-quantum-300">
                            <%= assembly_name(assembly, assigns[:intel_opts] || []) %>
                          </.link>
                        </td>
                        <td class="rounded-r-2xl px-3 py-3">
                          <span class={status_badge_classes(assembly)}>
                            <%= assembly_status(assembly) %>
                          </span>
                        </td>
                      </tr>
                    <% end %>
                  </tbody>
                </table>
              </div>
            </div>
          <% end %>
        </div>
      <% else %>
        <p class="mt-6 text-sm text-space-500">No assemblies found</p>
      <% end %>
    </div>
    """
  end

  @doc """
  Renders the intel summary panel.
  """
  @spec intel_panel(map()) :: Phoenix.LiveView.Rendered.t()
  def intel_panel(assigns) do
    ~H"""
    <div class="rounded-[2rem] border border-space-600/80 bg-space-900/70 p-8 shadow-2xl shadow-black/40 backdrop-blur">
      <div class="flex items-center justify-between gap-4">
        <div>
          <p class="font-mono text-xs uppercase tracking-[0.3em] text-quantum-300">Intel</p>
          <h2 class="mt-3 text-2xl font-semibold text-cream">Shared Intelligence</h2>
        </div>
        <.link
          navigate={~p"/tribe/#{@tribe_id}/intel"}
          class="rounded-full border border-quantum-400/40 px-4 py-2 font-mono text-xs uppercase tracking-[0.24em] text-quantum-300 transition hover:border-quantum-300 hover:text-cream"
        >
          View Intel
        </.link>
      </div>

      <div class="mt-6 flex flex-wrap gap-3 text-sm text-cream">
        <span><%= @intel_summary.locations %> assemblies with known locations</span>
        <span><%= @intel_summary.scouting %> scouting reports</span>
      </div>
    </div>
    """
  end

  @doc """
  Renders the standings summary panel.
  """
  @spec standings_panel(map()) :: Phoenix.LiveView.Rendered.t()
  def standings_panel(assigns) do
    reputation_rows =
      assigns.reputation_scores
      |> Map.values()
      |> Enum.sort_by(& &1.target_tribe_id)

    assigns = assign(assigns, :reputation_rows, reputation_rows)

    ~H"""
    <div class="rounded-[2rem] border border-space-600/80 bg-space-900/70 p-8 shadow-2xl shadow-black/40 backdrop-blur">
      <p class="font-mono text-xs uppercase tracking-[0.3em] text-quantum-300">Tribe Custodian</p>
      <h2 class="mt-3 text-2xl font-semibold text-cream">Standings Summary</h2>

      <%= if @has_custodian do %>
        <div class="mt-6 flex flex-wrap gap-3">
          <.standing_count_badge label="Hostile" count={@standings_summary.hostile} standing={:hostile} />
          <.standing_count_badge label="Unfriendly" count={@standings_summary.unfriendly} standing={:unfriendly} />
          <.standing_count_badge label="Neutral" count={@standings_summary.neutral} standing={:neutral} />
          <.standing_count_badge label="Friendly" count={@standings_summary.friendly} standing={:friendly} />
          <.standing_count_badge label="Allied" count={@standings_summary.allied} standing={:allied} />
        </div>

        <p :if={@oracle_enabled} class="mt-4 text-sm text-cream">
          <%= @auto_managed_count %> standings auto-managed
        </p>

        <div :if={@reputation_rows != []} class="mt-4 space-y-2">
          <%= for row <- @reputation_rows do %>
            <div class="flex items-center justify-between rounded-xl border border-space-600/60 bg-space-800/60 px-3 py-2">
              <span class="font-mono text-xs text-space-500">Tribe #<%= row.target_tribe_id %></span>
              <div class="flex items-center gap-2">
                <span class={score_badge_classes(row.score)}><%= row.score %></span>
                <span class={chip_classes(row.pinned)}><%= if row.pinned, do: "MANUAL", else: "AUTO" %></span>
              </div>
            </div>
          <% end %>
        </div>

        <div class="mt-4">
          <p class="text-sm text-cream">
            Default: <%= standing_display(@default_standing) %>
            <span class="ml-2 rounded-full border border-space-600/80 bg-space-900/70 px-2 py-0.5 font-mono text-xs uppercase tracking-[0.2em] text-space-500">
              <%= nbsi_nrds_label(@default_standing) %>
            </span>
          </p>
        </div>

        <.link
          navigate={~p"/tribe/#{@tribe_id}/diplomacy"}
          class="mt-6 inline-flex rounded-full border border-quantum-400/40 px-4 py-2 font-mono text-xs uppercase tracking-[0.24em] text-quantum-300 transition hover:border-quantum-300 hover:text-cream"
        >
          Manage Standings
        </.link>
      <% else %>
        <p class="mt-6 text-sm text-space-500">No Tribe Custodian configured</p>
        <.link
          navigate={~p"/tribe/#{@tribe_id}/diplomacy"}
          class="mt-4 inline-flex rounded-full border border-quantum-400/40 px-4 py-2 font-mono text-xs uppercase tracking-[0.24em] text-quantum-300 transition hover:border-quantum-300 hover:text-cream"
        >
          Set Up Diplomacy
        </.link>
      <% end %>
    </div>
    """
  end

  @spec standing_count_badge(map()) :: Phoenix.LiveView.Rendered.t()
  defp standing_count_badge(assigns) do
    assigns = assign(assigns, :badge_classes, standing_count_classes(assigns.standing))

    ~H"""
    <span :if={@count > 0} class={@badge_classes}>
      <%= @label %>: <%= @count %>
    </span>
    """
  end

  @spec score_badge_classes(integer()) :: String.t()
  defp score_badge_classes(score) when score < 0,
    do:
      "reputation-score-negative rounded-full border border-warning/40 bg-warning/10 px-2 py-0.5 font-mono text-xs text-warning"

  defp score_badge_classes(score) when score > 0,
    do:
      "reputation-score-positive rounded-full border border-success/40 bg-success/10 px-2 py-0.5 font-mono text-xs text-success"

  defp score_badge_classes(_score),
    do:
      "reputation-score-neutral rounded-full border border-space-600/80 bg-space-900/70 px-2 py-0.5 font-mono text-xs text-space-500"

  @spec chip_classes(boolean()) :: String.t()
  defp chip_classes(true),
    do:
      "rounded-full border border-warning/40 bg-warning/10 px-2 py-0.5 font-mono text-xs uppercase tracking-[0.2em] text-warning"

  defp chip_classes(false),
    do:
      "rounded-full border border-quantum-400/40 bg-quantum-400/10 px-2 py-0.5 font-mono text-xs uppercase tracking-[0.2em] text-quantum-300"

  @spec standing_count_classes(Diplomacy.standing_atom()) :: String.t()
  defp standing_count_classes(:hostile) do
    "rounded-full border border-warning/40 bg-warning/10 px-3 py-1 font-mono text-xs uppercase tracking-[0.2em] text-warning"
  end

  defp standing_count_classes(:unfriendly) do
    "rounded-full border border-warning/40 bg-warning/10 px-3 py-1 font-mono text-xs uppercase tracking-[0.2em] text-warning"
  end

  defp standing_count_classes(:neutral) do
    "rounded-full border border-space-500/40 bg-space-500/10 px-3 py-1 font-mono text-xs uppercase tracking-[0.2em] text-space-500"
  end

  defp standing_count_classes(:friendly) do
    "rounded-full border border-quantum-300/40 bg-quantum-300/10 px-3 py-1 font-mono text-xs uppercase tracking-[0.2em] text-quantum-300"
  end

  defp standing_count_classes(:allied) do
    "rounded-full border border-success/40 bg-success/10 px-3 py-1 font-mono text-xs uppercase tracking-[0.2em] text-success"
  end
end
