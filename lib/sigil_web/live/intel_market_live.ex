defmodule SigilWeb.IntelMarketLive do
  @moduledoc """
  Marketplace page for browsing, selling, and managing intel listings.
  """

  use SigilWeb, :live_view

  import SigilWeb.DiplomacyLive.Components, only: [signing_overlay: 1]
  import SigilWeb.TransactionHelpers, only: [sui_chain: 1]

  alias Sigil.Intel.IntelListing
  alias Sigil.Pseudonyms
  alias SigilWeb.IntelMarketLive.{PageHelpers, State, Transactions}

  @doc """
  Mounts the intel marketplace page.
  """
  @impl true
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def mount(_params, session, socket) do
    socket =
      socket
      |> assign(:seal_package_id_override, Map.get(session, "seal_package_id"))
      |> assign(:walrus_client_override, Map.get(session, "walrus_client"))
      |> assign(:reputation_registry_id_override, Map.get(session, "reputation_registry_id"))
      |> State.assign_base_state()
      |> PageHelpers.assign_seal_config_json()
      |> PageHelpers.maybe_load_marketplace()
      |> PageHelpers.maybe_subscribe_marketplace()

    {:ok, socket}
  end

  @doc false
  @impl true
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("filter_listings", %{"filters" => filters}, socket) do
    {:noreply, State.apply_filters(socket, filters)}
  end

  def handle_event("select_browse_system", %{"name" => name}, socket) do
    filters = Map.put(socket.assigns.filters, "solar_system_name", name)
    {:noreply, State.apply_filters(socket, filters)}
  end

  def handle_event("select_seller_system", %{"name" => name}, socket) do
    params = Map.put(socket.assigns.form.params, "solar_system_name", name)
    {:noreply, State.assign_listing_form(socket, params)}
  end

  @doc false
  def handle_event("show_section", %{"section" => section}, socket) do
    {:noreply, assign(socket, :page_section, PageHelpers.normalize_section(section))}
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
  def handle_event("create_pseudonym", _params, socket) do
    {:noreply,
     socket
     |> assign(
       pseudonym_error_message: nil,
       pending_delete_pseudonym: nil,
       pseudonym_delete_warning: nil
     )
     |> push_event("create_pseudonym", %{})}
  end

  @doc false
  def handle_event(
        "pseudonym_created",
        %{
          "pseudonym_address" => pseudonym_address,
          "encrypted_private_key" => encrypted_private_key
        },
        socket
      )
      when is_binary(pseudonym_address) and is_binary(encrypted_private_key) do
    attrs = %{
      pseudonym_address: pseudonym_address,
      encrypted_private_key: Base.decode64!(encrypted_private_key)
    }

    case Pseudonyms.create_pseudonym(socket.assigns.sender, attrs) do
      {:ok, _pseudonym} ->
        {:noreply,
         socket
         |> assign(pending_active_pseudonym: pseudonym_address, pseudonym_error_message: nil)
         |> State.reload_pseudonyms()
         |> State.push_pseudonyms()}

      {:error, :limit_reached} ->
        {:noreply, assign(socket, pseudonym_error_message: "Failed to create pseudonym")}

      {:error, _changeset} ->
        {:noreply, assign(socket, pseudonym_error_message: "Failed to create pseudonym")}
    end
  rescue
    ArgumentError ->
      {:noreply, assign(socket, pseudonym_error_message: "Failed to create pseudonym")}
  end

  @doc false
  def handle_event(
        "switch_pseudonym",
        %{"pseudonym" => %{"active_address" => pseudonym_address}},
        socket
      )
      when is_binary(pseudonym_address) do
    {:noreply,
     socket
     |> assign(pending_active_pseudonym: pseudonym_address, pseudonym_error_message: nil)
     |> push_event("activate_pseudonym", %{"pseudonym_address" => pseudonym_address})}
  end

  @doc false
  def handle_event(
        "pseudonyms_loaded",
        %{"addresses" => addresses, "active_address" => active_address},
        socket
      )
      when is_list(addresses) do
    {:noreply, State.sync_loaded_pseudonyms(socket, addresses, active_address)}
  end

  @doc false
  def handle_event(
        "request_delete_pseudonym",
        %{"pseudonym_address" => pseudonym_address},
        socket
      )
      when is_binary(pseudonym_address) do
    if Enum.any?(socket.assigns.pseudonyms, &(&1.pseudonym_address == pseudonym_address)) do
      {:noreply,
       assign(socket,
         pending_delete_pseudonym: pseudonym_address,
         pseudonym_delete_warning:
           "Deleting this pseudonym can orphan active listings and prevent cancellation. Confirm before continuing."
       )}
    else
      {:noreply, put_flash(socket, :error, "Pseudonym not found")}
    end
  end

  @doc false
  def handle_event("cancel_delete_pseudonym", _params, socket) do
    {:noreply, assign(socket, pending_delete_pseudonym: nil, pseudonym_delete_warning: nil)}
  end

  @doc false
  def handle_event("delete_pseudonym", %{"pseudonym_address" => pseudonym_address}, socket)
      when is_binary(pseudonym_address) do
    if socket.assigns.pending_delete_pseudonym == pseudonym_address do
      case Pseudonyms.delete_pseudonym(socket.assigns.sender, pseudonym_address) do
        {:ok, _deleted} ->
          {:noreply,
           socket
           |> assign(
             pending_active_pseudonym: nil,
             pending_delete_pseudonym: nil,
             pseudonym_delete_warning: nil
           )
           |> put_flash(:info, "Pseudonym deleted")
           |> State.refresh_marketplace()}

        {:error, :not_found} ->
          {:noreply,
           socket
           |> assign(pending_delete_pseudonym: nil, pseudonym_delete_warning: nil)
           |> put_flash(:error, "Pseudonym not found")}
      end
    else
      {:noreply,
       socket
       |> assign(pending_delete_pseudonym: nil, pseudonym_delete_warning: nil)
       |> put_flash(:error, "Confirm deletion before removing pseudonym")}
    end
  end

  @doc false
  def handle_event("pseudonym_activated", %{"pseudonym_address" => pseudonym_address}, socket)
      when is_binary(pseudonym_address) do
    {:noreply,
     socket
     |> assign(active_pseudonym: pseudonym_address, pending_active_pseudonym: pseudonym_address)
     |> State.refresh_marketplace()}
  end

  @doc false
  def handle_event("pseudonym_error", %{"phase" => phase, "reason" => reason}, socket)
      when is_binary(phase) and is_binary(reason) do
    {:noreply, PageHelpers.handle_pseudonym_error(socket, phase, reason)}
  end

  @doc false
  def handle_event("pseudonym_error", _params, socket) do
    {:noreply, assign(socket, pseudonym_error_message: "Failed to switch pseudonym")}
  end

  @doc false
  def handle_event("seal_status", %{"status" => status}, socket) when is_binary(status) do
    {:noreply,
     assign(socket, seal_status: State.humanize_seal_status(status), seal_error_message: nil)}
  end

  @doc false
  def handle_event(
        "seal_upload_complete",
        payload,
        %{assigns: %{pending_listing: pending}} = socket
      )
      when is_map(pending) do
    {:noreply, Transactions.build_listing_transaction(socket, pending, payload)}
  end

  @doc false
  def handle_event("seal_error", %{"reason" => reason}, socket) when is_binary(reason) do
    {:noreply,
     socket
     |> assign(
       seal_error_message: reason,
       seal_status: nil,
       page_state: :ready,
       pending_listing: nil,
       pending_tx: nil,
       pending_decrypt_listing_id: nil
     )
     |> put_flash(:error, reason)}
  end

  @doc false
  def handle_event("purchase_listing", %{"listing_id" => listing_id}, socket) do
    {:noreply, Transactions.begin_purchase(socket, listing_id)}
  end

  @doc false
  def handle_event("decrypt_listing", %{"listing_id" => listing_id}, socket) do
    {:noreply, Transactions.begin_decrypt(socket, listing_id)}
  end

  @doc false
  def handle_event(
        "seal_decrypt_complete",
        payload,
        %{assigns: %{pending_decrypt_listing_id: listing_id}} = socket
      )
      when is_binary(listing_id) and is_map(payload) do
    {:noreply, Transactions.complete_decrypt(socket, listing_id, payload)}
  end

  @doc false
  def handle_event("dismiss_decrypted_intel", %{"listing_id" => listing_id}, socket)
      when is_binary(listing_id) do
    decrypted_intel = Map.delete(socket.assigns.decrypted_intel, listing_id)

    {:noreply, assign(socket, decrypted_intel: decrypted_intel)}
  end

  @doc false
  def handle_event("cancel_listing", %{"listing_id" => listing_id}, socket) do
    {:noreply, Transactions.cancel_listing(socket, listing_id)}
  end

  @doc false
  def handle_event("confirm_quality", %{"listing_id" => listing_id}, socket) do
    {:noreply,
     if Map.get(socket.assigns.feedback_recorded || %{}, listing_id, false) do
       socket |> put_flash(:error, "Feedback already submitted")
     else
       Transactions.submit_feedback(socket, listing_id, :confirm_quality)
     end}
  end

  @doc false
  def handle_event("report_bad_quality", %{"listing_id" => listing_id}, socket) do
    {:noreply,
     if Map.get(socket.assigns.feedback_recorded || %{}, listing_id, false) do
       socket |> put_flash(:error, "Feedback already submitted")
     else
       Transactions.submit_feedback(socket, listing_id, :report_bad_quality)
     end}
  end

  @doc false
  def handle_event("pseudonym_tx_signed", %{"signature" => signature}, socket)
      when is_binary(signature) do
    case socket.assigns[:pending_tx] do
      %{kind: kind, tx_bytes: tx_bytes}
      when kind in [:create_listing_pseudonym, :cancel_listing_pseudonym] ->
        {:noreply, Transactions.finalize_transaction(socket, tx_bytes, signature)}

      _other ->
        {:noreply,
         socket
         |> assign(page_state: :ready, pending_tx: nil, pending_listing: nil, seal_status: nil)
         |> put_flash(:error, "Transaction failed")}
    end
  end

  @doc false
  def handle_event("transaction_signed", %{"bytes" => tx_bytes, "signature" => signature}, socket) do
    case socket.assigns[:pending_tx] do
      %{} = _pending ->
        {:noreply, Transactions.finalize_transaction(socket, tx_bytes, signature)}

      _other ->
        {:noreply,
         socket
         |> assign(page_state: :ready, pending_tx: nil, pending_listing: nil, seal_status: nil)
         |> put_flash(:error, "Transaction failed")}
    end
  end

  @doc false
  def handle_event("transaction_error", %{"reason" => reason}, socket) when is_binary(reason) do
    {:noreply,
     socket
     |> assign(page_state: :ready, pending_tx: nil, seal_status: nil)
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
      <div id="wallet-signer" phx-hook="WalletConnect" data-sui-chain={sui_chain(@world)} class="hidden"></div>
    <% end %>

    <%= if @authenticated? do %>
      <div
        id="seal-encrypt"
        phx-hook="SealEncrypt"
        data-address={@sender}
        data-active-pseudonym={@active_pseudonym}
        data-sui-chain={sui_chain(@world)}
        data-config={@seal_config_json}
        class="hidden"
      ></div>

      <div
        id="pseudonym-key"
        phx-hook="PseudonymKey"
        data-address={@sender}
        data-sui-chain={sui_chain(@world)}
        class="hidden"
      ></div>
    <% end %>

    <section class="relative overflow-hidden px-4 py-12 sm:px-6 lg:px-8">
      <div class="mx-auto max-w-6xl space-y-8">
        <div class="rounded-[2rem] border border-space-600/80 bg-space-900/70 p-8 shadow-2xl shadow-black/40 backdrop-blur">
          <div class="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
            <div>
              <p class="font-mono text-xs uppercase tracking-[0.35em] text-quantum-300">Intel marketplace</p>
              <h1 class="mt-3 text-4xl font-semibold text-cream">Encrypted Intel Trade</h1>
              <p class="mt-3 max-w-3xl text-sm leading-6 text-space-500">
                Browse active intel listings, encrypt and upload sealed offers, and settle purchases through your wallet.
              </p>
            </div>

            <%= if @authenticated? do %>
              <div class="flex flex-wrap gap-2">
                <button
                  type="button"
                  phx-click="show_section"
                  phx-value-section="browsing"
                  class={PageHelpers.section_button_classes(@page_section == :browsing)}
                >
                  Browse
                </button>
                <button
                  type="button"
                  phx-click="show_section"
                  phx-value-section="my_listings"
                  class={PageHelpers.section_button_classes(@page_section == :my_listings)}
                >
                  My Listings
                </button>
              </div>
            <% end %>
          </div>
        </div>

        <%= if @seal_error_message do %>
          <div class="rounded-2xl border border-warning/40 bg-warning/10 p-4 text-sm text-warning">
            <%= @seal_error_message %>
          </div>
        <% end %>

        <%= if @authenticated? do %>
          <%= if @marketplace_available? do %>
            <%= if @page_section == :my_listings do %>
              <SigilWeb.IntelMarketLive.Components.my_listings_panel
                listings={@my_listings}
                purchased_listings={@purchased_listings}
                decrypted_intel={@decrypted_intel}
                feedback_recorded={@feedback_recorded}
                static_data={@static_data_pid}
              />
            <% else %>
              <SigilWeb.IntelMarketLive.Components.filter_bar
                filters={@filters}
                browse_solar_suggestions={@browse_solar_suggestions}
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
                      active_pseudonym={@active_pseudonym}
                      tribe_id={@tribe_id}
                      static_data={@static_data_pid}
                      reputation={Map.get(@reputation_cache, listing.seller_address)}
                      decrypted_intel={Map.get(@decrypted_intel, listing.id, %{})}
                    />
                  <% end %>
                </div>

                <div class="space-y-4">
                  <SigilWeb.IntelMarketLive.Components.sell_form
                    can_sell={@can_sell}
                    form={@form}
                    entry_mode={@entry_mode}
                    my_reports={@my_reports}
                    pseudonyms={@pseudonyms}
                    active_pseudonym={@active_pseudonym}
                    pending_delete_pseudonym={@pending_delete_pseudonym}
                    pseudonym_error_message={@pseudonym_error_message}
                    pseudonym_delete_warning={@pseudonym_delete_warning}
                    seal_status={@seal_status}
                    seller_solar_suggestions={@seller_solar_suggestions}
                    tribe_id={@tribe_id}
                  />

                  <SigilWeb.IntelMarketLive.Components.seal_status status={@seal_status} />

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
              Authenticate from the dashboard to browse listings, create sealed offers, and settle purchases.
            </p>
          </div>
        <% end %>
      </div>
    </section>
    """
  end
end
