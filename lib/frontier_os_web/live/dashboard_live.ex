defmodule FrontierOSWeb.DashboardLive do
  @moduledoc """
  Renders the themed wallet form and the authenticated assembly overview.
  """

  use FrontierOSWeb, :live_view

  import FrontierOSWeb.AssemblyHelpers

  alias FrontierOS.Accounts.Account
  alias FrontierOS.Assemblies
  alias FrontierOS.GameState.Poller
  alias FrontierOS.Sui.Types.NetworkNode

  @owner_topic_prefix "assemblies:"
  @assembly_topic_prefix "assembly:"

  @doc """
  Sets the initial dashboard state and loads assemblies for authenticated users.
  """
  @impl true
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign_base_state()
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
              FrontierOS uplink
            </p>
            <h1 class="mt-3 text-4xl font-semibold text-cream sm:text-5xl">Command Deck</h1>
          </div>
          <div class="hidden rounded-full border border-quantum-600/60 bg-quantum-700/40 px-4 py-2 font-mono text-xs uppercase tracking-[0.25em] text-quantum-300 md:block">
            Waiting for capsuleer
          </div>
        </div>

        <%= if @current_account do %>
          <div class="grid gap-8">
            <div class="grid gap-4 lg:grid-cols-[2fr_1fr]">
              <div class="rounded-3xl border border-space-600/80 bg-space-800/80 p-6">
                <p class="font-mono text-xs uppercase tracking-[0.3em] text-quantum-300">Wallet linked</p>
                <h2 class="mt-4 text-2xl font-semibold text-cream"><%= truncate_id(@current_account.address) %></h2>
                <p class="mt-2 break-all font-mono text-sm text-foreground"><%= @current_account.address %></p>

                <dl class="mt-6 grid gap-4 sm:grid-cols-3">
                  <div>
                    <dt class="font-mono text-[0.65rem] uppercase tracking-[0.25em] text-space-500">Character</dt>
                    <dd class="mt-2 text-sm text-cream"><%= primary_character_name(@current_account) %></dd>
                  </div>
                  <div>
                    <dt class="font-mono text-[0.65rem] uppercase tracking-[0.25em] text-space-500">Tribe</dt>
                    <dd class="mt-2 text-sm text-cream"><%= tribe_label(@current_account) %></dd>
                  </div>
                  <div>
                    <dt class="font-mono text-[0.65rem] uppercase tracking-[0.25em] text-space-500">Crew count</dt>
                    <dd class="mt-2 text-sm text-cream"><%= length(@current_account.characters) %> online</dd>
                  </div>
                </dl>
              </div>

              <div class="rounded-3xl border border-space-600/80 bg-space-800/60 p-6">
                <p class="font-mono text-xs uppercase tracking-[0.3em] text-quantum-300">Session controls</p>
                <p class="mt-4 text-sm leading-6 text-space-500">
                  Discovery stays synced while this command deck remains linked to the uplink.
                </p>
                <.link
                  href={~p"/session"}
                  method="delete"
                  class="mt-6 inline-flex rounded-full bg-quantum-600 px-5 py-3 font-mono text-xs uppercase tracking-[0.25em] text-space-950 transition hover:bg-quantum-400"
                >
                  Disconnect Wallet
                </.link>
              </div>
            </div>

            <div class="rounded-3xl border border-space-600/80 bg-space-800/70 p-6">
              <div class="flex items-center justify-between gap-4">
                <div>
                  <p class="font-mono text-xs uppercase tracking-[0.3em] text-quantum-300">Assembly manifest</p>
                  <h2 class="mt-3 text-2xl font-semibold text-cream">Operational Assets</h2>
                </div>
                <span class="rounded-full border border-space-600/80 bg-space-900/70 px-3 py-1 font-mono text-xs uppercase tracking-[0.2em] text-space-500">
                  <%= length(@assemblies) %> tracked
                </span>
              </div>

              <%= if @assemblies == [] do %>
                <div class="mt-6 rounded-2xl border border-space-600/80 bg-space-900/70 p-5">
                  <p class="text-sm text-cream">
                    <%= if @discovery_error, do: "Assembly discovery is temporarily unavailable", else: "No assemblies found" %>
                  </p>
                  <p class="mt-2 text-sm text-space-500">
                    <%= if @discovery_error,
                      do: "Retry discovery by refreshing the command deck.",
                      else: "Link another wallet or check again after more assets come online." %>
                  </p>
                </div>
              <% else %>
                <div class="mt-6 overflow-x-auto">
                  <table class="min-w-full border-separate border-spacing-y-3">
                    <thead>
                      <tr class="font-mono text-xs uppercase tracking-[0.25em] text-space-500">
                        <th class="px-4 py-2 text-left">Type</th>
                        <th class="px-4 py-2 text-left">Name</th>
                        <th class="px-4 py-2 text-left">Status</th>
                        <th class="px-4 py-2 text-left">Fuel</th>
                      </tr>
                    </thead>
                    <tbody>
                      <%= for assembly <- @assemblies do %>
                        <tr class="cursor-pointer rounded-2xl bg-space-900/70 text-sm text-foreground transition hover:bg-space-800/80" phx-click={JS.navigate(~p"/assembly/#{assembly.id}")}>
                          <td class="rounded-l-2xl px-4 py-4 font-mono text-xs uppercase tracking-[0.2em] text-quantum-300">
                            <%= assembly_type_label(assembly) %>
                          </td>
                          <td class="px-4 py-4">
                            <.link navigate={~p"/assembly/#{assembly.id}"} class="font-semibold text-cream hover:text-quantum-300">
                              <%= assembly_name(assembly) %>
                            </.link>
                          </td>
                          <td class="px-4 py-4">
                            <span class={status_badge_classes(assembly)}>
                              <%= assembly_status(assembly) %>
                            </span>
                          </td>
                          <td class="rounded-r-2xl px-4 py-4">
                            <%= if match?(%NetworkNode{}, assembly) do %>
                              <div class="space-y-2">
                                <div class="flex items-center justify-between gap-3 font-mono text-xs uppercase tracking-[0.15em] text-space-500">
                                  <span><%= fuel_label(assembly.fuel) %></span>
                                  <span><%= fuel_percent_label(assembly.fuel) %></span>
                                </div>
                                <div class="h-2 rounded-full bg-space-700">
                                  <div class="h-full rounded-full bg-quantum-400" style={"width: #{fuel_percent(assembly.fuel)}%"}></div>
                                </div>
                              </div>
                            <% else %>
                              <span class="font-mono text-xs uppercase tracking-[0.2em] text-space-500">-</span>
                            <% end %>
                          </td>
                        </tr>
                      <% end %>
                    </tbody>
                  </table>
                </div>
              <% end %>
            </div>
          </div>
        <% else %>
          <div class="grid gap-8 lg:grid-cols-[1.4fr_0.9fr]">
            <div class="space-y-6">
              <p class="font-mono text-xs uppercase tracking-[0.3em] text-quantum-300">EVE Frontier-ready interface</p>
              <h2 class="max-w-2xl text-4xl font-semibold leading-tight text-cream sm:text-6xl">
                Connect Your Wallet
              </h2>
              <p class="max-w-2xl text-base leading-7 text-space-500 sm:text-lg">
                Link a commander wallet to unlock tribe assemblies, live status telemetry, and shared frontier operations.
              </p>
            </div>

            <form action={~p"/session"} method="post" class="rounded-3xl border border-space-600/80 bg-space-800/80 p-6">
              <input type="hidden" name="_csrf_token" value={Phoenix.Controller.get_csrf_token()} />
              <label for="wallet_address" class="font-mono text-xs uppercase tracking-[0.3em] text-quantum-300">
                Wallet Address
              </label>
              <input
                id="wallet_address"
                name="wallet_address"
                type="text"
                placeholder="0x..."
                class="mt-4 w-full rounded-2xl border border-space-600 bg-space-950 px-4 py-3 font-mono text-sm text-cream placeholder:text-space-500 focus:border-quantum-400 focus:ring-0"
              />
              <button
                type="submit"
                class="mt-6 inline-flex w-full items-center justify-center rounded-full bg-quantum-400 px-5 py-3 font-mono text-xs uppercase tracking-[0.25em] text-space-950 transition hover:bg-quantum-300"
              >
                Enter Frontier
              </button>
            </form>
          </div>
        <% end %>
      </div>
    </section>
    """
  end

  @spec assign_base_state(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp assign_base_state(%{assigns: %{current_account: nil}} = socket) do
    assign(socket,
      page_title: "Connect Wallet",
      assemblies: [],
      loading: false,
      poller: nil,
      discovery_error: false
    )
  end

  defp assign_base_state(socket) do
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

  defp maybe_load_assemblies(%{assigns: %{current_account: %{address: address}}} = socket) do
    if connected?(socket) do
      case discover_assemblies(address, socket.assigns[:cache_tables], socket.assigns[:pubsub]) do
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

  @spec discover_assemblies(String.t(), map() | nil, atom() | module()) ::
          {:ok, [Assemblies.assembly()]} | {:error, term()}
  defp discover_assemblies(address, cache_tables, pubsub) when is_map(cache_tables) do
    Assemblies.discover_for_owner(address, tables: cache_tables, pubsub: pubsub)
  end

  defp discover_assemblies(_address, _cache_tables, _pubsub), do: {:ok, []}

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

  @spec primary_character_name(Account.t()) :: String.t()
  defp primary_character_name(%Account{characters: [%{metadata: %{name: name}} | _rest]})
       when is_binary(name),
       do: name

  defp primary_character_name(%Account{characters: []}), do: "No characters synced"
  defp primary_character_name(%Account{}), do: "Commander profile"

  @spec tribe_label(Account.t()) :: String.t()
  defp tribe_label(%Account{tribe_id: tribe_id}) when is_integer(tribe_id),
    do: Integer.to_string(tribe_id)

  defp tribe_label(%Account{}), do: "Unaligned"

  @spec owner_topic(String.t()) :: String.t()
  defp owner_topic(address), do: @owner_topic_prefix <> address

  @spec assembly_topic(String.t()) :: String.t()
  defp assembly_topic(assembly_id), do: @assembly_topic_prefix <> assembly_id
end
