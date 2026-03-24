defmodule SigilWeb.IntelMarketLive do
  @moduledoc """
  Marketplace page for browsing, selling, and managing intel listings.
  """

  use SigilWeb, :live_view

  import SigilWeb.DiplomacyLive.Components, only: [signing_overlay: 1]
  import SigilWeb.TransactionHelpers, only: [sui_chain: 0]

  alias Sigil.Intel.IntelListing
  alias Sigil.IntelMarket
  alias SigilWeb.IntelMarketLive.{State, Transactions}

  @doc """
  Mounts the intel marketplace page.
  """
  @impl true
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def mount(_params, _session, socket) do
    socket =
      socket
      |> State.assign_base_state()
      |> maybe_load_marketplace()
      |> maybe_subscribe_marketplace()

    {:ok, socket}
  end

  @doc false
  @impl true
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("filter_listings", %{"filters" => filters}, socket) do
    {:noreply, State.apply_filters(socket, filters)}
  end

  @doc false
  def handle_event("show_section", %{"section" => section}, socket) do
    {:noreply, assign(socket, :page_section, normalize_section(section))}
  end

  @doc false
  def handle_event("validate_listing", %{"listing" => params}, socket) do
    {:noreply, State.assign_listing_form(socket, params)}
  end

  @doc false
  def handle_event("submit_listing", %{"listing" => params}, socket) do
    {:noreply, Transactions.submit_listing(socket, params)}
  end

  @doc false
  def handle_event("proof_status", %{"status" => status}, socket) when is_binary(status) do
    {:noreply,
     assign(socket, proof_status: State.humanize_status(status), proof_error_message: nil)}
  end

  @doc false
  def handle_event("proof_generated", payload, %{assigns: %{pending_listing: pending}} = socket)
      when is_map(pending) do
    {:noreply, Transactions.build_listing_transaction(socket, pending, payload)}
  end

  @doc false
  def handle_event("proof_error", %{"reason" => reason}, socket) when is_binary(reason) do
    {:noreply,
     socket
     |> assign(
       proof_error_message: reason,
       proof_status: nil,
       page_state: :ready,
       pending_listing: nil,
       pending_tx: nil
     )}
  end

  @doc false
  def handle_event("purchase_listing", %{"listing_id" => listing_id}, socket) do
    {:noreply, Transactions.begin_purchase(socket, listing_id)}
  end

  @doc false
  def handle_event("cancel_listing", %{"listing_id" => listing_id}, socket) do
    {:noreply, Transactions.cancel_listing(socket, listing_id)}
  end

  @doc false
  def handle_event("transaction_signed", %{"bytes" => tx_bytes, "signature" => signature}, socket) do
    case socket.assigns[:pending_tx] do
      %{tx_bytes: ^tx_bytes} ->
        {:noreply, Transactions.finalize_transaction(socket, tx_bytes, signature)}

      _other ->
        {:noreply,
         socket
         |> assign(page_state: :ready, pending_tx: nil, pending_listing: nil, proof_status: nil)
         |> put_flash(:error, "Transaction failed")}
    end
  end

  @doc false
  def handle_event("transaction_error", %{"reason" => reason}, socket) when is_binary(reason) do
    {:noreply,
     socket
     |> assign(page_state: :ready, pending_tx: nil, proof_status: nil)
     |> put_flash(:error, reason)}
  end

  @doc false
  def handle_event("wallet_detected", _params, socket), do: {:noreply, socket}
  @doc false
  def handle_event("wallet_error", _params, socket), do: {:noreply, socket}

  @doc false
  @impl true
  @spec handle_info(term(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_info({event, %IntelListing{}}, socket)
      when event in [:listing_created, :listing_purchased, :listing_cancelled] do
    {:noreply, State.refresh_marketplace(socket)}
  end

  @doc false
  def handle_info({:listing_removed, _listing_id}, socket) do
    {:noreply, State.refresh_marketplace(socket)}
  end

  @doc false
  def handle_info(_message, socket), do: {:noreply, socket}

  @doc false
  @impl true
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <%= if @authenticated? do %>
      <div id="wallet-signer" phx-hook="WalletConnect" data-sui-chain={sui_chain()} class="hidden"></div>
    <% end %>

    <%= if @can_sell do %>
      <div id="zk-proof-generator" phx-hook="ZkProofGenerator" class="hidden"></div>
    <% end %>

    <section class="relative overflow-hidden px-4 py-12 sm:px-6 lg:px-8">
      <div class="mx-auto max-w-6xl space-y-8">
        <div class="rounded-[2rem] border border-space-600/80 bg-space-900/70 p-8 shadow-2xl shadow-black/40 backdrop-blur">
          <div class="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
            <div>
              <p class="font-mono text-xs uppercase tracking-[0.35em] text-quantum-300">Intel marketplace</p>
              <h1 class="mt-3 text-4xl font-semibold text-cream">Commitment-backed trade</h1>
              <p class="mt-3 max-w-3xl text-sm leading-6 text-space-500">
                Browse active intel listings, create proof-backed offers, and settle purchases through your wallet.
              </p>
            </div>

            <%= if @authenticated? do %>
              <div class="flex flex-wrap gap-2">
                <button
                  type="button"
                  phx-click="show_section"
                  phx-value-section="browsing"
                  class={section_button_classes(@page_section == :browsing)}
                >
                  Browse
                </button>
                <button
                  type="button"
                  phx-click="show_section"
                  phx-value-section="my_listings"
                  class={section_button_classes(@page_section == :my_listings)}
                >
                  My Listings
                </button>
              </div>
            <% end %>
          </div>
        </div>

        <%= if @proof_error_message do %>
          <div class="rounded-2xl border border-warning/40 bg-warning/10 p-4 text-sm text-warning">
            <%= @proof_error_message %>
          </div>
        <% end %>

        <%= if @authenticated? do %>
          <%= if @marketplace_available? do %>
            <%= if @page_section == :my_listings do %>
              <SigilWeb.IntelMarketLive.Components.my_listings_panel
                listings={@my_listings}
                static_data={@static_data_pid}
              />
            <% else %>
              <SigilWeb.IntelMarketLive.Components.filter_bar
                filters={@filters}
                solar_systems={@solar_systems}
              />

              <div class="grid gap-8 xl:grid-cols-[1.1fr_0.9fr]">
                <div class="space-y-4">
                  <%= if @filtered_listings == [] do %>
                    <div class="rounded-[2rem] border border-space-600/80 bg-space-900/70 p-8 text-sm text-space-500 shadow-2xl shadow-black/30 backdrop-blur">
                      No listings available
                    </div>
                  <% else %>
                    <SigilWeb.IntelMarketLive.Components.listing_card
                      :for={listing <- @filtered_listings}
                      listing={listing}
                      sender={@sender}
                      tribe_id={@tribe_id}
                      static_data={@static_data_pid}
                    />
                  <% end %>
                </div>

                <div class="space-y-4">
                  <SigilWeb.IntelMarketLive.Components.sell_form
                    can_sell={@can_sell}
                    form={@form}
                    entry_mode={@entry_mode}
                    my_reports={@my_reports}
                    proof_status={@proof_status}
                    solar_systems={@solar_systems}
                    tribe_id={@tribe_id}
                  />

                  <SigilWeb.IntelMarketLive.Components.proof_status status={@proof_status} />

                  <.signing_overlay :if={@page_state == :signing_tx} />
                </div>
              </div>
            <% end %>
          <% else %>
            <div class="rounded-[2rem] border border-space-600/80 bg-space-900/70 p-8 text-sm text-space-500 shadow-2xl shadow-black/30 backdrop-blur">
              Marketplace not yet available
            </div>
          <% end %>
        <% else %>
          <div class="rounded-[2rem] border border-space-600/80 bg-space-900/70 p-8 shadow-2xl shadow-black/30 backdrop-blur">
            <p class="font-mono text-xs uppercase tracking-[0.3em] text-quantum-300">Authentication required</p>
            <h2 class="mt-3 text-2xl font-semibold text-cream">Connect wallet to use marketplace</h2>
            <p class="mt-3 max-w-2xl text-sm leading-6 text-space-500">
              Authenticate from the dashboard to browse listings, create proof-backed offers, and settle purchases.
            </p>
          </div>
        <% end %>
      </div>
    </section>
    """
  end

  defp maybe_load_marketplace(%{assigns: %{authenticated?: false}} = socket), do: socket

  defp maybe_load_marketplace(%{assigns: %{cache_tables: cache_tables}} = socket)
       when not is_map(cache_tables) do
    socket
  end

  defp maybe_load_marketplace(socket) do
    case IntelMarket.discover_marketplace(State.market_opts(socket)) do
      {:ok, nil} ->
        assign(socket, marketplace_available?: false)

      {:ok, marketplace_info} ->
        socket
        |> assign(marketplace_available?: true, marketplace_info: marketplace_info)
        |> State.sync_and_load_data()

      {:error, _reason} ->
        assign(socket, marketplace_available?: false)
    end
  end

  defp maybe_subscribe_marketplace(socket) do
    if connected?(socket) and socket.assigns[:authenticated?] and socket.assigns[:pubsub] do
      Phoenix.PubSub.subscribe(socket.assigns.pubsub, IntelMarket.topic())
    end

    socket
  end

  defp normalize_section("my_listings"), do: :my_listings
  defp normalize_section(_section), do: :browsing

  defp section_button_classes(true) do
    "rounded-full border border-quantum-300 bg-quantum-400/10 px-4 py-2 font-mono text-xs uppercase tracking-[0.22em] text-cream"
  end

  defp section_button_classes(false) do
    "rounded-full border border-space-600/80 bg-space-800/70 px-4 py-2 font-mono text-xs uppercase tracking-[0.22em] text-space-500 transition hover:border-quantum-400 hover:text-cream"
  end
end
