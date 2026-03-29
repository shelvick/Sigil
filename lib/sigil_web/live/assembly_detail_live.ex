defmodule SigilWeb.AssemblyDetailLive do
  @moduledoc """
  Displays the selected cached assembly with type-specific operational details.
  """

  use SigilWeb, :live_view

  import SigilWeb.AssemblyHelpers, except: [assembly_name: 1]
  import SigilWeb.TransactionHelpers, only: [localnet?: 0, sui_chain: 0]

  import SigilWeb.MonitorHelpers, only: [monitor_dependencies: 1, initial_depletion: 1]

  alias Sigil.{Assemblies, Intel, StaticData}
  alias SigilWeb.AssemblyDetailLive.IntelHelpers
  alias Sigil.GameState.MonitorSupervisor
  alias Sigil.Intel.IntelReport
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
            page_title: assembly_name(assembly, socket.assigns[:static_data]),
            signing_state: :idle,
            depletion: initial_depletion(assembly),
            is_owner: owner?(socket, assembly_id)
          )
          |> assign_intel_state()
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

  def handle_event("set_location", %{"location" => params}, socket) do
    {:noreply, persist_location(socket, params)}
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
           page_title: assembly_name(assembly, socket.assigns[:static_data]),
           depletion: depletion,
           signing_state: reset_signing_state(socket.assigns.signing_state)
         )}

      {:assembly_updated, assembly} ->
        {:noreply,
         assign(socket,
           assembly: assembly,
           assembly_type: assembly_type(assembly),
           page_title: assembly_name(assembly, socket.assigns[:static_data]),
           depletion: initial_depletion(assembly),
           signing_state: reset_signing_state(socket.assigns.signing_state)
         )}

      {:intel_updated, %IntelReport{report_type: :location, assembly_id: assembly_id} = report}
      when assembly_id == socket.assigns.assembly.id ->
        {:noreply, assign_location_report(socket, report)}

      {:intel_deleted, %IntelReport{report_type: :location, assembly_id: assembly_id}}
      when assembly_id == socket.assigns.assembly.id ->
        {:noreply, assign_location_report(socket, nil)}

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
                <%= assembly_type_label(@assembly, @static_data) %>
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

        <SigilWeb.AssemblyDetailLive.Components.location_panel
          :if={@location_visible}
          location_name={@location_name}
          location_solar_system_id={@location_solar_system_id}
          can_edit_location={@can_edit_location}
          form={@location_form}
          solar_systems={@solar_systems}
        />

        <SigilWeb.AssemblyDetailLive.Components.type_specific_section
          assembly={@assembly}
          assembly_type={@assembly_type}
          active_character={@active_character}
          depletion={@depletion}
          is_owner={@is_owner}
          signing_state={@signing_state}
        />
      </div>
    </section>
    """
  end

  @spec maybe_subscribe(Phoenix.LiveView.Socket.t(), String.t()) :: Phoenix.LiveView.Socket.t()
  defp maybe_subscribe(socket, assembly_id) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(socket.assigns.pubsub, assembly_topic(assembly_id))

      if is_integer(socket.assigns[:tribe_id]) do
        Phoenix.PubSub.subscribe(socket.assigns.pubsub, intel_topic(socket.assigns.tribe_id))
      end
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

  @spec assign_intel_state(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp assign_intel_state(socket) do
    tribe_id =
      IntelHelpers.current_tribe_id(
        socket.assigns[:active_character],
        socket.assigns[:current_account]
      )

    static_data_pid = socket.assigns[:static_data]
    intel_enabled? = IntelHelpers.intel_enabled?(socket.assigns[:cache_tables], tribe_id)

    can_edit_location =
      intel_enabled? and is_pid(static_data_pid) and
        match?(
          %Character{tribe_id: tribe_id} when is_integer(tribe_id) and tribe_id > 0,
          socket.assigns[:active_character]
        )

    location_report = load_location_report(socket, tribe_id, intel_enabled?)
    location_visible = is_integer(tribe_id)

    socket
    |> assign(
      tribe_id: tribe_id,
      location_visible: location_visible,
      static_data_pid: static_data_pid,
      solar_systems: load_solar_systems(socket, static_data_pid, can_edit_location),
      can_edit_location: can_edit_location,
      location_form: to_form(%{}, as: :location)
    )
    |> assign_location_report(location_report)
  end

  @spec load_location_report(Phoenix.LiveView.Socket.t(), integer() | nil, boolean()) ::
          IntelReport.t() | nil
  defp load_location_report(socket, tribe_id, true) when is_integer(tribe_id) do
    Intel.get_location(
      tribe_id,
      socket.assigns.assembly.id,
      IntelHelpers.intel_opts(socket.assigns.cache_tables, socket.assigns.pubsub, tribe_id)
    )
  end

  defp load_location_report(_socket, _tribe_id, _intel_enabled?), do: nil

  @spec load_solar_systems(Phoenix.LiveView.Socket.t(), pid() | nil, boolean()) :: list()
  defp load_solar_systems(socket, static_data_pid, true) when is_pid(static_data_pid) do
    if connected?(socket), do: StaticData.list_solar_systems(static_data_pid), else: []
  end

  defp load_solar_systems(_socket, _static_data_pid, _can_edit_location), do: []

  @spec assign_location_report(Phoenix.LiveView.Socket.t(), IntelReport.t() | nil) ::
          Phoenix.LiveView.Socket.t()
  defp assign_location_report(socket, report) do
    assign(socket,
      location_report: report,
      location_name: IntelHelpers.resolve_location_name(socket.assigns[:static_data_pid], report),
      location_solar_system_id: report_solar_system_id(report),
      location_form: to_form(%{}, as: :location)
    )
  end

  @spec report_solar_system_id(IntelReport.t() | nil) :: integer() | nil
  defp report_solar_system_id(%IntelReport{solar_system_id: solar_system_id})
       when is_integer(solar_system_id) and solar_system_id > 0,
       do: solar_system_id

  defp report_solar_system_id(_report), do: nil

  @spec persist_location(Phoenix.LiveView.Socket.t(), map()) :: Phoenix.LiveView.Socket.t()
  defp persist_location(socket, %{"solar_system_name" => solar_system_name} = params) do
    with true <- socket.assigns.can_edit_location,
         static_data_pid when is_pid(static_data_pid) <- socket.assigns.static_data_pid,
         tribe_id when is_integer(tribe_id) <- socket.assigns.tribe_id,
         %Character{} = active_character <- socket.assigns.active_character,
         %{} = solar_system <-
           StaticData.get_solar_system_by_name(static_data_pid, solar_system_name),
         {:ok, report} <-
           Intel.report_location(
             %{
               tribe_id: tribe_id,
               assembly_id: socket.assigns.assembly.id,
               solar_system_id: solar_system.id,
               label: assembly_name(socket.assigns.assembly, socket.assigns[:static_data]),
               notes: "Assembly location update",
               reported_by: socket.assigns.current_account.address,
               reported_by_name: IntelHelpers.character_name(active_character),
               reported_by_character_id: active_character.id
             },
             IntelHelpers.intel_opts(socket.assigns.cache_tables, socket.assigns.pubsub, tribe_id)
           ) do
      socket
      |> put_flash(:info, "Location saved")
      |> assign_location_report(report)
    else
      false ->
        put_flash(socket, :error, "Unknown or ambiguous solar system")

      nil ->
        put_flash(socket, :error, "Unknown or ambiguous solar system")

      {:error, %Ecto.Changeset{} = changeset} ->
        put_flash(socket, :error, inspect(changeset.errors))

      _other ->
        put_flash(socket, :error, "Unknown or ambiguous solar system")
    end
    |> assign(:location_form, to_form(params, as: :location))
  end

  defp persist_location(socket, _params),
    do: put_flash(socket, :error, "Unknown or ambiguous solar system")

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

  @spec assembly_name(Assemblies.assembly(), pid() | nil) :: String.t()
  defp assembly_name(assembly, static_data \\ nil)

  defp assembly_name(%{metadata: %{name: name}}, _static_data)
       when is_binary(name) and byte_size(name) > 0,
       do: name

  defp assembly_name(assembly, static_data) do
    "#{assembly_type_label(assembly, static_data)} #{truncate_id(assembly.id)}"
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

  @spec assembly_opts(Phoenix.LiveView.Socket.t()) :: Assemblies.options()
  defp assembly_opts(socket) do
    [tables: socket.assigns.cache_tables, pubsub: socket.assigns.pubsub]
  end

  @spec assembly_topic(String.t()) :: String.t()
  defp assembly_topic(assembly_id), do: @assembly_topic_prefix <> assembly_id

  @spec intel_topic(integer()) :: String.t()
  defp intel_topic(tribe_id), do: "intel:" <> Integer.to_string(tribe_id)
end
