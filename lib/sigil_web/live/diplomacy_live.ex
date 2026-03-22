defmodule SigilWeb.DiplomacyLive do
  @moduledoc """
  Diplomacy editor for managing tribe custodians, standings, and pilot overrides.
  """

  use SigilWeb, :live_view

  import SigilWeb.DiplomacyLive.Components

  import SigilWeb.TransactionHelpers,
    only: [localnet?: 0, sui_chain: 0, localnet_signer_address: 0]

  import SigilWeb.TribeHelpers, only: [authorize_tribe: 2]

  alias Sigil.{Cache, Diplomacy}

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
          |> discover_custodian_state()
          |> load_standings()
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
     |> build_transaction(&Diplomacy.build_create_custodian_tx/1)}
  end

  def handle_event("retry_discovery", _params, socket) do
    {:noreply,
     socket
     |> clear_flash()
     |> discover_custodian_state()
     |> load_standings()}
  end

  def handle_event("add_tribe_standing", %{"tribe_id" => tid, "standing" => s}, socket) do
    case Integer.parse(tid) do
      {tribe_id, ""} ->
        {:noreply,
         socket
         |> clear_flash()
         |> build_transaction(
           &Diplomacy.build_set_standing_tx(tribe_id, String.to_integer(s), &1)
         )}

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
     |> build_transaction(
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
     |> build_transaction(&Diplomacy.build_batch_set_standings_tx(parsed, &1))}
  end

  def handle_event("add_pilot_override", %{"pilot_address" => pilot, "standing" => s}, socket) do
    if valid_address?(pilot) do
      {:noreply,
       socket
       |> clear_flash()
       |> assign(pilot_error: nil)
       |> build_transaction(
         &Diplomacy.build_set_pilot_standing_tx(pilot, String.to_integer(s), &1)
       )}
    else
      {:noreply, assign(socket, pilot_error: "Invalid address format")}
    end
  end

  def handle_event("set_default_standing", %{"standing" => standing_str}, socket) do
    {:noreply,
     socket
     |> clear_flash()
     |> build_transaction(
       &Diplomacy.build_set_default_standing_tx(String.to_integer(standing_str), &1)
     )}
  end

  def handle_event("filter_tribes", %{"query" => query}, socket) do
    {:noreply, assign(socket, tribe_filter: query)}
  end

  def handle_event("transaction_signed", %{"bytes" => tx_bytes, "signature" => signature}, socket) do
    case Diplomacy.submit_signed_transaction(tx_bytes, signature, diplomacy_opts(socket)) do
      {:ok, %{digest: _digest, effects_bcs: effects_bcs}} ->
        socket =
          socket
          |> assign(page_state: socket.assigns.return_page_state, pending_tx_bytes: nil)
          |> maybe_refresh_after_submission()

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
  def handle_info({:standing_updated, _data}, socket), do: {:noreply, load_standings(socket)}

  def handle_info({:pilot_standing_updated, _data}, socket),
    do: {:noreply, load_standings(socket)}

  def handle_info({:default_standing_updated, _standing}, socket),
    do: {:noreply, load_standings(socket)}

  def handle_info({:custodian_discovered, custodian}, socket),
    do: {:noreply, socket |> apply_discovered_custodian(custodian) |> load_standings()}

  def handle_info({:custodian_created, _custodian}, socket),
    do: {:noreply, socket |> apply_cached_custodian_state() |> load_standings()}

  def handle_info(:rediscover_custodian, socket),
    do: {:noreply, socket |> discover_custodian_state() |> load_standings()}

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
      character_ref: nil
    )
  end

  @spec discover_custodian_state(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp discover_custodian_state(%{assigns: %{cache_tables: cache_tables}} = socket)
       when not is_map_key(cache_tables, :standings),
       do:
         assign(socket,
           page_state: :no_custodian,
           return_page_state: :no_custodian,
           active_custodian: nil
         )

  defp discover_custodian_state(socket) do
    opts = diplomacy_opts(socket)
    tribe_id = socket.assigns.tribe_id

    result =
      if connected?(socket) do
        Diplomacy.discover_custodian(tribe_id, opts)
      else
        {:ok, Diplomacy.get_active_custodian(opts)}
      end

    case result do
      {:ok, custodian} -> apply_discovered_custodian(socket, custodian)
      {:error, _reason} -> assign_discovery_error(socket)
    end
  end

  @doc false
  @spec apply_discovered_custodian(Phoenix.LiveView.Socket.t(), Diplomacy.custodian_info() | nil) ::
          Phoenix.LiveView.Socket.t()
  defp apply_discovered_custodian(socket, nil),
    do:
      assign(socket,
        page_title: "Your tribe doesn't have a Tribe Custodian yet",
        page_state: :no_custodian,
        return_page_state: :no_custodian,
        active_custodian: nil,
        is_leader: false
      )

  defp apply_discovered_custodian(socket, custodian) do
    opts = diplomacy_opts(socket)
    is_leader = Diplomacy.leader?(opts)
    page_state = if is_leader, do: :active, else: :active_readonly

    assign(socket,
      page_title: "Diplomacy — Tribe ##{socket.assigns.tribe_id}",
      page_state: page_state,
      return_page_state: page_state,
      active_custodian: custodian,
      is_leader: is_leader
    )
  end

  @spec assign_discovery_error(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp assign_discovery_error(socket) do
    socket
    |> put_flash(:error, "Custodian discovery failed")
    |> assign(
      page_state: :discovery_error,
      return_page_state: :discovery_error,
      active_custodian: nil,
      is_leader: false
    )
  end

  @spec load_standings(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp load_standings(socket) do
    cache_tables = socket.assigns[:cache_tables]
    tribe_id = socket.assigns[:tribe_id]
    sender = localnet_signer_address() || socket.assigns.current_account.address

    if is_map(cache_tables) and is_map_key(cache_tables, :standings) do
      active_character = socket.assigns[:active_character]

      character_ref =
        case active_character do
          nil -> nil
          %{id: character_id} -> Cache.get(cache_tables.standings, {:character_ref, character_id})
        end

      opts = [tables: cache_tables, tribe_id: tribe_id, sender: sender]
      active_custodian = socket.assigns.active_custodian || Diplomacy.get_active_custodian(opts)

      world_tribes =
        cache_tables.standings
        |> Cache.match({{:world_tribe, :_}, :_})
        |> Enum.map(fn {{:world_tribe, _id}, tribe} -> tribe end)

      assign(socket,
        active_custodian: active_custodian,
        tribe_standings: Diplomacy.list_standings(opts),
        pilot_standings: Diplomacy.list_pilot_standings(opts),
        default_standing: Diplomacy.get_default_standing(opts),
        world_tribes: world_tribes,
        character_ref: character_ref,
        is_leader: Diplomacy.leader?(Keyword.put(opts, :character_ref, character_ref))
      )
    else
      socket
    end
  end

  @spec maybe_subscribe(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp maybe_subscribe(socket) do
    pubsub = socket.assigns[:pubsub]

    if connected?(socket) and pubsub do
      Phoenix.PubSub.subscribe(pubsub, "diplomacy")
    end

    socket
  end

  @spec diplomacy_opts(Phoenix.LiveView.Socket.t()) :: Diplomacy.options()
  defp diplomacy_opts(socket) do
    active_character = socket.assigns[:active_character]

    [
      tables: socket.assigns.cache_tables,
      pubsub: socket.assigns.pubsub,
      sender: localnet_signer_address() || socket.assigns.current_account.address,
      tribe_id: socket.assigns.tribe_id,
      character_id: active_character && active_character.id,
      character_ref: socket.assigns.character_ref
    ]
  end

  @spec build_transaction(Phoenix.LiveView.Socket.t(), (Diplomacy.options() ->
                                                          {:ok, %{tx_bytes: String.t()}}
                                                          | {:error, term()})) ::
          Phoenix.LiveView.Socket.t()
  defp build_transaction(socket, builder) when is_function(builder, 1) do
    opts = diplomacy_opts(socket)

    case socket.assigns.character_ref || maybe_resolve_character_ref(socket, opts) do
      nil ->
        put_flash(socket, :error, "Active character reference unavailable")

      character_ref ->
        socket
        |> assign(character_ref: character_ref)
        |> handle_tx_build_result(builder.(Keyword.put(opts, :character_ref, character_ref)))
    end
  end

  @spec handle_tx_build_result(
          Phoenix.LiveView.Socket.t(),
          {:ok, %{tx_bytes: String.t()}} | {:error, term()}
        ) :: Phoenix.LiveView.Socket.t()
  defp handle_tx_build_result(socket, {:ok, %{tx_bytes: tx_bytes}}),
    do: enter_signing(socket, tx_bytes)

  defp handle_tx_build_result(socket, {:error, :no_character_ref}),
    do: put_flash(socket, :error, "Active character reference unavailable")

  defp handle_tx_build_result(socket, {:error, :no_active_custodian}),
    do: put_flash(socket, :error, "No Tribe Custodian configured")

  defp handle_tx_build_result(socket, {:error, reason}) do
    put_flash(socket, :error, "Failed to build transaction: #{inspect(reason)}")
  end

  @spec maybe_resolve_character_ref(Phoenix.LiveView.Socket.t(), Diplomacy.options()) ::
          Diplomacy.character_ref() | nil
  defp maybe_resolve_character_ref(socket, opts) do
    case socket.assigns[:active_character] do
      %{id: character_id} ->
        case Diplomacy.resolve_character_ref(character_id, opts) do
          {:ok, ref} -> ref
          _ -> nil
        end

      _ ->
        nil
    end
  end

  @spec enter_signing(Phoenix.LiveView.Socket.t(), String.t()) :: Phoenix.LiveView.Socket.t()
  defp enter_signing(socket, tx_bytes) do
    if localnet?() do
      sign_and_submit_locally(socket, tx_bytes)
    else
      socket
      |> assign(
        page_state: :signing_tx,
        return_page_state: socket.assigns.page_state,
        pending_tx_bytes: tx_bytes
      )
      |> push_event("request_sign_transaction", %{"tx_bytes" => tx_bytes})
    end
  end

  @spec sign_and_submit_locally(Phoenix.LiveView.Socket.t(), String.t()) ::
          Phoenix.LiveView.Socket.t()
  defp sign_and_submit_locally(socket, kind_bytes) do
    opts = diplomacy_opts(socket)

    case Diplomacy.sign_and_submit_locally(kind_bytes, opts) do
      {:ok, %{digest: _digest}} ->
        socket
        |> put_flash(:info, "Transaction confirmed (local signing)")
        |> assign(page_state: socket.assigns.page_state, pending_tx_bytes: nil)
        |> maybe_refresh_after_submission()

      {:error, reason} ->
        socket
        |> put_flash(:error, "Transaction failed: #{inspect(reason)}")
        |> assign(pending_tx_bytes: nil)
    end
  end

  @spec maybe_refresh_after_submission(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp maybe_refresh_after_submission(%{assigns: %{return_page_state: :no_custodian}} = socket) do
    socket = socket |> discover_custodian_state() |> load_standings()

    if socket.assigns.page_state == :no_custodian,
      do: Process.send_after(self(), :rediscover_custodian, 2_000)

    socket
  end

  defp maybe_refresh_after_submission(socket), do: load_standings(socket)

  @spec apply_cached_custodian_state(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp apply_cached_custodian_state(socket) do
    socket
    |> diplomacy_opts()
    |> Diplomacy.get_active_custodian()
    |> then(&apply_discovered_custodian(socket, &1))
  end

  @spec valid_address?(String.t()) :: boolean()
  defp valid_address?("0x" <> hex) when byte_size(hex) == 64,
    do: match?({:ok, _}, Base.decode16(hex, case: :mixed))

  defp valid_address?(_other), do: false
end
