defmodule SigilWeb.DashboardLive do
  @moduledoc """
  Renders the themed wallet form and the authenticated assembly overview.
  """

  use SigilWeb, :live_view

  import SigilWeb.DashboardLive.Components

  alias Sigil.Assemblies
  alias Sigil.GameState.Poller
  alias Sigil.Sui.ZkLoginVerifier

  @owner_topic_prefix "assemblies:"
  @assembly_topic_prefix "assembly:"

  @doc """
  Sets the initial dashboard state and loads assemblies for authenticated users.
  """
  @impl true
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def mount(params, _session, socket) do
    socket =
      socket
      |> assign_base_state(params)
      |> maybe_load_assemblies()
      |> maybe_subscribe()
      |> maybe_start_poller()

    {:ok, socket}
  end

  @doc false
  @impl true
  @spec handle_info(
          {:assemblies_discovered, [Assemblies.assembly()]},
          Phoenix.LiveView.Socket.t()
        ) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_info({:assemblies_discovered, assemblies}, socket) when is_list(assemblies) do
    {:noreply,
     socket
     |> assign(assemblies: assemblies, discovery_error: false)
     |> subscribe_to_assembly_topics(assemblies)
     |> maybe_update_poller(assemblies)}
  end

  @doc false
  @impl true
  @spec handle_info({:assembly_updated, Assemblies.assembly()}, Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_info({:assembly_updated, assembly}, socket) do
    {:noreply, assign(socket, assemblies: replace_assembly(socket.assigns.assemblies, assembly))}
  end

  @doc false
  @impl true
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("wallet_detected", _params, %{assigns: %{wallet_state: state}} = socket)
      when state in [:connecting, :account_selection, :signing] do
    {:noreply, socket}
  end

  def handle_event("wallet_detected", %{"wallets" => []}, socket) do
    {:noreply,
     assign(socket,
       wallets: [],
       wallet_state: :idle,
       wallet_name: nil,
       wallet_error: nil
     )}
  end

  def handle_event("wallet_detected", %{"wallets" => [wallet]}, socket) when is_map(wallet) do
    {:noreply,
     socket
     |> assign(
       wallets: [wallet],
       wallet_state: :connecting,
       wallet_name: wallet_name(wallet),
       wallet_error: nil
     )
     |> push_event("connect_wallet", %{"index" => 0})}
  end

  def handle_event("wallet_detected", %{"wallets" => wallets}, socket) when is_list(wallets) do
    {:noreply,
     assign(socket,
       wallets: wallets,
       wallet_state: :idle,
       wallet_name: nil,
       wallet_error: nil
     )}
  end

  @doc false
  def handle_event("select_wallet", %{"index" => index}, socket) do
    case Integer.parse(index) do
      {parsed_index, ""} ->
        {:noreply,
         socket
         |> assign(wallet_state: :connecting, wallet_error: nil)
         |> push_event("connect_wallet", %{"index" => parsed_index})}

      _other ->
        {:noreply, assign(socket, wallet_state: :error, wallet_error: "Unable to select wallet")}
    end
  end

  @doc false
  def handle_event("wallet_accounts", %{"accounts" => accounts}, socket) when is_list(accounts) do
    {:noreply,
     assign(socket,
       wallet_accounts: accounts,
       wallet_state: :account_selection,
       wallet_error: nil
     )}
  end

  @doc false
  def handle_event("select_account", %{"index" => index}, socket) do
    case Integer.parse(to_string(index)) do
      {parsed_index, ""} ->
        {:noreply,
         socket
         |> assign(wallet_state: :connecting, wallet_error: nil, wallet_accounts: [])
         |> push_event("select_account", %{"index" => parsed_index})}

      _other ->
        {:noreply, assign(socket, wallet_state: :error, wallet_error: "Unable to select account")}
    end
  end

  @doc false
  def handle_event("wallet_account_changed", _params, socket) do
    {:noreply, put_flash(socket, :info, "Wallet account changed. Re-authenticate to switch.")}
  end

  @doc false
  def handle_event("wallet_connected", %{"address" => address, "name" => name}, socket) do
    case generate_wallet_challenge(socket, address) do
      {:ok, socket, challenge} ->
        {:noreply,
         socket
         |> assign(
           wallet_state: :signing,
           wallet_address: address,
           wallet_name: name,
           wallet_error: nil
         )
         |> push_event("request_sign", challenge)}

      {:error, socket, reason} ->
        {:noreply,
         assign(socket, wallet_state: :error, wallet_error: wallet_error_message(reason))}
    end
  end

  @doc false
  def handle_event("wallet_error", %{"reason" => reason}, socket) when is_binary(reason) do
    socket =
      socket
      |> put_flash(:error, reason)
      |> assign(wallet_state: :error, wallet_error: reason)

    {:noreply, socket}
  end

  @doc false
  def handle_event("wallet_retry", _params, socket) do
    {:noreply,
     assign(socket,
       wallet_state: :idle,
       wallet_address: nil,
       wallet_name: nil,
       wallet_error: nil
     )}
  end

  @doc """
  Renders the themed wallet form or the authenticated assembly overview.
  """
  @impl true
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <section class="relative overflow-hidden px-4 py-12 sm:px-6 lg:px-8">
      <div class="mx-auto max-w-6xl rounded-[2rem] border border-space-600/80 bg-space-900/70 p-8 shadow-2xl shadow-black/40 backdrop-blur">
        <div class="mb-10 flex items-center justify-between gap-4 border-b border-space-600/80 pb-6">
          <div>
            <p class="font-mono text-xs uppercase tracking-[0.35em] text-quantum-300">
              Sigil uplink
            </p>
            <h1 class="mt-3 text-4xl font-semibold text-cream sm:text-5xl">Command Deck</h1>
          </div>
          <div class="hidden rounded-full border border-quantum-600/60 bg-quantum-700/40 px-4 py-2 font-mono text-xs uppercase tracking-[0.25em] text-quantum-300 md:block">
            Waiting for capsuleer
          </div>
        </div>

        <%= if @current_account do %>
          <.authenticated_view
            current_account={@current_account}
            active_character={@active_character}
            assemblies={@assemblies}
            discovery_error={@discovery_error}
          />
        <% else %>
          <.wallet_connect_view
            wallets={@wallets}
            wallet_state={@wallet_state}
            wallet_name={@wallet_name}
            wallet_error={@wallet_error}
            wallet_accounts={@wallet_accounts}
          />
        <% end %>
      </div>
    </section>
    """
  end

  @spec assign_base_state(Phoenix.LiveView.Socket.t(), map()) :: Phoenix.LiveView.Socket.t()
  defp assign_base_state(%{assigns: %{current_account: nil}} = socket, params) do
    assign(socket,
      page_title: "Connect Wallet",
      assemblies: [],
      loading: false,
      poller: nil,
      discovery_error: false,
      wallet_state: :idle,
      wallet_address: nil,
      wallet_name: nil,
      wallet_error: nil,
      wallets: [],
      wallet_accounts: [],
      item_id: Map.get(params, "itemId"),
      tenant: Map.get(params, "tenant")
    )
  end

  defp assign_base_state(socket, _params) do
    assign(socket,
      page_title: "Dashboard",
      assemblies: [],
      loading: false,
      poller: nil,
      discovery_error: false
    )
  end

  @spec maybe_load_assemblies(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp maybe_load_assemblies(%{assigns: %{current_account: nil}} = socket), do: socket

  defp maybe_load_assemblies(%{assigns: %{current_account: account}} = socket) do
    address = account.address
    character_ids = active_character_ids(socket)

    if connected?(socket) do
      case discover_assemblies(
             address,
             character_ids,
             socket.assigns[:cache_tables],
             socket.assigns[:pubsub]
           ) do
        {:ok, assemblies} ->
          assign(socket, assemblies: assemblies, discovery_error: false)

        {:error, _reason} ->
          socket
          |> put_flash(:error, "Unable to refresh assemblies right now.")
          |> assign(assemblies: [], discovery_error: true)
      end
    else
      assign(socket,
        assemblies: list_assemblies(address, socket.assigns[:cache_tables]),
        discovery_error: false
      )
    end
  end

  @spec maybe_subscribe(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp maybe_subscribe(%{assigns: %{current_account: nil}} = socket), do: socket

  defp maybe_subscribe(
         %{assigns: %{current_account: %{address: address}, pubsub: pubsub}} = socket
       ) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(pubsub, owner_topic(address))
      subscribe_to_assembly_topics(socket, socket.assigns.assemblies)
    else
      socket
    end
  end

  @spec maybe_start_poller(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp maybe_start_poller(%{assigns: %{current_account: nil}} = socket), do: socket

  defp maybe_start_poller(
         %{assigns: %{assemblies: assemblies, cache_tables: tables, pubsub: pubsub}} = socket
       ) do
    if connected?(socket) and is_map(tables) do
      {:ok, poller} =
        Poller.start_link(
          assembly_ids: Enum.map(assemblies, & &1.id),
          tables: tables,
          pubsub: pubsub
        )

      assign(socket, poller: poller)
    else
      socket
    end
  end

  @spec maybe_update_poller(Phoenix.LiveView.Socket.t(), [Assemblies.assembly()]) ::
          Phoenix.LiveView.Socket.t()
  defp maybe_update_poller(%{assigns: %{poller: poller}} = socket, assemblies)
       when is_pid(poller) do
    :ok = Poller.update_assembly_ids(poller, Enum.map(assemblies, & &1.id))
    socket
  end

  defp maybe_update_poller(socket, _assemblies), do: socket

  @spec active_character_ids(Phoenix.LiveView.Socket.t()) :: [String.t()]
  defp active_character_ids(%{assigns: %{active_character: %{id: id}}}), do: [id]
  defp active_character_ids(_socket), do: []

  @spec discover_assemblies(String.t(), [String.t()], map() | nil, atom() | module()) ::
          {:ok, [Assemblies.assembly()]} | {:error, term()}
  defp discover_assemblies(address, character_ids, cache_tables, pubsub)
       when is_map(cache_tables) do
    Assemblies.discover_for_owner(address,
      tables: cache_tables,
      pubsub: pubsub,
      character_ids: character_ids
    )
  end

  defp discover_assemblies(_address, _character_ids, _cache_tables, _pubsub), do: {:ok, []}

  @spec list_assemblies(String.t(), map() | nil) :: [Assemblies.assembly()]
  defp list_assemblies(address, cache_tables) when is_map(cache_tables) do
    Assemblies.list_for_owner(address, tables: cache_tables)
  end

  defp list_assemblies(_address, _cache_tables), do: []

  @spec subscribe_to_assembly_topics(Phoenix.LiveView.Socket.t(), [Assemblies.assembly()]) ::
          Phoenix.LiveView.Socket.t()
  defp subscribe_to_assembly_topics(%{assigns: %{pubsub: pubsub}} = socket, assemblies) do
    Enum.each(assemblies, fn assembly ->
      Phoenix.PubSub.subscribe(pubsub, assembly_topic(assembly.id))
    end)

    socket
  end

  @spec replace_assembly([Assemblies.assembly()], Assemblies.assembly()) :: [
          Assemblies.assembly()
        ]
  defp replace_assembly(assemblies, assembly) do
    Enum.map(assemblies, fn existing ->
      if existing.id == assembly.id, do: assembly, else: existing
    end)
  end

  @spec generate_wallet_challenge(Phoenix.LiveView.Socket.t(), String.t()) ::
          {:ok, Phoenix.LiveView.Socket.t(), %{required(String.t()) => String.t()}}
          | {:error, Phoenix.LiveView.Socket.t(), atom()}
  defp generate_wallet_challenge(%{assigns: %{cache_tables: tables}} = socket, address)
       when is_map(tables) do
    case ZkLoginVerifier.generate_nonce(address,
           tables: tables,
           item_id: socket.assigns[:item_id],
           tenant: socket.assigns[:tenant]
         ) do
      {:ok, %{nonce: nonce, message: message}} ->
        {:ok, socket, %{"nonce" => nonce, "message" => message}}

      {:error, reason} ->
        {:error, socket, reason}
    end
  end

  defp generate_wallet_challenge(socket, _address), do: {:error, socket, :cache_unavailable}

  @spec wallet_error_message(:cache_unavailable | :invalid_address) :: String.t()
  defp wallet_error_message(:cache_unavailable), do: "Service starting up. Please try again."
  defp wallet_error_message(:invalid_address), do: "Invalid wallet address"

  @spec wallet_name(map()) :: String.t()
  defp wallet_name(%{"name" => name}) when is_binary(name), do: name
  defp wallet_name(%{name: name}) when is_binary(name), do: name
  defp wallet_name(_wallet), do: "Unknown Wallet"

  @spec owner_topic(String.t()) :: String.t()
  defp owner_topic(address), do: @owner_topic_prefix <> address

  @spec assembly_topic(String.t()) :: String.t()
  defp assembly_topic(assembly_id), do: @assembly_topic_prefix <> assembly_id
end
