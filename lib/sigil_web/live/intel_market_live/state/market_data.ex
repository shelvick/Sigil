defmodule SigilWeb.IntelMarketLive.State.MarketData do
  @moduledoc """
  Market data loading and pseudonym synchronization helpers for IntelMarketLive state.
  """

  import Phoenix.Component, only: [assign: 2, assign: 3]

  alias Sigil.{Intel, IntelMarket, Pseudonyms, StaticData}
  alias SigilWeb.IntelMarketLive.State

  @doc "Reloads listings, seller listings, purchased listings, and reputation cache."
  @spec load_listings(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def load_listings(socket) do
    opts = State.market_opts(socket)
    active_listings = IntelMarket.list_listings(opts)
    pseudonym_addresses = seller_addresses(socket)
    purchased_listings = IntelMarket.list_purchased_listings(socket.assigns.sender || "", opts)

    feedback_recorded = load_feedback_recorded(purchased_listings, socket, opts)

    assign(socket,
      listings: active_listings,
      my_listings: IntelMarket.list_all_seller_listings(pseudonym_addresses, opts),
      purchased_listings: purchased_listings,
      reputation_cache: load_reputation_cache(active_listings, socket, opts),
      feedback_recorded: feedback_recorded
    )
  end

  @doc "Loads reports for seller workflows and coerces entry mode when no reports exist."
  @spec load_reports(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def load_reports(%{assigns: %{can_sell: false}} = socket) do
    socket
    |> assign(my_reports: [])
    |> State.assign_listing_form(%{"entry_mode" => "manual"})
  end

  def load_reports(socket) do
    reports =
      socket.assigns.tribe_id
      |> Intel.list_intel(State.intel_opts(socket))
      |> Enum.filter(&(&1.reported_by == socket.assigns.sender))

    socket
    |> assign(my_reports: reports)
    |> ensure_entry_mode(reports)
  end

  @doc "Loads pseudonyms from persistence and keeps browser cache in sync when connected."
  @spec load_pseudonyms(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def load_pseudonyms(%{assigns: %{sender: sender}} = socket) when is_binary(sender) do
    pseudonyms = Pseudonyms.list_pseudonyms(sender)
    active_pseudonym = choose_active_pseudonym(socket, pseudonyms)

    socket
    |> assign(
      pseudonyms: pseudonyms,
      active_pseudonym: active_pseudonym,
      pending_active_pseudonym: active_pseudonym
    )
    |> maybe_push_pseudonyms()
  end

  def load_pseudonyms(socket) do
    socket
    |> assign(pseudonyms: [], active_pseudonym: nil, pending_active_pseudonym: nil)
    |> maybe_push_pseudonyms()
  end

  @doc "Reloads persisted pseudonyms without forcing browser-side decrypt lifecycle."
  @spec reload_pseudonyms(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def reload_pseudonyms(socket) do
    case socket.assigns[:sender] do
      sender when is_binary(sender) ->
        pseudonyms = Pseudonyms.list_pseudonyms(sender)
        active_pseudonym = choose_active_pseudonym(socket, pseudonyms)

        assign(socket,
          pseudonyms: pseudonyms,
          active_pseudonym: active_pseudonym,
          pending_active_pseudonym: active_pseudonym
        )

      _other ->
        assign(socket, pseudonyms: [], active_pseudonym: nil, pending_active_pseudonym: nil)
    end
  end

  @doc "Syncs server pseudonym state with browser-loaded key availability."
  @spec sync_loaded_pseudonyms(Phoenix.LiveView.Socket.t(), [String.t()], String.t() | nil) ::
          Phoenix.LiveView.Socket.t()
  def sync_loaded_pseudonyms(socket, addresses, active_address) do
    if is_list(addresses) do
      pseudonyms = loaded_pseudonyms(socket.assigns.pseudonyms, addresses)
      active_pseudonym = loaded_active_pseudonym(pseudonyms, active_address)

      assign(socket,
        pseudonyms: pseudonyms,
        active_pseudonym: active_pseudonym,
        pending_active_pseudonym: active_pseudonym,
        pseudonym_error_message: nil
      )
    else
      assign(socket, pseudonym_error_message: "Failed to load pseudonyms")
    end
  end

  @doc "Returns sender derived from current account assign."
  @spec current_sender(Phoenix.LiveView.Socket.t()) :: String.t() | nil
  def current_sender(socket) do
    case socket.assigns[:current_account] do
      %{address: address} when is_binary(address) -> address
      _other -> nil
    end
  end

  @doc "Returns tribe id derived from active character, then account fallback."
  @spec current_tribe_id(Phoenix.LiveView.Socket.t()) :: integer() | nil
  def current_tribe_id(socket) do
    case socket.assigns[:active_character] do
      %{tribe_id: tribe_id} when is_integer(tribe_id) and tribe_id > 0 -> tribe_id
      _other -> account_tribe_id(socket.assigns[:current_account])
    end
  end

  @doc "Loads solar systems from static data when available."
  @spec load_solar_systems(pid() | nil) :: [map()]
  def load_solar_systems(pid) when is_pid(pid), do: StaticData.list_solar_systems(pid)
  def load_solar_systems(_pid), do: []

  defp load_reputation_cache(active_listings, socket, opts) do
    base_cache = socket.assigns[:reputation_cache] || %{}

    active_listings
    |> Enum.map(& &1.seller_address)
    |> Enum.uniq()
    |> Enum.reduce(base_cache, fn seller_address, cache ->
      case IntelMarket.get_reputation(seller_address, opts) do
        {:ok, reputation} -> Map.put(cache, seller_address, reputation)
        {:error, _reason} -> cache
      end
    end)
  end

  defp load_feedback_recorded(purchased_listings, socket, opts) do
    listing_ids = Enum.map(purchased_listings, & &1.id)
    session_flags = Map.take(socket.assigns[:feedback_recorded] || %{}, listing_ids)

    Enum.reduce(purchased_listings, session_flags, fn listing, feedback_flags ->
      on_chain_recorded = IntelMarket.feedback_recorded?(listing.seller_address, listing.id, opts)
      already_recorded? = Map.get(feedback_flags, listing.id, false)

      Map.put(feedback_flags, listing.id, already_recorded? or on_chain_recorded)
    end)
  end

  defp seller_addresses(socket) do
    addresses =
      [socket.assigns.sender | Enum.map(socket.assigns.pseudonyms, & &1.pseudonym_address)]
      |> Enum.filter(&is_binary/1)
      |> Enum.uniq()

    case addresses do
      [] -> [socket.assigns.sender || ""]
      _non_empty_addresses -> addresses
    end
  end

  defp ensure_entry_mode(socket, reports) do
    entry_mode = if reports == [], do: "manual", else: socket.assigns.entry_mode

    params = Map.put(socket.assigns.form.params || %{}, "entry_mode", entry_mode)

    socket
    |> assign(:entry_mode, entry_mode)
    |> State.assign_listing_form(params)
  end

  defp account_tribe_id(%{tribe_id: tribe_id}) when is_integer(tribe_id) and tribe_id > 0,
    do: tribe_id

  defp account_tribe_id(_account), do: nil

  defp choose_active_pseudonym(socket, pseudonyms) do
    requested = socket.assigns.pending_active_pseudonym || socket.assigns.active_pseudonym

    case Enum.find(pseudonyms, &(&1.pseudonym_address == requested)) do
      %{pseudonym_address: pseudonym_address} -> pseudonym_address
      nil -> first_pseudonym_address(pseudonyms)
    end
  end

  defp loaded_pseudonyms(pseudonyms, addresses) do
    Enum.filter(pseudonyms, &(&1.pseudonym_address in addresses))
  end

  defp loaded_active_pseudonym(pseudonyms, active_address) do
    case Enum.find(pseudonyms, &(&1.pseudonym_address == active_address)) do
      %{pseudonym_address: pseudonym_address} -> pseudonym_address
      nil -> first_pseudonym_address(pseudonyms)
    end
  end

  defp first_pseudonym_address([%{pseudonym_address: pseudonym_address} | _rest]),
    do: pseudonym_address

  defp first_pseudonym_address([]), do: nil

  defp maybe_push_pseudonyms(socket) do
    if Phoenix.LiveView.connected?(socket), do: State.push_pseudonyms(socket), else: socket
  end
end
