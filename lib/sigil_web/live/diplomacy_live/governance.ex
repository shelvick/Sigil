defmodule SigilWeb.DiplomacyLive.Governance do
  @moduledoc """
  Governance state management and transaction building helpers for
  `SigilWeb.DiplomacyLive`. Handles governance data loading, transaction
  construction, wallet signing flow, and post-submission refresh.

  Extracted from `SigilWeb.DiplomacyLive` to keep the LiveView module
  under 500 lines.
  """

  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [put_flash: 3, push_event: 3, connected?: 1]

  import SigilWeb.TransactionHelpers,
    only: [localnet?: 0, localnet_signer_address: 0]

  alias Sigil.{Cache, Diplomacy, Tribes}

  @doc "Loads governance state (members, votes, tallies) into the socket."
  @spec load_governance_state(Phoenix.LiveView.Socket.t(), Diplomacy.options()) ::
          Phoenix.LiveView.Socket.t()
  def load_governance_state(%{assigns: %{active_custodian: nil}} = socket, _opts) do
    assign(socket,
      governance_data: nil,
      governance_error: nil,
      is_member: false,
      tribe_members: []
    )
  end

  def load_governance_state(socket, opts) do
    tribe_id = socket.assigns.tribe_id
    cache_tables = socket.assigns.cache_tables

    tribe_members = Tribes.list_members(tribe_id, tables: cache_tables)

    governance_data =
      Cache.get(cache_tables.standings, {:governance_data, tribe_id}) ||
        load_governance_data_from_chain(opts)

    case governance_data do
      {:error, _reason} ->
        assign(socket,
          governance_data: %{votes: %{}, tallies: %{}},
          governance_error: "Unable to load governance data",
          is_member: Diplomacy.member?(opts),
          tribe_members: tribe_members
        )

      data ->
        assign(socket,
          governance_data: data,
          governance_error: nil,
          is_member: Diplomacy.member?(opts),
          tribe_members: tribe_members
        )
    end
  end

  @doc "Builds a transaction, resolving character ref and entering signing flow."
  @spec build_transaction(
          Phoenix.LiveView.Socket.t(),
          Diplomacy.options(),
          (Diplomacy.options() -> {:ok, %{tx_bytes: String.t()}} | {:error, term()})
        ) :: Phoenix.LiveView.Socket.t()
  def build_transaction(socket, opts, builder) when is_function(builder, 1) do
    case socket.assigns.character_ref || maybe_resolve_character_ref(socket, opts) do
      nil ->
        put_flash(socket, :error, "Active character reference unavailable")

      character_ref ->
        socket
        |> assign(character_ref: character_ref)
        |> handle_tx_build_result(builder.(Keyword.put(opts, :character_ref, character_ref)))
    end
  end

  @doc "Enters the signing flow or submits locally, returning the updated socket."
  @spec enter_signing(Phoenix.LiveView.Socket.t(), String.t()) :: Phoenix.LiveView.Socket.t()
  def enter_signing(socket, tx_bytes) do
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

  @doc "Signs and submits a transaction locally, refreshing state on success."
  @spec sign_and_submit_locally(Phoenix.LiveView.Socket.t(), String.t()) ::
          Phoenix.LiveView.Socket.t()
  def sign_and_submit_locally(socket, kind_bytes) do
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

  @doc "Refreshes standings (and possibly custodian) after a successful submission."
  @spec maybe_refresh_after_submission(Phoenix.LiveView.Socket.t()) ::
          Phoenix.LiveView.Socket.t()
  def maybe_refresh_after_submission(%{assigns: %{return_page_state: :no_custodian}} = socket) do
    socket = socket |> discover_custodian_state() |> load_standings()

    if socket.assigns.page_state == :no_custodian,
      do: Process.send_after(self(), :rediscover_custodian, 2_000)

    socket
  end

  def maybe_refresh_after_submission(socket), do: load_standings(socket)

  @doc "Checks whether a pending tx is a governance operation (vote/claim)."
  @spec governance_tx?(Phoenix.LiveView.Socket.t(), String.t()) :: boolean()
  def governance_tx?(socket, tx_bytes) do
    case Cache.get(socket.assigns.cache_tables.standings, {:pending_tx, tx_bytes}) do
      {:vote_leader, _candidate} -> true
      :claim_leadership -> true
      _other -> false
    end
  end

  @doc "Re-applies the cached custodian state from ETS."
  @spec apply_cached_custodian_state(Phoenix.LiveView.Socket.t()) ::
          Phoenix.LiveView.Socket.t()
  def apply_cached_custodian_state(socket) do
    socket
    |> diplomacy_opts()
    |> Diplomacy.get_active_custodian()
    |> then(&apply_discovered_custodian(socket, &1))
  end

  @doc "Discovers and applies the custodian state for the socket's tribe."
  @spec discover_custodian_state(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def discover_custodian_state(%{assigns: %{cache_tables: cache_tables}} = socket)
      when not is_map_key(cache_tables, :standings),
      do:
        assign(socket,
          page_state: :no_custodian,
          return_page_state: :no_custodian,
          active_custodian: nil
        )

  def discover_custodian_state(socket) do
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

  @doc "Applies a discovered custodian (or nil) to the socket assigns."
  @spec apply_discovered_custodian(
          Phoenix.LiveView.Socket.t(),
          Diplomacy.custodian_info() | nil
        ) :: Phoenix.LiveView.Socket.t()
  def apply_discovered_custodian(socket, nil),
    do:
      assign(socket,
        page_title: "Your tribe doesn't have a Tribe Custodian yet",
        page_state: :no_custodian,
        return_page_state: :no_custodian,
        active_custodian: nil,
        is_leader: false
      )

  def apply_discovered_custodian(socket, custodian) do
    opts = diplomacy_opts(socket)
    is_leader = Diplomacy.leader?(opts)
    page_state = if is_leader, do: :active, else: :active_readonly

    assign(socket,
      page_title: "Diplomacy — Tribe ##{socket.assigns.tribe_id}",
      page_state: page_state,
      return_page_state: page_state,
      active_custodian: custodian,
      is_leader: is_leader,
      governance_expanded: false
    )
  end

  @doc "Loads all standings, custodian, world tribes, and governance into the socket."
  @spec load_standings(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def load_standings(socket) do
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
      active_custodian = Diplomacy.get_active_custodian(opts) || socket.assigns.active_custodian

      world_tribes =
        cache_tables.standings
        |> Cache.match({{:world_tribe, :_}, :_})
        |> Enum.map(fn {{:world_tribe, _id}, tribe} -> tribe end)

      socket =
        assign(socket,
          active_custodian: active_custodian,
          tribe_standings: Diplomacy.list_standings(opts),
          pilot_standings: Diplomacy.list_pilot_standings(opts),
          default_standing: Diplomacy.get_default_standing(opts),
          world_tribes: world_tribes,
          character_ref: character_ref,
          is_leader: Diplomacy.leader?(Keyword.put(opts, :character_ref, character_ref))
        )

      load_governance_state(socket, opts)
    else
      socket
    end
  end

  @doc "Builds the diplomacy opts keyword list from socket assigns."
  @spec diplomacy_opts(Phoenix.LiveView.Socket.t()) :: Diplomacy.options()
  def diplomacy_opts(socket) do
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

  # -- Private helpers --

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

  @spec load_governance_data_from_chain(Diplomacy.options()) ::
          Diplomacy.governance_data() | {:error, term()}
  defp load_governance_data_from_chain(opts) do
    try do
      case Diplomacy.load_governance_data(opts) do
        {:ok, governance_data} -> governance_data
        {:error, _reason} = error -> error
      end
    rescue
      error -> {:error, error}
    catch
      :exit, reason -> {:error, reason}
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
end
