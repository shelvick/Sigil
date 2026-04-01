defmodule SigilWeb.DiplomacyLive do
  @moduledoc """
  Diplomacy editor for managing tribe custodians, standings, and pilot overrides.
  """

  use SigilWeb, :live_view

  import SigilWeb.DiplomacyLive.Components

  import SigilWeb.TransactionHelpers,
    only: [sui_chain: 1, localnet_signer_address: 1]

  import SigilWeb.TribeHelpers, only: [authorize_tribe: 2]

  alias SigilWeb.DiplomacyLive.{Events, State}

  @doc "Mounts the diplomacy editor for the given tribe id."
  @impl true
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) ::
          {:ok, Phoenix.LiveView.Socket.t()}
  def mount(%{"tribe_id" => tribe_id_str}, _session, socket) do
    case authorize_tribe(tribe_id_str, socket) do
      {:ok, tribe_id} ->
        socket =
          socket
          |> State.assign_base_state(tribe_id)
          |> State.discover_custodian_state()
          |> State.load_standings()
          |> State.maybe_subscribe()

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
  @spec handle_params(map(), String.t(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_params(params, _uri, socket) do
    reputation_view = if params["view"] == "reputation", do: :config, else: :summary
    {:noreply, assign(socket, :reputation_view, reputation_view)}
  end

  @doc false
  @impl true
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event(event, params, socket), do: Events.handle_event(event, params, socket)

  @doc false
  @impl true
  @spec handle_info(term(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_info(message, socket), do: Events.handle_info(message, socket)

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
    <div id="wallet-signer" phx-hook="WalletConnect" data-sui-chain={sui_chain(@world)} class="hidden"></div>
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
              viewer_address={localnet_signer_address(@world) || @current_account.address}
              tribe_members={@tribe_members}
            />
            <.tribe_standings_section
              tribe_standings={@tribe_standings}
              tribe_filter={@tribe_filter}
              world_tribes={@world_tribes}
              is_leader={@is_leader}
              reputation_scores={@reputation_scores}
            />
            <.pilot_overrides_section
              pilot_standings={@pilot_standings}
              pilot_error={@pilot_error}
              is_leader={@is_leader}
            />
            <.default_standing_section default_standing={@default_standing} is_leader={@is_leader} />
            <.oracle_controls_section
              :if={@is_leader}
              oracle_enabled={@oracle_enabled}
              oracle_address={@oracle_address}
              oracle_address_input={@oracle_address_input}
              tribe_id={@tribe_id}
            />
            <.reputation_config_panel :if={@is_leader and @reputation_view == :config} />
          <% _other -> %>
            <div class="rounded-[2rem] border border-space-600/80 bg-space-900/70 p-8">
              <p class="text-sm text-cream">Loading...</p>
            </div>
        <% end %>
      </div>
    </section>
    """
  end
end
