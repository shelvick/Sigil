defmodule SigilWeb.TribeOverviewLive do
  @moduledoc """
  Displays tribe overview: member list, aggregate assemblies, and standings summary.
  """

  use SigilWeb, :live_view

  import SigilWeb.AssemblyHelpers
  import SigilWeb.TribeHelpers, only: [authorize_tribe: 2]

  alias Sigil.{Diplomacy, Tribes}
  alias Sigil.Tribes.Tribe

  @doc """
  Mounts the tribe overview page for the given tribe_id.
  """
  @impl true
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) ::
          {:ok, Phoenix.LiveView.Socket.t()}
          | {:ok, Phoenix.LiveView.Socket.t(), keyword()}
  def mount(%{"tribe_id" => tribe_id_str}, _session, socket) do
    case authorize_tribe(tribe_id_str, socket) do
      {:ok, tribe_id} ->
        socket =
          socket
          |> assign_base_state(tribe_id)
          |> maybe_subscribe()
          |> load_tribe_data()
          |> load_standings_data()
          |> load_member_assemblies()

        {:ok, socket}

      {:error, :unauthorized} ->
        {:ok,
         socket
         |> put_flash(:error, "Not your tribe")
         |> redirect(to: ~p"/")}

      {:error, :unauthenticated} ->
        {:ok, redirect(socket, to: ~p"/")}
    end
  end

  @doc false
  @impl true
  @spec handle_info(term(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_info({:tribe_discovered, %Tribe{} = tribe}, socket) do
    if tribe.tribe_id == socket.assigns.tribe_id do
      {:noreply,
       socket
       |> assign(
         members: tribe.members,
         loading: false
       )
       |> load_member_assemblies()}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:standing_updated, _data}, socket) do
    {:noreply, refresh_standings(socket)}
  end

  def handle_info({:default_standing_updated, _standing}, socket) do
    {:noreply, refresh_standings(socket)}
  end

  def handle_info({:table_discovered, _tables}, socket) do
    {:noreply, refresh_standings(socket)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  @doc false
  @impl true
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <section class="relative overflow-hidden px-4 py-12 sm:px-6 lg:px-8">
      <div class="mx-auto max-w-6xl space-y-8">
        <.tribe_header
          tribe_id={@tribe_id}
          tribe_name={@tribe_name}
          tribe_short_name={@tribe_short_name}
          members={@members}
        />

        <%= if @loading do %>
          <div class="rounded-[2rem] border border-space-600/80 bg-space-900/70 p-8 shadow-2xl shadow-black/40 backdrop-blur">
            <p class="text-sm text-cream">Discovering tribe members...</p>
          </div>
        <% else %>
          <.members_panel members={@members} active_character={@active_character} />
          <.assemblies_panel member_assemblies={@member_assemblies} />
          <.standings_panel
            tribe_id={@tribe_id}
            standings_summary={@standings_summary}
            default_standing={@default_standing}
            has_standings_table={@has_standings_table}
          />
        <% end %>
      </div>
    </section>
    """
  end

  # ---------------------------------------------------------------------------
  # Components
  # ---------------------------------------------------------------------------

  @spec tribe_header(map()) :: Phoenix.LiveView.Rendered.t()
  defp tribe_header(assigns) do
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
            <%= length(@members) %> members
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

  @spec members_panel(map()) :: Phoenix.LiveView.Rendered.t()
  defp members_panel(assigns) do
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
                  <td class="rounded-l-2xl px-4 py-4 font-semibold text-cream">
                    <%= member.character_name || "Unknown" %>
                    <span
                      :if={@active_character && member.character_id == @active_character.id}
                      class="ml-2 font-mono text-xs text-quantum-300"
                    >
                      (you)
                    </span>
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

  @spec assemblies_panel(map()) :: Phoenix.LiveView.Rendered.t()
  defp assemblies_panel(assigns) do
    all_assemblies =
      Enum.flat_map(assigns.member_assemblies, fn {_member, assemblies} -> assemblies end)

    has_assemblies = all_assemblies != []

    type_counts =
      all_assemblies
      |> Enum.group_by(&assembly_type_label/1)
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
                          <%= assembly_type_label(assembly) %>
                        </td>
                        <td class="px-3 py-3">
                          <.link navigate={~p"/assembly/#{assembly.id}"} class="font-semibold text-cream hover:text-quantum-300">
                            <%= assembly_name(assembly) %>
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

  @spec standings_panel(map()) :: Phoenix.LiveView.Rendered.t()
  defp standings_panel(assigns) do
    ~H"""
    <div class="rounded-[2rem] border border-space-600/80 bg-space-900/70 p-8 shadow-2xl shadow-black/40 backdrop-blur">
      <p class="font-mono text-xs uppercase tracking-[0.3em] text-quantum-300">Diplomacy</p>
      <h2 class="mt-3 text-2xl font-semibold text-cream">Standings Summary</h2>

      <%= if @has_standings_table do %>
        <div class="mt-6 flex flex-wrap gap-3">
          <.standing_count_badge label="Hostile" count={@standings_summary.hostile} standing={:hostile} />
          <.standing_count_badge label="Unfriendly" count={@standings_summary.unfriendly} standing={:unfriendly} />
          <.standing_count_badge label="Neutral" count={@standings_summary.neutral} standing={:neutral} />
          <.standing_count_badge label="Friendly" count={@standings_summary.friendly} standing={:friendly} />
          <.standing_count_badge label="Allied" count={@standings_summary.allied} standing={:allied} />
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
        <p class="mt-6 text-sm text-space-500">No standings table configured</p>
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

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  @spec assign_base_state(Phoenix.LiveView.Socket.t(), non_neg_integer()) ::
          Phoenix.LiveView.Socket.t()
  defp assign_base_state(socket, tribe_id) do
    tribe_name_data = resolve_tribe_name(tribe_id, socket)

    assign(socket,
      page_title: tribe_name_data[:name] || "Tribe ##{tribe_id}",
      tribe_id: tribe_id,
      tribe_name: tribe_name_data[:name],
      tribe_short_name: tribe_name_data[:short_name],
      members: [],
      member_assemblies: [],
      standings_summary: %{hostile: 0, unfriendly: 0, neutral: 0, friendly: 0, allied: 0},
      default_standing: :neutral,
      has_standings_table: false,
      loading: false
    )
  end

  @spec resolve_tribe_name(non_neg_integer(), Phoenix.LiveView.Socket.t()) :: map() | nil
  defp resolve_tribe_name(tribe_id, socket) do
    cache_tables = socket.assigns[:cache_tables]

    if is_map(cache_tables) and is_map_key(cache_tables, :standings) do
      Diplomacy.get_tribe_name(tribe_id, tables: cache_tables)
    else
      nil
    end
  end

  @spec load_tribe_data(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp load_tribe_data(socket) do
    tribe_id = socket.assigns.tribe_id
    cache_tables = socket.assigns[:cache_tables]

    if is_map(cache_tables) and is_map_key(cache_tables, :tribes) do
      case Tribes.get_tribe(tribe_id, tables: cache_tables) do
        %Tribe{members: members} ->
          assign(socket, members: members, loading: false)

        nil ->
          maybe_discover_tribe(socket, tribe_id, cache_tables)
      end
    else
      socket
    end
  end

  @spec maybe_discover_tribe(Phoenix.LiveView.Socket.t(), non_neg_integer(), map()) ::
          Phoenix.LiveView.Socket.t()
  defp maybe_discover_tribe(socket, tribe_id, cache_tables) do
    if connected?(socket) do
      pubsub = socket.assigns[:pubsub]
      Tribes.discover_members(tribe_id, tables: cache_tables, pubsub: pubsub)
    end

    assign(socket, loading: true)
  end

  @spec load_standings_data(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp load_standings_data(socket) do
    cache_tables = socket.assigns[:cache_tables]
    sender = socket.assigns.current_account.address

    if is_map(cache_tables) and is_map_key(cache_tables, :standings) do
      opts = [tables: cache_tables, sender: sender]
      active_table = Diplomacy.get_active_table(opts)
      has_table = active_table != nil

      standings = Diplomacy.list_standings(tables: cache_tables)
      default = Diplomacy.get_default_standing(tables: cache_tables)

      summary = compute_standings_summary(standings)

      assign(socket,
        has_standings_table: has_table,
        standings_summary: summary,
        default_standing: default
      )
    else
      socket
    end
  end

  @spec load_member_assemblies(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp load_member_assemblies(socket) do
    tribe_id = socket.assigns.tribe_id
    cache_tables = socket.assigns[:cache_tables]

    if is_map(cache_tables) and is_map_key(cache_tables, :tribes) do
      member_assemblies = Tribes.list_tribe_assemblies(tribe_id, tables: cache_tables)
      assign(socket, member_assemblies: member_assemblies)
    else
      socket
    end
  end

  @spec maybe_subscribe(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp maybe_subscribe(socket) do
    pubsub = socket.assigns[:pubsub]

    if connected?(socket) and pubsub do
      Phoenix.PubSub.subscribe(pubsub, "tribes")
      Phoenix.PubSub.subscribe(pubsub, "diplomacy")
    end

    socket
  end

  @spec refresh_standings(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp refresh_standings(socket) do
    load_standings_data(socket)
  end

  @spec compute_standings_summary([Diplomacy.tribe_entry()]) :: map()
  defp compute_standings_summary(standings) do
    base = %{hostile: 0, unfriendly: 0, neutral: 0, friendly: 0, allied: 0}

    Enum.reduce(standings, base, fn %{standing: standing}, acc ->
      Map.update!(acc, standing, &(&1 + 1))
    end)
  end

  @spec standing_display(Diplomacy.standing_atom()) :: String.t()
  defp standing_display(:hostile), do: "Hostile"
  defp standing_display(:unfriendly), do: "Unfriendly"
  defp standing_display(:neutral), do: "Neutral"
  defp standing_display(:friendly), do: "Friendly"
  defp standing_display(:allied), do: "Allied"

  @spec nbsi_nrds_label(Diplomacy.standing_atom()) :: String.t()
  defp nbsi_nrds_label(:hostile), do: "NBSI"
  defp nbsi_nrds_label(:unfriendly), do: "NBSI"
  defp nbsi_nrds_label(:neutral), do: "NRDS"
  defp nbsi_nrds_label(:friendly), do: "NRDS"
  defp nbsi_nrds_label(:allied), do: "NRDS"
end
