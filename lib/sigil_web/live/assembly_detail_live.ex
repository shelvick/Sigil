defmodule SigilWeb.AssemblyDetailLive do
  @moduledoc """
  Displays the selected cached assembly with type-specific operational details.
  """

  use SigilWeb, :live_view

  import SigilWeb.AssemblyHelpers, except: [assembly_name: 1]
  import SigilWeb.DiplomacyLive.Components, only: [signing_overlay: 1]
  import SigilWeb.TransactionHelpers, only: [localnet?: 0, sui_chain: 0]

  import SigilWeb.MonitorHelpers,
    only: [monitor_dependencies: 1, initial_depletion: 1, relative_depletion_label: 1]

  alias Sigil.Assemblies
  alias Sigil.GameState.MonitorSupervisor
  alias Sigil.Sui.Types.{Assembly, Character, Gate, NetworkNode, StorageUnit, Turret}

  @assembly_topic_prefix "assembly:"

  @doc """
  Loads the requested cached assembly, subscribes for updates, and ensures a monitor is running.
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
            signing_state: :idle,
            depletion: initial_depletion(assembly),
            is_owner: owner?(socket, assembly_id)
          )
          |> maybe_subscribe(assembly_id)
          |> maybe_ensure_monitor(assembly_id)

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
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event(
        "authorize_extension",
        _params,
        %{
          assigns: %{assembly: %Gate{id: gate_id}, active_character: %Character{id: character_id}}
        } =
          socket
      ) do
    case Assemblies.build_authorize_gate_extension_tx(
           gate_id,
           character_id,
           assembly_opts(socket)
         ) do
      {:ok, %{tx_bytes: tx_bytes}} ->
        {:noreply, enter_signing(socket, tx_bytes)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, inspect(reason))}
    end
  end

  def handle_event("authorize_extension", _params, socket) do
    {:noreply, put_flash(socket, :error, "Reconnect your wallet")}
  end

  def handle_event("transaction_signed", %{"bytes" => tx_bytes, "signature" => signature}, socket) do
    case Assemblies.submit_signed_extension_tx(tx_bytes, signature, assembly_opts(socket)) do
      {:ok, %{effects_bcs: effects_bcs}} ->
        socket =
          socket
          |> put_flash(:info, "Extension authorized successfully")
          |> assign(signing_state: :submitted)

        socket =
          if effects_bcs,
            do: push_event(socket, "report_transaction_effects", %{effects: effects_bcs}),
            else: socket

        {:noreply, socket}

      {:error, reason} ->
        {:noreply,
         socket
         |> put_flash(:error, inspect(reason))
         |> assign(signing_state: :idle)}
    end
  end

  def handle_event("transaction_error", %{"reason" => reason}, socket) do
    {:noreply,
     socket
     |> put_flash(:error, reason)
     |> assign(signing_state: :idle)}
  end

  def handle_event("wallet_detected", _params, socket), do: {:noreply, socket}
  def handle_event("wallet_error", _params, socket), do: {:noreply, socket}

  @doc false
  @impl true
  @spec handle_info(term(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_info(message, socket) do
    case message do
      {:assembly_monitor, _assembly_id, %{assembly: assembly, depletion: depletion}} ->
        {:noreply,
         assign(socket,
           assembly: assembly,
           assembly_type: assembly_type(assembly),
           page_title: assembly_name(assembly),
           depletion: depletion,
           signing_state: reset_signing_state(socket.assigns.signing_state)
         )}

      {:assembly_updated, assembly} ->
        {:noreply,
         assign(socket,
           assembly: assembly,
           assembly_type: assembly_type(assembly),
           page_title: assembly_name(assembly),
           depletion: initial_depletion(assembly),
           signing_state: reset_signing_state(socket.assigns.signing_state)
         )}

      _other ->
        {:noreply, socket}
    end
  end

  @doc """
  Renders the selected assembly detail shell.
  """
  @impl true
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <div
      :if={@is_owner}
      id={"wallet-hook-#{@assembly.id}"}
      phx-hook="WalletConnect"
      data-sui-chain={sui_chain()}
      class="hidden"
    ></div>
    <section class="px-4 py-12 sm:px-6 lg:px-8">
      <div class="mx-auto max-w-5xl rounded-[2rem] border border-space-600/80 bg-space-900/70 p-8 shadow-2xl shadow-black/40 backdrop-blur">
        <div class="flex flex-col gap-6 border-b border-space-600/80 pb-8 md:flex-row md:items-start md:justify-between">
          <div>
            <p class="font-mono text-xs uppercase tracking-[0.35em] text-quantum-300">Assembly uplink</p>
            <div class="mt-4 flex flex-wrap items-center gap-3">
              <span class={type_badge_classes(@assembly)}>
                <%= assembly_type_label(@assembly) %>
              </span>
              <span class={status_badge_classes(@assembly)}><%= assembly_status(@assembly) %></span>
            </div>
            <h1 class="mt-4 text-4xl font-semibold text-cream"><%= assembly_name(@assembly) %></h1>
            <div class="mt-3 flex items-center gap-2">
              <p class="break-all font-mono text-sm text-foreground"><%= @assembly.id %></p>
              <button
                type="button"
                class="shrink-0 rounded-full border border-space-600/80 bg-space-900/70 px-2 py-0.5 font-mono text-[0.6rem] text-space-500 transition hover:border-quantum-400/40 hover:text-quantum-300"
                onclick={"navigator.clipboard.writeText('#{@assembly.id}').then(() => { this.textContent = 'Copied!'; setTimeout(() => { this.textContent = 'Copy'; }, 1500); })"}
              >
                Copy
              </button>
            </div>
            <p :if={has_description?(@assembly)} class="mt-4 max-w-3xl text-sm leading-6 text-space-500"><%= assembly_description(@assembly) %></p>
          </div>

          <div class="flex flex-wrap gap-2">
            <.link
              navigate={~p"/"}
              class="inline-flex items-center rounded-full border border-space-600/80 bg-space-800/70 px-4 py-2 font-mono text-xs uppercase tracking-[0.2em] text-foreground transition hover:border-quantum-400 hover:text-quantum-300"
            >
              Dashboard
            </.link>
            <.link
              :if={@active_character && @active_character.tribe_id && @active_character.tribe_id > 0}
              navigate={~p"/tribe/#{@active_character.tribe_id}"}
              class="inline-flex items-center rounded-full border border-space-600/80 bg-space-800/70 px-4 py-2 font-mono text-xs uppercase tracking-[0.2em] text-foreground transition hover:border-quantum-400 hover:text-quantum-300"
            >
              Tribe
            </.link>
          </div>
        </div>

        <div class="mt-8 grid gap-4 md:grid-cols-2 xl:grid-cols-4">
          <.detail_card
            title="Owner Cap ID"
            value={truncate_or_placeholder(@assembly.owner_cap_id)}
            mono
            full_value={@assembly.owner_cap_id}
          />
          <.detail_card title="Type ID" value={to_string(@assembly.type_id)} mono />
          <.detail_card
            title="Location Hash"
            value={format_location_hash(@assembly.location.location_hash)}
            mono
            full_value={Base.encode16(@assembly.location.location_hash, case: :lower)}
          />
          <.detail_card
            title="Energy Source ID"
            value={truncate_or_placeholder(Map.get(@assembly, :energy_source_id))}
            mono
            full_value={Map.get(@assembly, :energy_source_id)}
          />
        </div>

        <%= case @assembly_type do %>
          <% :gate -> %>
            <div class="mt-8 space-y-4">
              <div class="grid gap-4 md:grid-cols-2">
                <div class="rounded-2xl border border-space-600/80 bg-space-800/70 p-4">
                  <p class="font-mono text-xs uppercase tracking-[0.3em] text-quantum-300">Linked Gate</p>
                  <%= if @assembly.linked_gate_id && byte_size(@assembly.linked_gate_id) > 0 do %>
                    <.link
                      navigate={~p"/assembly/#{@assembly.linked_gate_id}"}
                      class="mt-3 block font-mono text-sm text-quantum-300 transition hover:text-cream"
                      title={@assembly.linked_gate_id}
                    >
                      <%= truncate_id(@assembly.linked_gate_id) %>
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
                <p class="font-mono text-xs uppercase tracking-[0.3em] text-quantum-300">Inventory Keys</p>
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
                      <.link
                        :for={assembly_id <- @assembly.connected_assembly_ids}
                        navigate={~p"/assembly/#{assembly_id}"}
                        class="block break-all font-mono text-sm text-quantum-300 transition hover:text-cream"
                      >
                        <%= truncate_id(assembly_id) %>
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
      </div>
    </section>
    """
  end

  @spec maybe_subscribe(Phoenix.LiveView.Socket.t(), String.t()) :: Phoenix.LiveView.Socket.t()
  defp maybe_subscribe(socket, assembly_id) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(socket.assigns.pubsub, assembly_topic(assembly_id))
    end

    socket
  end

  @spec maybe_ensure_monitor(Phoenix.LiveView.Socket.t(), String.t()) ::
          Phoenix.LiveView.Socket.t()
  defp maybe_ensure_monitor(socket, assembly_id) do
    with true <- connected?(socket),
         {:ok, supervisor, registry} <- monitor_dependencies(socket),
         true <- is_map(socket.assigns[:cache_tables]) do
      :ok =
        MonitorSupervisor.ensure_monitors(
          supervisor,
          [assembly_id],
          registry: registry,
          tables: socket.assigns.cache_tables,
          pubsub: socket.assigns.pubsub
        )

      socket
    else
      _other ->
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

  @spec owner?(Phoenix.LiveView.Socket.t(), String.t()) :: boolean()
  defp owner?(socket, assembly_id) do
    case {socket.assigns[:current_account], socket.assigns[:cache_tables]} do
      {%{address: owner_address}, cache_tables}
      when is_binary(owner_address) and is_map(cache_tables) ->
        Assemblies.assembly_owned_by?(assembly_id, owner_address, tables: cache_tables)

      _other ->
        false
    end
  end

  @spec assembly_opts(Phoenix.LiveView.Socket.t()) :: Assemblies.options()
  defp assembly_opts(socket) do
    [tables: socket.assigns.cache_tables, pubsub: socket.assigns.pubsub]
  end

  @spec reset_signing_state(atom()) :: atom()
  defp reset_signing_state(:submitted), do: :idle
  defp reset_signing_state(signing_state), do: signing_state

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

  defp assembly_name(assembly) do
    "#{assembly_type_label(assembly)} #{truncate_id(assembly.id)}"
  end

  @spec enter_signing(Phoenix.LiveView.Socket.t(), String.t()) :: Phoenix.LiveView.Socket.t()
  defp enter_signing(socket, tx_bytes) do
    if localnet?() do
      sign_and_submit_locally(socket, tx_bytes)
    else
      socket
      |> assign(signing_state: :signing_tx)
      |> push_event("request_sign_transaction", %{"tx_bytes" => tx_bytes})
    end
  end

  @spec sign_and_submit_locally(Phoenix.LiveView.Socket.t(), String.t()) ::
          Phoenix.LiveView.Socket.t()
  defp sign_and_submit_locally(socket, kind_bytes) do
    case Assemblies.sign_and_submit_extension_locally(kind_bytes, assembly_opts(socket)) do
      {:ok, %{digest: _digest}} ->
        socket
        |> put_flash(:info, "Extension authorized (local signing)")
        |> assign(signing_state: :submitted)

      {:error, reason} ->
        socket
        |> put_flash(:error, "Transaction failed: #{inspect(reason)}")
        |> assign(signing_state: :idle)
    end
  end

  @spec assembly_topic(String.t()) :: String.t()
  defp assembly_topic(assembly_id), do: @assembly_topic_prefix <> assembly_id
end
