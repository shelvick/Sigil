defmodule FrontierOSWeb.AssemblyDetailLive do
  @moduledoc """
  Displays the selected cached assembly with type-specific operational details.
  """

  use FrontierOSWeb, :live_view

  import FrontierOSWeb.AssemblyHelpers, except: [assembly_name: 1]

  alias FrontierOS.Assemblies
  alias FrontierOS.GameState.Poller
  alias FrontierOS.Sui.Types.{Assembly, Gate, NetworkNode, StorageUnit, Turret}

  @assembly_topic_prefix "assembly:"

  @doc """
  Loads the requested cached assembly, subscribes for updates, and starts a linked poller.
  """
  @impl true
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def mount(%{"id" => assembly_id}, _session, socket) do
    case fetch_assembly(assembly_id, socket.assigns[:cache_tables]) do
      {:ok, assembly} ->
        socket =
          socket
          |> assign(
            assembly: assembly,
            assembly_type: assembly_type(assembly),
            page_title: assembly_name(assembly),
            poller: nil
          )
          |> maybe_subscribe(assembly_id)
          |> maybe_start_poller(assembly_id)

        {:ok, socket}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "Assembly not found")
         |> redirect(to: ~p"/")}
    end
  end

  @doc false
  @impl true
  @spec handle_info({:assembly_updated, Assemblies.assembly()}, Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_info({:assembly_updated, assembly}, socket) do
    {:noreply,
     assign(socket,
       assembly: assembly,
       assembly_type: assembly_type(assembly),
       page_title: assembly_name(assembly)
     )}
  end

  @doc """
  Renders the selected assembly detail shell.
  """
  @impl true
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <section class="px-4 py-12 sm:px-6 lg:px-8">
      <div class="mx-auto max-w-5xl rounded-[2rem] border border-space-600/80 bg-space-900/70 p-8 shadow-2xl shadow-black/40 backdrop-blur">
        <div class="flex flex-col gap-6 border-b border-space-600/80 pb-8 md:flex-row md:items-start md:justify-between">
          <div>
            <p class="font-mono text-xs uppercase tracking-[0.35em] text-quantum-300">Assembly uplink</p>
            <div class="mt-4 flex flex-wrap items-center gap-3">
              <span class="rounded-full border border-space-600/80 bg-space-800/80 px-3 py-1 font-mono text-xs uppercase tracking-[0.25em] text-quantum-300">
                <%= assembly_type_label(@assembly) %>
              </span>
              <span class={status_badge_classes(@assembly)}><%= assembly_status(@assembly) %></span>
            </div>
            <h1 class="mt-4 text-4xl font-semibold text-cream"><%= assembly_name(@assembly) %></h1>
            <p class="mt-3 break-all font-mono text-sm text-foreground"><%= @assembly.id %></p>
            <p class="mt-4 max-w-3xl text-sm leading-6 text-space-500"><%= assembly_description(@assembly) %></p>
          </div>

          <.link
            navigate={~p"/"}
            class="inline-flex items-center rounded-full border border-space-600/80 bg-space-800/70 px-4 py-2 font-mono text-xs uppercase tracking-[0.2em] text-foreground transition hover:border-quantum-400 hover:text-quantum-300"
          >
            Back to Dashboard
          </.link>
        </div>

        <div class="mt-8 grid gap-4 md:grid-cols-2 xl:grid-cols-4">
          <.detail_card title="Owner Cap ID" value={truncate_or_placeholder(@assembly.owner_cap_id)} mono full_value={@assembly.owner_cap_id} />
          <.detail_card title="Type ID" value={to_string(@assembly.type_id)} mono />
          <.detail_card title="Location Hash" value={format_location_hash(@assembly.location.location_hash)} mono full_value={Base.encode16(@assembly.location.location_hash, case: :lower)} />
          <.detail_card title="Energy Source ID" value={truncate_or_placeholder(Map.get(@assembly, :energy_source_id))} mono full_value={Map.get(@assembly, :energy_source_id)} />
        </div>

        <%= case @assembly_type do %>
          <% :gate -> %>
            <div class="mt-8 grid gap-4 md:grid-cols-2">
              <.detail_card title="Linked Gate ID" value={linked_gate_label(@assembly.linked_gate_id)} mono full_value={@assembly.linked_gate_id} />
              <.detail_card title="Extension" value={extension_label(@assembly.extension)} mono full_value={@assembly.extension} />
            </div>

          <% :turret -> %>
            <div class="mt-8 grid gap-4 md:grid-cols-2">
              <.detail_card title="Extension" value={extension_label(@assembly.extension)} mono full_value={@assembly.extension} />
            </div>

          <% :storage_unit -> %>
            <div class="mt-8 grid gap-4 lg:grid-cols-[1.2fr_0.8fr]">
              <div class="rounded-2xl border border-space-600/80 bg-space-800/70 p-5">
                <p class="font-mono text-xs uppercase tracking-[0.3em] text-quantum-300">Inventory Keys</p>
                <%= if @assembly.inventory_keys == [] do %>
                  <p class="mt-4 text-sm text-space-500">Empty</p>
                <% else %>
                  <div class="mt-4 space-y-2">
                    <p :for={inventory_key <- @assembly.inventory_keys} class="break-all font-mono text-sm text-foreground">
                      <%= inventory_key %>
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
                    <div class="h-full rounded-full bg-quantum-400" style={"width: #{fuel_percent(@assembly.fuel)}%"}></div>
                  </div>
                </div>

                <div class="grid gap-4 md:grid-cols-2">
                  <.detail_card title="Burn Rate" value={format_burn_rate(@assembly.fuel.burn_rate_in_ms)} mono />
                  <.detail_card title="Is Burning" value={yes_no(@assembly.fuel.is_burning)} mono />
                  <.detail_card title="Fuel Type ID" value={optional_integer(@assembly.fuel.type_id)} mono />
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
                      <p :for={assembly_id <- @assembly.connected_assembly_ids} class="break-all font-mono text-sm text-foreground">
                        <%= assembly_id %>
                      </p>
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
      </div>
    </section>
    """
  end

  attr :title, :string, required: true
  attr :value, :string, required: true
  attr :full_value, :string, default: nil
  attr :mono, :boolean, default: false

  defp detail_card(assigns) do
    ~H"""
    <div class="rounded-2xl border border-space-600/80 bg-space-800/70 p-4">
      <p class="font-mono text-xs uppercase tracking-[0.3em] text-quantum-300"><%= @title %></p>
      <p class={["mt-3 break-all text-sm text-cream", @mono && "font-mono text-foreground"]} title={@full_value || @value}>
        <%= @value %>
      </p>
    </div>
    """
  end

  @spec maybe_subscribe(Phoenix.LiveView.Socket.t(), String.t()) :: Phoenix.LiveView.Socket.t()
  defp maybe_subscribe(socket, assembly_id) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(socket.assigns.pubsub, assembly_topic(assembly_id))
    end

    socket
  end

  @spec maybe_start_poller(Phoenix.LiveView.Socket.t(), String.t()) :: Phoenix.LiveView.Socket.t()
  defp maybe_start_poller(
         %{assigns: %{cache_tables: tables, pubsub: pubsub}} = socket,
         assembly_id
       ) do
    if connected?(socket) and is_map(tables) do
      {:ok, poller} =
        Poller.start_link(assembly_ids: [assembly_id], tables: tables, pubsub: pubsub)

      assign(socket, poller: poller)
    else
      socket
    end
  end

  @spec fetch_assembly(String.t(), map() | nil) ::
          {:ok, Assemblies.assembly()} | {:error, :not_found}
  defp fetch_assembly(assembly_id, cache_tables)
       when is_binary(assembly_id) and is_map(cache_tables) do
    Assemblies.get_assembly(assembly_id, tables: cache_tables)
  end

  defp fetch_assembly(_assembly_id, _cache_tables), do: {:error, :not_found}

  @spec assembly_type(Assemblies.assembly()) ::
          :gate | :turret | :network_node | :storage_unit | :assembly
  defp assembly_type(%Gate{}), do: :gate
  defp assembly_type(%Turret{}), do: :turret
  defp assembly_type(%NetworkNode{}), do: :network_node
  defp assembly_type(%StorageUnit{}), do: :storage_unit
  defp assembly_type(%Assembly{}), do: :assembly

  @spec assembly_name(Assemblies.assembly()) :: String.t()
  defp assembly_name(%{metadata: %{name: name}}) when is_binary(name) and byte_size(name) > 0,
    do: name

  defp assembly_name(%{id: _assembly_id}), do: "Unnamed"

  @spec assembly_description(Assemblies.assembly()) :: String.t()
  defp assembly_description(%{metadata: %{description: description}})
       when is_binary(description) and byte_size(description) > 0,
       do: description

  defp assembly_description(_assembly), do: "No description provided"

  @spec available_energy(FrontierOS.Sui.Types.EnergySource.t()) :: integer()
  defp available_energy(energy_source) do
    energy_source.current_energy_production - energy_source.total_reserved_energy
  end

  @spec energy_current_label(FrontierOS.Sui.Types.EnergySource.t()) :: String.t()
  defp energy_current_label(%{max_energy_production: 0, current_energy_production: current}) do
    "#{current} (N/A)"
  end

  defp energy_current_label(energy_source) do
    percent =
      div(energy_source.current_energy_production * 100, energy_source.max_energy_production)

    "#{energy_source.current_energy_production} (#{percent}%)"
  end

  @spec format_burn_rate(non_neg_integer()) :: String.t()
  defp format_burn_rate(rate_in_ms) when rate_in_ms >= 3_600_000 do
    "#{div(rate_in_ms, 3_600_000)} per hour"
  end

  defp format_burn_rate(rate_in_ms) when rate_in_ms >= 60_000 do
    "#{div(rate_in_ms, 60_000)} per minute"
  end

  defp format_burn_rate(rate_in_ms) do
    "#{rate_in_ms} ms"
  end

  @spec format_timestamp(non_neg_integer(), boolean()) :: String.t()
  defp format_timestamp(_timestamp, false), do: "Not burning"

  defp format_timestamp(timestamp, true) when is_integer(timestamp) and timestamp > 0 do
    case DateTime.from_unix(timestamp, :millisecond) do
      {:ok, dt} -> Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S UTC")
      {:error, _} -> Integer.to_string(timestamp)
    end
  end

  defp format_timestamp(timestamp, true), do: Integer.to_string(timestamp)

  @spec yes_no(boolean()) :: String.t()
  defp yes_no(true), do: "Yes"
  defp yes_no(false), do: "No"

  @spec optional_integer(non_neg_integer() | nil) :: String.t()
  defp optional_integer(nil), do: "Not set"
  defp optional_integer(value), do: Integer.to_string(value)

  @spec truncate_or_placeholder(String.t() | nil) :: String.t()
  defp truncate_or_placeholder(nil), do: "Not set"
  defp truncate_or_placeholder(value) when is_binary(value), do: truncate_id(value)

  @spec linked_gate_label(String.t() | nil) :: String.t()
  defp linked_gate_label(value) when is_binary(value) and byte_size(value) > 0, do: value
  defp linked_gate_label(_value), do: "Not linked"

  @spec extension_label(String.t() | nil) :: String.t()
  defp extension_label(value) when is_binary(value) and byte_size(value) > 0, do: value
  defp extension_label(_value), do: "None"

  @spec format_location_hash(binary()) :: String.t()
  defp format_location_hash(hash) when is_binary(hash) do
    hash
    |> Base.encode16(case: :lower)
    |> truncate_or_placeholder()
  end

  @spec assembly_topic(String.t()) :: String.t()
  defp assembly_topic(assembly_id), do: @assembly_topic_prefix <> assembly_id
end
