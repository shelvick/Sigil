defmodule SigilWeb.TribeOverviewLive do
  @moduledoc """
  Displays tribe overview: member list, aggregate assemblies, diplomacy summary,
  and intel summary.
  """

  use SigilWeb, :live_view

  import SigilWeb.TribeHelpers, only: [authorize_tribe: 2]

  alias Sigil.{Diplomacy, Intel, Tribes, Worlds}
  alias Sigil.Intel.IntelReport
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
          |> load_intel_summary()

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
       |> assign(members: tribe.members, loading: false)
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

  def handle_info({:custodian_discovered, _custodian}, socket) do
    {:noreply, refresh_standings(socket)}
  end

  def handle_info({:custodian_created, _custodian}, socket) do
    {:noreply, refresh_standings(socket)}
  end

  def handle_info({:reputation_updated, _payload}, socket) do
    {:noreply, refresh_standings(socket)}
  end

  def handle_info({:reputation_pinned, _payload}, socket) do
    {:noreply, refresh_standings(socket)}
  end

  def handle_info({:reputation_unpinned, _payload}, socket) do
    {:noreply, refresh_standings(socket)}
  end

  def handle_info({:intel_updated, %IntelReport{tribe_id: tribe_id}}, socket)
      when tribe_id == socket.assigns.tribe_id do
    {:noreply, load_intel_summary(socket)}
  end

  def handle_info({:intel_deleted, %IntelReport{tribe_id: tribe_id}}, socket)
      when tribe_id == socket.assigns.tribe_id do
    {:noreply, load_intel_summary(socket)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  @doc false
  @impl true
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <section class="relative overflow-hidden px-4 py-12 sm:px-6 lg:px-8">
      <div class="mx-auto max-w-6xl space-y-8">
        <SigilWeb.TribeOverviewLive.Components.tribe_header
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
          <SigilWeb.TribeOverviewLive.Components.members_panel members={@members} active_character={@active_character} />
          <SigilWeb.TribeOverviewLive.Components.assemblies_panel
            member_assemblies={@member_assemblies}
            static_data={@static_data}
            intel_opts={[cache_tables: @cache_tables, tribe_id: @tribe_id]}
          />
          <SigilWeb.TribeOverviewLive.Components.intel_panel tribe_id={@tribe_id} intel_summary={@intel_summary} />
          <SigilWeb.TribeOverviewLive.Components.standings_panel
            tribe_id={@tribe_id}
            standings_summary={@standings_summary}
            default_standing={@default_standing}
            has_custodian={@has_custodian}
            reputation_scores={@reputation_scores}
            auto_managed_count={@auto_managed_count}
            oracle_enabled={@oracle_enabled}
          />
        <% end %>
      </div>
    </section>
    """
  end

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
      has_custodian: false,
      reputation_scores: %{},
      auto_managed_count: 0,
      oracle_enabled: false,
      intel_summary: %{locations: 0, scouting: 0},
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

      Tribes.discover_members(tribe_id,
        tables: cache_tables,
        pubsub: pubsub,
        world: socket.assigns.world
      )
    end

    assign(socket, loading: true)
  end

  @spec load_standings_data(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp load_standings_data(socket) do
    cache_tables = socket.assigns[:cache_tables]
    sender = socket.assigns.current_account.address
    tribe_id = socket.assigns[:tribe_id]

    if is_map(cache_tables) and is_map_key(cache_tables, :standings) do
      opts = [
        tables: cache_tables,
        sender: sender,
        tribe_id: tribe_id,
        pubsub: socket.assigns[:pubsub],
        world: socket.assigns.world
      ]

      active_custodian = Diplomacy.get_active_custodian(opts)
      standings = Diplomacy.list_standings(opts)
      default_standing = Diplomacy.get_default_standing(opts)

      reputation_scores =
        opts
        |> Diplomacy.list_reputation_scores()
        |> Map.new(&{&1.target_tribe_id, &1})

      auto_managed_count =
        standings
        |> Enum.count(fn %{tribe_id: target_tribe_id} ->
          case Map.get(reputation_scores, target_tribe_id) do
            %{pinned: true} -> false
            _other -> true
          end
        end)

      assign(socket,
        has_custodian: active_custodian != nil,
        standings_summary: compute_standings_summary(standings),
        default_standing: default_standing,
        reputation_scores: reputation_scores,
        auto_managed_count: auto_managed_count,
        oracle_enabled: Diplomacy.oracle_enabled?(opts)
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
      world = socket.assigns.world
      diplomacy_opts = [world: world]

      Phoenix.PubSub.subscribe(pubsub, Worlds.topic(world, "tribes"))
      Phoenix.PubSub.subscribe(pubsub, Diplomacy.legacy_topic(diplomacy_opts))
      Phoenix.PubSub.subscribe(pubsub, Worlds.topic(world, "reputation"))

      if intel_enabled?(socket.assigns.cache_tables) do
        Phoenix.PubSub.subscribe(pubsub, intel_topic(socket.assigns.tribe_id, world))
      end
    end

    socket
  end

  @spec refresh_standings(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp refresh_standings(socket), do: load_standings_data(socket)

  @spec load_intel_summary(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp load_intel_summary(socket) do
    if intel_enabled?(socket.assigns.cache_tables) do
      reports = Intel.list_intel(socket.assigns.tribe_id, intel_opts(socket))

      summary = %{
        locations: Enum.count(reports, &(&1.report_type == :location)),
        scouting: Enum.count(reports, &(&1.report_type == :scouting))
      }

      assign(socket, :intel_summary, summary)
    else
      assign(socket, :intel_summary, %{locations: 0, scouting: 0})
    end
  end

  @spec compute_standings_summary([Diplomacy.tribe_entry()]) :: map()
  defp compute_standings_summary(standings) do
    base = %{hostile: 0, unfriendly: 0, neutral: 0, friendly: 0, allied: 0}

    Enum.reduce(standings, base, fn %{standing: standing}, acc ->
      Map.update!(acc, standing, &(&1 + 1))
    end)
  end

  @spec intel_opts(Phoenix.LiveView.Socket.t()) :: Intel.options()
  defp intel_opts(socket) do
    [
      authorized_tribe_id: socket.assigns.tribe_id,
      tables: socket.assigns.cache_tables,
      pubsub: socket.assigns.pubsub,
      world: socket.assigns.world
    ]
  end

  @spec intel_enabled?(map() | nil) :: boolean()
  defp intel_enabled?(cache_tables),
    do: is_map(cache_tables) and Map.has_key?(cache_tables, :intel)

  @spec intel_topic(integer(), Worlds.world_name()) :: String.t()
  defp intel_topic(tribe_id, world), do: Intel.topic(tribe_id, world: world)
end
