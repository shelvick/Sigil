defmodule SigilWeb.DiplomacyLive do
  @moduledoc """
  Diplomacy editor for managing tribe standings tables and pilot overrides.
  """

  use SigilWeb, :live_view

  import SigilWeb.DiplomacyLive.Components
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
          |> discover_tables()
          |> load_standings()
          |> maybe_subscribe()

        {:ok, socket}

      {:error, :unauthorized} ->
        {:ok,
         socket
         |> put_flash(:error, "Not your tribe")
         |> redirect(to: ~p"/")}

      {:error, :unauthenticated} ->
        {:ok, redirect(socket, to: ~p"/")}
    end
  end

  # ---------------------------------------------------------------------------
  # Events
  # ---------------------------------------------------------------------------

  @doc false
  @impl true
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("select_table", %{"id" => table_id}, socket) do
    case Enum.find(socket.assigns.available_tables, &(&1.object_id == table_id)) do
      nil ->
        {:noreply, put_flash(socket, :error, "Table not found")}

      table ->
        opts = diplomacy_opts(socket)
        Diplomacy.set_active_table(table, opts)

        {:noreply,
         socket
         |> assign(page_state: :active, active_table: table)
         |> load_standings()}
    end
  end

  def handle_event("create_table", _params, socket) do
    {:ok, %{tx_bytes: tx_bytes}} = Diplomacy.build_create_table_tx(diplomacy_opts(socket))
    {:noreply, enter_signing(socket, tx_bytes)}
  end

  def handle_event("add_tribe_standing", %{"tribe_id" => tid, "standing" => s}, socket) do
    build_set_standing(socket, String.to_integer(tid), String.to_integer(s))
  end

  def handle_event("set_standing", %{"standing" => ""}, socket) do
    {:noreply, socket}
  end

  def handle_event("set_standing", %{"tribe_id" => tid, "standing" => s}, socket) do
    build_set_standing(socket, String.to_integer(tid), String.to_integer(s))
  end

  def handle_event("batch_set_standings", %{"updates" => updates}, socket) do
    parsed =
      Enum.map(updates, fn %{"tribe_id" => tid, "standing" => s} ->
        {String.to_integer(tid), String.to_integer(s)}
      end)

    opts = diplomacy_opts(socket)

    case Diplomacy.build_batch_set_standings_tx(parsed, opts) do
      {:ok, %{tx_bytes: tx_bytes}} ->
        {:noreply, enter_signing(socket, tx_bytes)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to build transaction: #{inspect(reason)}")}
    end
  end

  def handle_event("add_pilot_override", %{"pilot_address" => pilot, "standing" => s}, socket) do
    standing = String.to_integer(s)

    if valid_address?(pilot) do
      opts = diplomacy_opts(socket)

      case Diplomacy.build_set_pilot_standing_tx(pilot, standing, opts) do
        {:ok, %{tx_bytes: tx_bytes}} ->
          {:noreply, enter_signing(socket, tx_bytes)}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Failed to build transaction: #{inspect(reason)}")}
      end
    else
      {:noreply, assign(socket, pilot_error: "Invalid address format")}
    end
  end

  def handle_event("set_default_standing", %{"standing" => standing_str}, socket) do
    standing = String.to_integer(standing_str)
    opts = diplomacy_opts(socket)

    case Diplomacy.build_set_default_standing_tx(standing, opts) do
      {:ok, %{tx_bytes: tx_bytes}} ->
        {:noreply, enter_signing(socket, tx_bytes)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to build transaction: #{inspect(reason)}")}
    end
  end

  def handle_event("filter_tribes", %{"query" => query}, socket) do
    {:noreply, assign(socket, tribe_filter: query)}
  end

  def handle_event("transaction_signed", %{"bytes" => tx_bytes, "signature" => signature}, socket) do
    opts = diplomacy_opts(socket)

    case Diplomacy.submit_signed_transaction(tx_bytes, signature, opts) do
      {:ok, %{digest: _digest, effects_bcs: effects_bcs}} ->
        socket =
          socket
          |> assign(page_state: :active, pending_tx_bytes: nil)
          |> load_standings()

        # Report effects back to wallet so it can update cached object versions
        socket =
          if effects_bcs,
            do: push_event(socket, "report_transaction_effects", %{effects: effects_bcs}),
            else: socket

        {:noreply, socket}

      {:error, _reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Transaction failed")
         |> assign(page_state: :active, pending_tx_bytes: nil)}
    end
  end

  def handle_event("transaction_error", %{"reason" => _reason}, socket) do
    {:noreply,
     socket
     |> put_flash(:info, "Transaction cancelled")
     |> assign(page_state: :active, pending_tx_bytes: nil)}
  end

  # Ignore wallet discovery events — hook auto-connects silently
  def handle_event("wallet_detected", _params, socket), do: {:noreply, socket}
  def handle_event("wallet_error", _params, socket), do: {:noreply, socket}

  # ---------------------------------------------------------------------------
  # PubSub
  # ---------------------------------------------------------------------------

  @doc false
  @impl true
  @spec handle_info(term(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_info({:standing_updated, _data}, socket) do
    {:noreply, load_standings(socket)}
  end

  def handle_info({:pilot_standing_updated, _data}, socket) do
    {:noreply, load_standings(socket)}
  end

  def handle_info({:default_standing_updated, _standing}, socket) do
    {:noreply, load_standings(socket)}
  end

  def handle_info({:table_discovered, _tables}, socket) do
    {:noreply, discover_tables(socket)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  @doc false
  @impl true
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <div id="wallet-signer" phx-hook="WalletConnect" data-sui-chain={sui_chain()} class="hidden"></div>
    <section class="relative overflow-hidden px-4 py-12 sm:px-6 lg:px-8">
      <div class="mx-auto max-w-6xl space-y-8">
        <div class="rounded-[2rem] border border-space-600/80 bg-space-900/70 p-8 shadow-2xl shadow-black/40 backdrop-blur">
          <p class="font-mono text-xs uppercase tracking-[0.35em] text-quantum-300">
            Diplomacy editor
          </p>
          <h1 class="mt-3 text-4xl font-semibold text-cream">Diplomacy</h1>
        </div>

        <%= case @page_state do %>
          <% :no_table -> %>
            <.no_table_view />
          <% :select_table -> %>
            <.select_table_view available_tables={@available_tables} />
          <% state when state in [:active, :signing_tx] -> %>
            <.signing_overlay :if={@page_state == :signing_tx} />
            <.tribe_standings_section
              tribe_standings={@tribe_standings}
              tribe_filter={@tribe_filter}
              world_tribes={@world_tribes}
            />
            <.pilot_overrides_section
              pilot_standings={@pilot_standings}
              pilot_error={@pilot_error}
            />
            <.default_standing_section default_standing={@default_standing} />
          <% _other -> %>
            <div class="rounded-[2rem] border border-space-600/80 bg-space-900/70 p-8">
              <p class="text-sm text-cream">Loading...</p>
            </div>
        <% end %>
      </div>
    </section>
    """
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  @spec assign_base_state(Phoenix.LiveView.Socket.t(), non_neg_integer()) ::
          Phoenix.LiveView.Socket.t()
  defp assign_base_state(socket, tribe_id) do
    assign(socket,
      page_title: "Diplomacy",
      tribe_id: tribe_id,
      page_state: :loading,
      available_tables: [],
      active_table: nil,
      tribe_standings: [],
      pilot_standings: [],
      default_standing: :neutral,
      world_tribes: [],
      tribe_filter: "",
      pending_tx_bytes: nil,
      pilot_error: nil
    )
  end

  @spec discover_tables(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp discover_tables(%{assigns: %{cache_tables: cache_tables}} = socket)
       when not is_map_key(cache_tables, :standings) do
    assign(socket, page_state: :no_table)
  end

  defp discover_tables(socket) do
    cache_tables = socket.assigns[:cache_tables]
    sender = localnet_signer_address() || socket.assigns.current_account.address
    pubsub = socket.assigns[:pubsub]

    if connected?(socket) do
      opts = [tables: cache_tables, pubsub: pubsub, sender: sender]

      case Diplomacy.discover_tables(sender, opts) do
        {:ok, []} -> assign(socket, page_state: :no_table)
        {:ok, [_single]} -> assign(socket, page_state: :active)
        {:ok, tables} -> assign(socket, page_state: :select_table, available_tables: tables)
        {:error, _reason} -> assign(socket, page_state: :no_table)
      end
    else
      active = Diplomacy.get_active_table(tables: cache_tables, sender: sender)

      if active do
        assign(socket, page_state: :active, active_table: active)
      else
        assign(socket, page_state: :no_table)
      end
    end
  end

  @spec load_standings(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp load_standings(socket) do
    cache_tables = socket.assigns[:cache_tables]

    if is_map(cache_tables) and is_map_key(cache_tables, :standings) do
      world_tribes =
        cache_tables.standings
        |> Cache.match({{:world_tribe, :_}, :_})
        |> Enum.map(fn {{:world_tribe, _id}, tribe} -> tribe end)

      assign(socket,
        tribe_standings: Diplomacy.list_standings(tables: cache_tables),
        pilot_standings: Diplomacy.list_pilot_standings(tables: cache_tables),
        default_standing: Diplomacy.get_default_standing(tables: cache_tables),
        world_tribes: world_tribes
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
    [
      tables: socket.assigns.cache_tables,
      pubsub: socket.assigns.pubsub,
      sender: socket.assigns.current_account.address
    ]
  end

  @spec enter_signing(Phoenix.LiveView.Socket.t(), String.t()) :: Phoenix.LiveView.Socket.t()
  defp enter_signing(socket, tx_bytes) do
    if localnet?() do
      sign_and_submit_locally(socket, tx_bytes)
    else
      socket
      |> assign(page_state: :signing_tx, pending_tx_bytes: tx_bytes)
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
        |> assign(page_state: :active, pending_tx_bytes: nil)
        |> maybe_rediscover_tables()
        |> load_standings()

      {:error, reason} ->
        socket
        |> put_flash(:error, "Transaction failed: #{inspect(reason)}")
        |> assign(page_state: :active, pending_tx_bytes: nil)
    end
  end

  @spec maybe_rediscover_tables(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp maybe_rediscover_tables(%{assigns: %{active_table: nil}} = socket),
    do: discover_tables(socket)

  defp maybe_rediscover_tables(socket), do: socket

  @spec localnet?() :: boolean()
  defp localnet? do
    Application.fetch_env!(:sigil, :eve_world) == "localnet"
  end

  @spec localnet_signer_address() :: String.t() | nil
  defp localnet_signer_address do
    if localnet?(), do: Sigil.Diplomacy.LocalSigner.signer_address()
  end

  @spec build_set_standing(Phoenix.LiveView.Socket.t(), non_neg_integer(), non_neg_integer()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  defp build_set_standing(socket, tribe_id, standing) do
    opts = diplomacy_opts(socket)

    case Diplomacy.build_set_standing_tx(tribe_id, standing, opts) do
      {:ok, %{tx_bytes: tx_bytes}} ->
        {:noreply, enter_signing(socket, tx_bytes)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to build transaction: #{inspect(reason)}")}
    end
  end

  @spec valid_address?(String.t()) :: boolean()
  defp valid_address?("0x" <> hex) when byte_size(hex) == 64 do
    case Base.decode16(hex, case: :mixed) do
      {:ok, _bytes} -> true
      :error -> false
    end
  end

  defp valid_address?(_other), do: false

  @sui_chains %{
    "stillness" => "sui:testnet",
    "utopia" => "sui:testnet",
    "internal" => "sui:testnet",
    "localnet" => "sui:testnet",
    "mainnet" => "sui:mainnet"
  }

  @spec sui_chain() :: String.t()
  defp sui_chain do
    world = Application.fetch_env!(:sigil, :eve_world)
    Map.get(@sui_chains, world, "sui:testnet")
  end
end
