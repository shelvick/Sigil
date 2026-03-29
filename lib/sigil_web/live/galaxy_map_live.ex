defmodule SigilWeb.GalaxyMapLive do
  @moduledoc """
  Interactive galaxy map page backed by StaticData and intel overlays.
  """

  use SigilWeb, :live_view

  alias Sigil.{Intel, IntelMarket, StaticData}
  alias Sigil.Intel.IntelListing
  alias Sigil.Intel.IntelReport
  alias SigilWeb.GalaxyMapLive.Data

  import SigilWeb.GalaxyMapLive.Components, only: [map_panel: 1, detail_panel: 1]

  @doc false
  @impl true
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def mount(params, _session, socket) do
    tribe_id =
      resolve_tribe_id(socket.assigns[:active_character], socket.assigns[:current_account])

    socket =
      socket
      |> assign(
        page_title: "Galaxy Map",
        map_ready: false,
        target_system_id: parse_system_id(Map.get(params, "system_id")),
        tribe_id: tribe_id,
        selected_system: nil,
        detail_data: nil,
        overlay_toggles: %{
          "tribe_locations" => true,
          "tribe_scouting" => true,
          "marketplace" => true
        },
        static_data_available: false,
        system_names: %{},
        system_constellations: %{},
        constellation_names: %{},
        init_systems_payload: %{"systems" => []},
        init_constellations_payload: %{"constellations" => []},
        tribe_location_overlays: [],
        tribe_scouting_overlays: [],
        marketplace_overlay_map: %{},
        marketplace_overlays: []
      )

    socket =
      socket
      |> load_static_data()
      |> maybe_load_connected_data()

    {:ok, socket}
  end

  @doc false
  @impl true
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("map_ready", _params, socket) do
    socket =
      socket
      |> assign(:map_ready, true)
      |> push_event("init_systems", socket.assigns.init_systems_payload)
      |> push_event("init_constellations", socket.assigns.init_constellations_payload)
      |> push_event("update_overlays", overlay_payload(socket.assigns))

    socket =
      if is_integer(socket.assigns.target_system_id) do
        push_event(socket, "select_system", %{"system_id" => socket.assigns.target_system_id})
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_event("system_selected", %{"system_id" => system_id}, socket) do
    case parse_system_id(system_id) do
      system_id when is_integer(system_id) ->
        {:noreply,
         assign(socket,
           selected_system: system_id,
           detail_data: Data.build_detail_data(system_id, socket.assigns)
         )}

      _other ->
        {:noreply, socket}
    end
  end

  def handle_event("system_deselected", _params, socket) do
    {:noreply, assign(socket, selected_system: nil, detail_data: nil)}
  end

  def handle_event("toggle_overlay", %{"layer" => layer}, socket) do
    case socket.assigns.overlay_toggles do
      %{^layer => visible} = toggles ->
        new_visible = !visible
        socket = assign(socket, :overlay_toggles, Map.put(toggles, layer, new_visible))
        payload = overlay_payload_for(socket)

        socket =
          socket
          |> push_event("toggle_overlay", %{"layer" => layer, "visible" => new_visible})
          |> push_event("update_overlays", payload)

        {:noreply, socket}

      _other ->
        {:noreply, socket}
    end
  end

  @doc false
  @impl true
  @spec handle_info(term(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_info({:intel_updated, %IntelReport{} = report}, socket) do
    socket =
      case report do
        %IntelReport{report_type: :location, solar_system_id: system_id, assembly_id: assembly_id}
        when is_integer(system_id) and is_binary(assembly_id) ->
          if known_system?(socket, system_id) do
            entry = %{system_id: system_id, assembly_id: assembly_id, label: report.label}

            locations =
              socket.assigns.tribe_location_overlays
              |> Enum.reject(&(&1.assembly_id == assembly_id))
              |> Kernel.++([entry])

            assign(socket, :tribe_location_overlays, locations)
          else
            socket
          end

        %IntelReport{report_type: :scouting, solar_system_id: system_id}
        when is_integer(system_id) ->
          if known_system?(socket, system_id) do
            scouting = socket.assigns.tribe_scouting_overlays ++ [%{system_id: system_id}]
            assign(socket, :tribe_scouting_overlays, scouting)
          else
            socket
          end

        _other ->
          socket
      end

    {:noreply, refresh_overlays(socket)}
  end

  def handle_info({:intel_deleted, %IntelReport{} = report}, socket) do
    socket =
      case report do
        %IntelReport{report_type: :location, assembly_id: assembly_id}
        when is_binary(assembly_id) ->
          assign(
            socket,
            :tribe_location_overlays,
            Enum.reject(socket.assigns.tribe_location_overlays, &(&1.assembly_id == assembly_id))
          )

        %IntelReport{report_type: :scouting, solar_system_id: system_id}
        when is_integer(system_id) ->
          assign(
            socket,
            :tribe_scouting_overlays,
            remove_first(socket.assigns.tribe_scouting_overlays, &(&1.system_id == system_id))
          )

        _other ->
          socket
      end

    {:noreply, refresh_overlays(socket)}
  end

  def handle_info({:listing_created, %IntelListing{} = listing}, socket) do
    socket =
      if listing.status == :active, do: put_marketplace_listing(socket, listing), else: socket

    {:noreply, refresh_overlays(socket)}
  end

  def handle_info({:listing_purchased, %IntelListing{} = listing}, socket) do
    socket =
      case socket.assigns[:current_account] do
        %{address: buyer_address} when buyer_address == listing.buyer_address ->
          put_marketplace_listing(socket, listing)

        _other ->
          remove_marketplace_listing(socket, listing.id)
      end

    {:noreply, refresh_overlays(socket)}
  end

  def handle_info({:listing_cancelled, %IntelListing{id: listing_id}}, socket) do
    {:noreply, socket |> remove_marketplace_listing(listing_id) |> refresh_overlays()}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  @doc false
  @impl true
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <section class="relative overflow-hidden px-4 py-12 sm:px-6 lg:px-8">
      <div class="mx-auto max-w-6xl space-y-8">
        <.map_panel static_data_available={@static_data_available} tribe_id={@tribe_id} />
        <.detail_panel detail_data={@detail_data} tribe_id={@tribe_id} />
      </div>
    </section>
    """
  end

  @spec load_static_data(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp load_static_data(socket) do
    case socket.assigns[:static_data] do
      static_data when is_pid(static_data) ->
        systems = StaticData.list_solar_systems(static_data)
        constellations = StaticData.list_constellations(static_data)

        assign(socket,
          static_data_available: true,
          system_names: Map.new(systems, &{&1.id, &1.name}),
          system_constellations: Map.new(systems, &{&1.id, &1.constellation_id}),
          constellation_names: Map.new(constellations, &{&1.id, &1.name}),
          init_systems_payload: %{"systems" => Data.map_system_payload(systems)},
          init_constellations_payload: %{
            "constellations" => Data.map_constellation_payload(constellations)
          }
        )

      _other ->
        assign(socket, static_data_available: false)
    end
  end

  @spec load_overlays(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp load_overlays(socket) do
    {tribe_locations, tribe_scouting} = load_tribe_overlays(socket.assigns)
    marketplace_overlay_map = load_marketplace_overlay_map(socket.assigns)
    marketplace_overlays = marketplace_overlay_map |> Map.values() |> Enum.sort_by(& &1.system_id)

    assign(socket,
      tribe_location_overlays: tribe_locations,
      tribe_scouting_overlays: tribe_scouting,
      marketplace_overlay_map: marketplace_overlay_map,
      marketplace_overlays: marketplace_overlays
    )
  end

  @spec load_tribe_overlays(map()) :: {[map()], [map()]}
  defp load_tribe_overlays(%{tribe_id: tribe_id, cache_tables: cache_tables, pubsub: pubsub})
       when is_integer(tribe_id) and tribe_id > 0 and is_map(cache_tables) and
              is_map_key(cache_tables, :intel) do
    reports =
      Intel.list_intel(tribe_id,
        authorized_tribe_id: tribe_id,
        tables: cache_tables,
        pubsub: pubsub
      )

    reports
    |> Enum.reduce({[], []}, fn
      %IntelReport{report_type: :location, solar_system_id: system_id, assembly_id: assembly_id} =
          report,
      {locations, scouting}
      when is_integer(system_id) and is_binary(assembly_id) ->
        {
          [
            %{system_id: system_id, assembly_id: assembly_id, label: report.label}
            | locations
          ],
          scouting
        }

      %IntelReport{report_type: :scouting, solar_system_id: system_id}, {locations, scouting}
      when is_integer(system_id) ->
        {locations, [%{system_id: system_id} | scouting]}

      _other, acc ->
        acc
    end)
    |> then(fn {locations, scouting} -> {Enum.reverse(locations), Enum.reverse(scouting)} end)
  end

  defp load_tribe_overlays(_assigns), do: {[], []}

  @spec load_marketplace_overlay_map(map()) :: %{optional(String.t()) => map()}
  defp load_marketplace_overlay_map(assigns) do
    options = marketplace_opts(assigns)

    listings =
      IntelMarket.list_listings(options) ++
        purchased_listings(assigns[:current_account], options)

    listings
    |> Enum.reduce(%{}, fn
      %IntelListing{id: id, solar_system_id: system_id}, acc
      when is_binary(id) and is_integer(system_id) and is_map_key(assigns.system_names, system_id) ->
        Map.put(acc, id, %{system_id: system_id})

      _other, acc ->
        acc
    end)
  end

  @spec purchased_listings(map() | nil, keyword()) :: [IntelListing.t()]
  defp purchased_listings(%{address: address}, options) when is_binary(address) do
    IntelMarket.list_purchased_listings(address, options)
  end

  defp purchased_listings(_account, _options), do: []

  @spec marketplace_opts(map()) :: keyword()
  defp marketplace_opts(assigns) do
    [
      tables: assigns[:cache_tables],
      pubsub: assigns[:pubsub]
    ]
  end

  @spec overlay_payload(map()) :: map()
  defp overlay_payload(assigns) do
    %{
      "tribe_locations" => stringify_overlay_entries(assigns.tribe_location_overlays),
      "tribe_scouting" => stringify_overlay_entries(assigns.tribe_scouting_overlays),
      "marketplace" => stringify_overlay_entries(assigns.marketplace_overlays),
      "overlay_toggles" => assigns.overlay_toggles
    }
  end

  @spec stringify_overlay_entries([map()]) :: [map()]
  defp stringify_overlay_entries(entries) do
    Enum.map(entries, &stringify_overlay_entry/1)
  end

  @spec stringify_overlay_entry(map()) :: map()
  defp stringify_overlay_entry(entry) do
    entry
    |> Enum.map(fn {key, value} -> {Atom.to_string(key), value} end)
    |> Map.new()
  end

  @spec maybe_load_connected_data(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp maybe_load_connected_data(socket) do
    if connected?(socket) do
      socket
      |> load_overlays()
      |> subscribe_overlay_topics()
    else
      socket
    end
  end

  @spec subscribe_overlay_topics(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp subscribe_overlay_topics(socket) do
    if is_atom(socket.assigns[:pubsub]) do
      if is_integer(socket.assigns.tribe_id) do
        Phoenix.PubSub.subscribe(socket.assigns.pubsub, Intel.topic(socket.assigns.tribe_id))
      end

      Phoenix.PubSub.subscribe(socket.assigns.pubsub, IntelMarket.topic())
    end

    socket
  end

  @spec known_system?(Phoenix.LiveView.Socket.t(), integer()) :: boolean()
  defp known_system?(socket, system_id), do: is_map_key(socket.assigns.system_names, system_id)

  @spec refresh_overlays(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp refresh_overlays(socket) do
    socket =
      case socket.assigns.selected_system do
        system_id when is_integer(system_id) ->
          assign(socket, :detail_data, Data.build_detail_data(system_id, socket.assigns))

        _other ->
          socket
      end

    if socket.assigns.map_ready do
      push_event(socket, "update_overlays", overlay_payload_for(socket))
    else
      socket
    end
  end

  @spec overlay_payload_for(Phoenix.LiveView.Socket.t()) :: map()
  defp overlay_payload_for(socket), do: overlay_payload(socket.assigns)

  @spec put_marketplace_listing(Phoenix.LiveView.Socket.t(), IntelListing.t()) ::
          Phoenix.LiveView.Socket.t()
  defp put_marketplace_listing(
         socket,
         %IntelListing{id: listing_id, solar_system_id: system_id}
       )
       when is_binary(listing_id) and is_integer(system_id) and
              is_map_key(socket.assigns.system_names, system_id) do
    overlay_map =
      Map.put(socket.assigns.marketplace_overlay_map, listing_id, %{system_id: system_id})

    assign(socket,
      marketplace_overlay_map: overlay_map,
      marketplace_overlays: overlay_map |> Map.values() |> Enum.sort_by(& &1.system_id)
    )
  end

  defp put_marketplace_listing(socket, _listing), do: socket

  @spec remove_marketplace_listing(Phoenix.LiveView.Socket.t(), String.t() | nil) ::
          Phoenix.LiveView.Socket.t()
  defp remove_marketplace_listing(socket, listing_id) when is_binary(listing_id) do
    overlay_map = Map.delete(socket.assigns.marketplace_overlay_map, listing_id)

    assign(socket,
      marketplace_overlay_map: overlay_map,
      marketplace_overlays: overlay_map |> Map.values() |> Enum.sort_by(& &1.system_id)
    )
  end

  defp remove_marketplace_listing(socket, _listing_id), do: socket

  @spec remove_first([map()], (map() -> boolean())) :: [map()]
  defp remove_first(list, matcher) do
    {remaining, removed?} =
      Enum.reduce(list, {[], false}, fn entry, {acc, removed?} ->
        cond do
          removed? -> {[entry | acc], removed?}
          matcher.(entry) -> {acc, true}
          true -> {[entry | acc], removed?}
        end
      end)

    if removed?, do: Enum.reverse(remaining), else: list
  end

  @spec resolve_tribe_id(map() | nil, map() | nil) :: integer() | nil
  defp resolve_tribe_id(%{tribe_id: tribe_id}, _account)
       when is_integer(tribe_id) and tribe_id > 0,
       do: tribe_id

  defp resolve_tribe_id(_character, %{tribe_id: tribe_id})
       when is_integer(tribe_id) and tribe_id > 0,
       do: tribe_id

  defp resolve_tribe_id(_character, _account), do: nil

  @spec parse_system_id(String.t() | integer() | nil) :: integer() | nil
  defp parse_system_id(value) when is_integer(value), do: value

  defp parse_system_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} -> parsed
      _other -> nil
    end
  end

  defp parse_system_id(_value), do: nil
end
