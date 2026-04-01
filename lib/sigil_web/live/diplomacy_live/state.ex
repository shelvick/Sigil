defmodule SigilWeb.DiplomacyLive.State do
  @moduledoc """
  Shared state and data-loading helpers for the diplomacy LiveView.
  """

  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [put_flash: 3]

  import SigilWeb.TransactionHelpers, only: [localnet_signer_address: 1]

  alias Sigil.{Cache, Diplomacy, Worlds}

  @doc "Assigns baseline diplomacy page state for the selected tribe."
  @spec assign_base_state(Phoenix.LiveView.Socket.t(), non_neg_integer()) ::
          Phoenix.LiveView.Socket.t()
  def assign_base_state(socket, tribe_id) do
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
      ignore_governance_update: false,
      reputation_scores: %{},
      oracle_enabled: false,
      oracle_address: nil,
      oracle_address_input: "",
      reputation_view: :summary
    )
  end

  @doc "Discovers and applies the current custodian state for the selected tribe."
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
      if Phoenix.LiveView.connected?(socket) do
        Diplomacy.discover_custodian(tribe_id, opts)
      else
        {:ok, Diplomacy.get_active_custodian(opts)}
      end

    case result do
      {:ok, custodian} -> apply_discovered_custodian(socket, custodian)
      {:error, _reason} -> assign_discovery_error(socket)
    end
  end

  @doc "Applies discovered custodian state to page assigns."
  @spec apply_discovered_custodian(Phoenix.LiveView.Socket.t(), Diplomacy.custodian_info() | nil) ::
          Phoenix.LiveView.Socket.t()
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
      is_leader: is_leader
    )
  end

  @doc "Applies discovery error state and message to the socket."
  @spec assign_discovery_error(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def assign_discovery_error(socket) do
    socket
    |> put_flash(:error, "Custodian discovery failed")
    |> assign(
      page_state: :discovery_error,
      return_page_state: :discovery_error,
      active_custodian: nil,
      is_leader: false
    )
  end

  @doc "Loads standings, overrides, and reputation details from cache/context."
  @spec load_standings(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def load_standings(socket) do
    cache_tables = socket.assigns[:cache_tables]
    tribe_id = socket.assigns[:tribe_id]

    sender =
      localnet_signer_address(socket.assigns.world) || socket.assigns.current_account.address

    if is_map(cache_tables) and is_map_key(cache_tables, :standings) do
      active_character = socket.assigns[:active_character]

      character_ref =
        case active_character do
          nil -> nil
          %{id: character_id} -> Cache.get(cache_tables.standings, {:character_ref, character_id})
        end

      opts = [
        tables: cache_tables,
        tribe_id: tribe_id,
        sender: sender,
        world: socket.assigns.world
      ]

      active_custodian = Diplomacy.get_active_custodian(opts) || socket.assigns.active_custodian

      world_tribes =
        cache_tables.standings
        |> Cache.match({{:world_tribe, :_}, :_})
        |> Enum.map(fn {{:world_tribe, _id}, tribe} -> tribe end)

      standings = Diplomacy.list_standings(opts)

      reputation_scores =
        opts
        |> Diplomacy.list_reputation_scores()
        |> Map.new(&{&1.target_tribe_id, &1})

      oracle_address = active_custodian && Map.get(active_custodian, :oracle_address)

      socket =
        assign(socket,
          active_custodian: active_custodian,
          tribe_standings: standings,
          pilot_standings: Diplomacy.list_pilot_standings(opts),
          default_standing: Diplomacy.get_default_standing(opts),
          world_tribes: world_tribes,
          character_ref: character_ref,
          is_leader: Diplomacy.leader?(Keyword.put(opts, :character_ref, character_ref)),
          reputation_scores: reputation_scores,
          oracle_enabled: Diplomacy.oracle_enabled?(opts),
          oracle_address: oracle_address,
          oracle_address_input: socket.assigns.oracle_address_input
        )

      SigilWeb.DiplomacyLive.Governance.load_governance_state(socket, opts)
    else
      socket
    end
  end

  @doc "Subscribes connected clients to diplomacy and reputation PubSub topics."
  @spec maybe_subscribe(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def maybe_subscribe(socket) do
    pubsub = socket.assigns[:pubsub]

    if Phoenix.LiveView.connected?(socket) and pubsub do
      opts = diplomacy_opts(socket)
      world = Keyword.fetch!(opts, :world)

      Phoenix.PubSub.subscribe(pubsub, Diplomacy.legacy_topic(opts))
      Phoenix.PubSub.subscribe(pubsub, Worlds.topic(world, "reputation"))
      Phoenix.PubSub.subscribe(pubsub, Diplomacy.topic(socket.assigns.tribe_id, opts))
    end

    socket
  end

  @doc "Builds diplomacy context opts from the current socket session state."
  @spec diplomacy_opts(Phoenix.LiveView.Socket.t()) :: Diplomacy.options()
  def diplomacy_opts(socket) do
    active_character = socket.assigns[:active_character]

    [
      tables: socket.assigns.cache_tables,
      pubsub: socket.assigns.pubsub,
      sender:
        localnet_signer_address(socket.assigns.world) || socket.assigns.current_account.address,
      tribe_id: socket.assigns.tribe_id,
      character_id: active_character && active_character.id,
      character_ref: socket.assigns.character_ref,
      world: socket.assigns.world
    ]
  end

  @doc "Resolves character ref from cache or context for transaction building."
  @spec maybe_resolve_character_ref(Phoenix.LiveView.Socket.t(), Diplomacy.options()) ::
          Diplomacy.character_ref() | nil
  def maybe_resolve_character_ref(socket, opts) do
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

  @doc "Refreshes diplomacy data after successful transaction submission."
  @spec maybe_refresh_after_submission(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def maybe_refresh_after_submission(%{assigns: %{return_page_state: :no_custodian}} = socket) do
    socket = socket |> discover_custodian_state() |> load_standings()

    if socket.assigns.page_state == :no_custodian,
      do: Process.send_after(self(), {:rediscover_custodian, 1}, 1_000)

    socket
  end

  def maybe_refresh_after_submission(socket), do: load_standings(socket)

  @doc "Loads current active custodian from cache and applies state assigns."
  @spec apply_cached_custodian_state(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def apply_cached_custodian_state(socket) do
    socket
    |> diplomacy_opts()
    |> Diplomacy.get_active_custodian()
    |> then(&apply_discovered_custodian(socket, &1))
  end

  @doc "Validates `0x` prefixed 32-byte hex addresses from form params."
  @spec valid_address?(String.t()) :: boolean()
  def valid_address?("0x" <> hex) when byte_size(hex) == 64,
    do: match?({:ok, _}, Base.decode16(hex, case: :mixed))

  def valid_address?(_other), do: false

  @doc "Parses string standing params into canonical standing atoms."
  @spec standing_from_param(String.t()) :: {:ok, Diplomacy.standing_atom()} | :error
  def standing_from_param("hostile"), do: {:ok, :hostile}
  def standing_from_param("unfriendly"), do: {:ok, :unfriendly}
  def standing_from_param("neutral"), do: {:ok, :neutral}
  def standing_from_param("friendly"), do: {:ok, :friendly}
  def standing_from_param("allied"), do: {:ok, :allied}
  def standing_from_param("0"), do: {:ok, :hostile}
  def standing_from_param("1"), do: {:ok, :unfriendly}
  def standing_from_param("2"), do: {:ok, :neutral}
  def standing_from_param("3"), do: {:ok, :friendly}
  def standing_from_param("4"), do: {:ok, :allied}
  def standing_from_param(_other), do: :error
end
