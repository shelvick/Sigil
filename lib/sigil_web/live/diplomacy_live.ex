defmodule SigilWeb.DiplomacyLive do
  @moduledoc """
  Diplomacy editor for managing tribe custodians, standings, and pilot overrides.
  """

  use SigilWeb, :live_view

  import SigilWeb.DiplomacyLive.Components

  import SigilWeb.TransactionHelpers,
    only: [sui_chain: 0, localnet_signer_address: 0]

  import SigilWeb.TribeHelpers, only: [authorize_tribe: 2]

  alias Sigil.Diplomacy
  alias SigilWeb.DiplomacyLive.Governance, as: Gov

  @doc """
  Mounts the diplomacy editor for the given tribe_id.
  """
  @impl true
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) ::
          {:ok, Phoenix.LiveView.Socket.t()}
  def mount(%{"tribe_id" => tribe_id_str}, _session, socket) do
    case authorize_tribe(tribe_id_str, socket) do
      {:ok, tribe_id} ->
        socket =
          socket
          |> assign_base_state(tribe_id)
          |> Gov.discover_custodian_state()
          |> Gov.load_standings()
          |> maybe_subscribe()

        {:ok, socket}

      {:error, :unauthorized} ->
        {:ok,
         socket
         |> put_flash(:error, "Tribe Custodian access denied")
         |> redirect(to: ~p"/")}

      {:error, :unauthenticated} ->
        {:ok, redirect(socket, to: ~p"/")}
    end
  end

  @doc false
  @impl true
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("create_custodian", _params, socket) do
    {:noreply,
     socket
     |> clear_flash()
     |> build_tx(&Diplomacy.build_create_custodian_tx/1)}
  end

  def handle_event("retry_discovery", _params, socket) do
    {:noreply,
     socket
     |> clear_flash()
     |> Gov.discover_custodian_state()
     |> Gov.load_standings()}
  end

  def handle_event("add_tribe_standing", %{"tribe_id" => tid, "standing" => s}, socket) do
    case Integer.parse(tid) do
      {tribe_id, ""} ->
        {:noreply,
         socket
         |> clear_flash()
         |> build_tx(&Diplomacy.build_set_standing_tx(tribe_id, String.to_integer(s), &1))}

      _invalid ->
        {:noreply, put_flash(socket, :error, "Tribe ID must be a number")}
    end
  end

  def handle_event("set_standing", %{"standing" => ""}, socket) do
    {:noreply, socket}
  end

  def handle_event("set_standing", %{"tribe_id" => tid, "standing" => s}, socket) do
    {:noreply,
     socket
     |> clear_flash()
     |> build_tx(
       &Diplomacy.build_set_standing_tx(String.to_integer(tid), String.to_integer(s), &1)
     )}
  end

  def handle_event("batch_set_standings", %{"updates" => updates}, socket) do
    parsed =
      Enum.map(updates, fn %{"tribe_id" => tid, "standing" => s} ->
        {String.to_integer(tid), String.to_integer(s)}
      end)

    {:noreply,
     socket
     |> clear_flash()
     |> build_tx(&Diplomacy.build_batch_set_standings_tx(parsed, &1))}
  end

  def handle_event("add_pilot_override", %{"pilot_address" => pilot, "standing" => s}, socket) do
    if valid_address?(pilot) do
      {:noreply,
       socket
       |> clear_flash()
       |> assign(pilot_error: nil)
       |> build_tx(&Diplomacy.build_set_pilot_standing_tx(pilot, String.to_integer(s), &1))}
    else
      {:noreply, assign(socket, pilot_error: "Invalid address format")}
    end
  end

  def handle_event("set_default_standing", %{"standing" => standing_str}, socket) do
    {:noreply,
     socket
     |> clear_flash()
     |> build_tx(&Diplomacy.build_set_default_standing_tx(String.to_integer(standing_str), &1))}
  end

  def handle_event("filter_tribes", %{"query" => query}, socket) do
    {:noreply, assign(socket, tribe_filter: query)}
  end

  def handle_event("toggle_governance", _params, socket) do
    {:noreply, assign(socket, governance_expanded: !socket.assigns.governance_expanded)}
  end

  def handle_event("vote_leader", %{"candidate" => candidate}, socket) do
    {:noreply,
     socket
     |> clear_flash()
     |> build_tx(&Diplomacy.build_vote_leader_tx(candidate, &1))}
  end

  def handle_event("claim_leadership", _params, socket) do
    {:noreply,
     socket
     |> clear_flash()
     |> build_tx(&Diplomacy.build_claim_leadership_tx/1)}
  end

  def handle_event("transaction_signed", %{"bytes" => tx_bytes, "signature" => signature}, socket) do
    tx_bytes = socket.assigns.pending_tx_bytes || tx_bytes
    ignore_governance_update = Gov.governance_tx?(socket, tx_bytes)

    case Diplomacy.submit_signed_transaction(tx_bytes, signature, Gov.diplomacy_opts(socket)) do
      {:ok, %{digest: _digest, effects_bcs: effects_bcs}} ->
        socket =
          socket
          |> assign(
            page_state: socket.assigns.return_page_state,
            pending_tx_bytes: nil,
            ignore_governance_update: ignore_governance_update
          )
          |> Gov.maybe_refresh_after_submission()

        socket =
          if effects_bcs,
            do: push_event(socket, "report_transaction_effects", %{effects: effects_bcs}),
            else: socket

        {:noreply, socket}

      {:error, _reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Transaction failed")
         |> assign(page_state: socket.assigns.return_page_state, pending_tx_bytes: nil)}
    end
  end

  def handle_event("transaction_error", %{"reason" => _reason}, socket) do
    {:noreply,
     socket
     |> put_flash(:info, "Transaction cancelled")
     |> assign(page_state: socket.assigns.return_page_state, pending_tx_bytes: nil)}
  end

  def handle_event("wallet_detected", _params, socket), do: {:noreply, socket}
  def handle_event("wallet_error", _params, socket), do: {:noreply, socket}

  @doc false
  @impl true
  @spec handle_info(term(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_info({:standing_updated, _data}, socket),
    do: {:noreply, Gov.load_standings(socket)}

  def handle_info({:pilot_standing_updated, _data}, socket),
    do: {:noreply, Gov.load_standings(socket)}

  def handle_info({:default_standing_updated, _standing}, socket),
    do: {:noreply, Gov.load_standings(socket)}

  def handle_info(
        {:custodian_discovered, _custodian},
        %{assigns: %{ignore_governance_update: true}} = socket
      ),
      do: {:noreply, socket}

  def handle_info({:custodian_discovered, custodian}, socket),
    do: {:noreply, socket |> Gov.apply_discovered_custodian(custodian) |> Gov.load_standings()}

  def handle_info({:custodian_created, _custodian}, socket),
    do: {:noreply, socket |> Gov.apply_cached_custodian_state() |> Gov.load_standings()}

  def handle_info(
        {:governance_updated, %{tribe_id: tribe_id}},
        %{assigns: %{tribe_id: tribe_id, ignore_governance_update: true}} = socket
      ),
      do: {:noreply, assign(socket, ignore_governance_update: false)}

  def handle_info(
        {:governance_updated, %{tribe_id: tribe_id}},
        %{assigns: %{tribe_id: tribe_id}} = socket
      ),
      do: {:noreply, Gov.load_standings(socket)}

  def handle_info(:rediscover_custodian, socket),
    do: {:noreply, socket |> Gov.discover_custodian_state() |> Gov.load_standings()}

  def handle_info(_msg, socket), do: {:noreply, socket}

  @doc false
  @impl true
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    content_state =
      if assigns.page_state == :signing_tx,
        do: assigns.return_page_state,
        else: assigns.page_state

    assigns = assign(assigns, :content_state, content_state)

    ~H"""
    <div id="wallet-signer" phx-hook="WalletConnect" data-sui-chain={sui_chain()} class="hidden"></div>
    <section class="relative overflow-hidden px-4 py-12 sm:px-6 lg:px-8">
      <div class="mx-auto max-w-6xl space-y-8">
        <div class="rounded-[2rem] border border-space-600/80 bg-space-900/70 p-8 shadow-2xl shadow-black/40 backdrop-blur">
          <p class="font-mono text-xs uppercase tracking-[0.35em] text-quantum-300">
            Tribe Custodian
          </p>
          <h1 class="mt-3 text-4xl font-semibold text-cream">Diplomacy</h1>
        </div>

        <.signing_overlay :if={@page_state == :signing_tx} />

        <%= case @content_state do %>
          <% :no_custodian -> %>
            <.no_custodian_view />
          <% :discovery_error -> %>
            <.discovery_error_view />
          <% state when state in [:active, :active_readonly] -> %>
            <.governance_section
              active_custodian={@active_custodian}
              governance_data={@governance_data}
              governance_error={@governance_error}
              governance_expanded={@governance_expanded}
              is_member={@is_member}
              viewer_address={localnet_signer_address() || @current_account.address}
              tribe_members={@tribe_members}
            />
            <.tribe_standings_section
              tribe_standings={@tribe_standings}
              tribe_filter={@tribe_filter}
              world_tribes={@world_tribes}
              is_leader={@is_leader}
            />
            <.pilot_overrides_section
              pilot_standings={@pilot_standings}
              pilot_error={@pilot_error}
              is_leader={@is_leader}
            />
            <.default_standing_section default_standing={@default_standing} is_leader={@is_leader} />
          <% _other -> %>
            <div class="rounded-[2rem] border border-space-600/80 bg-space-900/70 p-8">
              <p class="text-sm text-cream">Loading...</p>
            </div>
        <% end %>
      </div>
    </section>
    """
  end

  @spec assign_base_state(Phoenix.LiveView.Socket.t(), non_neg_integer()) ::
          Phoenix.LiveView.Socket.t()
  defp assign_base_state(socket, tribe_id) do
    assign(socket,
      page_title: "Diplomacy — Tribe ##{tribe_id}",
      tribe_id: tribe_id,
      page_state: :loading,
      return_page_state: :active,
      active_custodian: nil,
      is_leader: false,
      tribe_standings: [],
      pilot_standings: [],
      default_standing: :neutral,
      world_tribes: [],
      tribe_filter: "",
      pending_tx_bytes: nil,
      pilot_error: nil,
      character_ref: nil,
      governance_expanded: false,
      governance_data: nil,
      governance_error: nil,
      is_member: false,
      tribe_members: [],
      ignore_governance_update: false
    )
  end

  @spec maybe_subscribe(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp maybe_subscribe(socket) do
    pubsub = socket.assigns[:pubsub]

    if connected?(socket) and pubsub do
      Phoenix.PubSub.subscribe(pubsub, "diplomacy")
      Phoenix.PubSub.subscribe(pubsub, Diplomacy.topic(socket.assigns.tribe_id))
    end

    socket
  end

  @spec build_tx(Phoenix.LiveView.Socket.t(), (Diplomacy.options() ->
                                                 {:ok, %{tx_bytes: String.t()}}
                                                 | {:error, term()})) ::
          Phoenix.LiveView.Socket.t()
  defp build_tx(socket, builder) when is_function(builder, 1) do
    Gov.build_transaction(socket, Gov.diplomacy_opts(socket), builder)
  end

  @spec valid_address?(String.t()) :: boolean()
  defp valid_address?("0x" <> hex) when byte_size(hex) == 64,
    do: match?({:ok, _}, Base.decode16(hex, case: :mixed))

  defp valid_address?(_other), do: false
end
