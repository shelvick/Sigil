defmodule SigilWeb.IntelMarketLive.State do
  @moduledoc """
  Shared state, form, and filtering helpers for the intel marketplace LiveView.
  """

  import Phoenix.Component, only: [assign: 2, assign: 3, to_form: 2]
  import Phoenix.LiveView, only: [push_event: 3]

  alias Sigil.{Diplomacy, Intel, IntelMarket}
  alias Sigil.Sui.Types.Character
  alias SigilWeb.IntelMarketLive.State.{Filtering, MarketData}

  @doc """
  Assigns the baseline marketplace state for the current socket.
  """
  @spec assign_base_state(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def assign_base_state(socket) do
    sender = MarketData.current_sender(socket)
    tribe_id = MarketData.current_tribe_id(socket)

    can_sell =
      is_binary(sender) and is_integer(tribe_id) and
        match?(%Character{}, socket.assigns[:active_character])

    socket
    |> assign(
      page_title: "Intel Marketplace",
      authenticated?: is_binary(sender),
      sender: sender,
      tribe_id: tribe_id,
      can_sell: can_sell,
      page_section: :browsing,
      page_state: :ready,
      marketplace_available?: false,
      marketplace_info: nil,
      listings: [],
      filtered_listings: [],
      my_listings: [],
      purchased_listings: [],
      my_reports: [],
      filters: Filtering.default_filters(),
      entry_mode: "existing",
      pending_listing: nil,
      pending_tx: nil,
      pending_decrypt_listing_id: nil,
      seal_status: nil,
      seal_error_message: nil,
      pseudonyms: [],
      active_pseudonym: nil,
      pending_active_pseudonym: nil,
      pending_delete_pseudonym: nil,
      pseudonym_error_message: nil,
      pseudonym_delete_warning: nil,
      decrypted_intel: %{},
      reputation_cache: %{},
      feedback_recorded: %{},
      static_data_pid: socket.assigns[:static_data],
      solar_systems: MarketData.load_solar_systems(socket.assigns[:static_data])
    )
    |> assign_listing_form(%{"entry_mode" => if(can_sell, do: "existing", else: "manual")})
  end

  @doc """
  Reloads marketplace listings and seller reports from persisted state.
  """
  @spec sync_and_load_data(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def sync_and_load_data(socket) do
    _ = IntelMarket.sync_listings(market_opts(socket))

    socket
    |> MarketData.load_pseudonyms()
    |> MarketData.load_listings()
    |> MarketData.load_reports()
    |> apply_filters(socket.assigns.filters)
  end

  @doc """
  Refreshes the rendered marketplace state without forcing a chain sync.
  """
  @spec refresh_marketplace(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def refresh_marketplace(socket) do
    socket
    |> MarketData.load_pseudonyms()
    |> MarketData.load_listings()
    |> MarketData.load_reports()
    |> apply_filters(socket.assigns.filters)
  end

  @doc """
  Applies the active browse filters to the current listing set.
  """
  @spec apply_filters(Phoenix.LiveView.Socket.t(), map()) :: Phoenix.LiveView.Socket.t()
  def apply_filters(socket, filters) do
    filtered =
      Enum.filter(
        socket.assigns.listings,
        &Filtering.matches_filters?(&1, filters, socket.assigns.static_data_pid)
      )

    assign(socket, filters: filters, filtered_listings: filtered)
  end

  @doc """
  Normalizes listing form params and stores them as a Phoenix form.
  """
  @spec assign_listing_form(Phoenix.LiveView.Socket.t(), map()) :: Phoenix.LiveView.Socket.t()
  def assign_listing_form(socket, params) do
    params =
      params
      |> Map.put_new("entry_mode", socket.assigns.entry_mode)
      |> Filtering.maybe_fill_from_report(socket)
      |> Filtering.maybe_fill_solar_system_id(socket.assigns.static_data_pid)

    socket
    |> assign(entry_mode: Map.get(params, "entry_mode", socket.assigns.entry_mode))
    |> assign(:form, to_form(params, as: :listing))
  end

  @doc """
  Returns the context options used for intel operations.
  """
  @spec intel_opts(Phoenix.LiveView.Socket.t()) :: Intel.options()
  def intel_opts(socket) do
    [
      tables: socket.assigns.cache_tables,
      pubsub: socket.assigns.pubsub,
      authorized_tribe_id: socket.assigns.tribe_id
    ]
  end

  @doc """
  Pushes the current pseudonym cache payload to the browser hook.
  """
  @spec push_pseudonyms(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def push_pseudonyms(socket) do
    encrypted_keys =
      Enum.map(socket.assigns.pseudonyms, fn pseudonym ->
        %{
          "address" => pseudonym.pseudonym_address,
          "encrypted_key" => Base.encode64(pseudonym.encrypted_private_key)
        }
      end)

    push_event(socket, "load_pseudonyms", %{
      "encrypted_keys" => encrypted_keys,
      "active_address" => socket.assigns.active_pseudonym
    })
  end

  @doc """
  Reloads persisted pseudonyms without asking the browser hook to decrypt again.
  """
  @spec reload_pseudonyms(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def reload_pseudonyms(socket), do: MarketData.reload_pseudonyms(socket)

  @doc """
  Reconciles LiveView state with the pseudonyms the browser hook actually loaded.
  """
  @spec sync_loaded_pseudonyms(Phoenix.LiveView.Socket.t(), [String.t()], String.t() | nil) ::
          Phoenix.LiveView.Socket.t()
  def sync_loaded_pseudonyms(socket, addresses, active_address),
    do: MarketData.sync_loaded_pseudonyms(socket, addresses, active_address)

  @doc """
  Returns the context options used for marketplace operations.
  """
  @spec market_opts(Phoenix.LiveView.Socket.t()) :: IntelMarket.options()
  def market_opts(socket) do
    [
      tables: socket.assigns.cache_tables,
      pubsub: socket.assigns.pubsub,
      sender: socket.assigns.sender,
      tribe_id: socket.assigns.tribe_id
    ]
    |> maybe_put_sigil_package_id(socket.assigns[:seal_package_id_override])
    |> maybe_put_walrus_client(socket.assigns[:walrus_client_override])
    |> maybe_put_reputation_registry_id(socket.assigns[:reputation_registry_id_override])
  end

  @doc """
  Marks buyer feedback as recorded for a listing in the current LiveView session.
  """
  @spec mark_feedback_recorded(Phoenix.LiveView.Socket.t(), String.t()) ::
          Phoenix.LiveView.Socket.t()
  def mark_feedback_recorded(socket, listing_id) when is_binary(listing_id) do
    assign(
      socket,
      :feedback_recorded,
      Map.put(socket.assigns.feedback_recorded || %{}, listing_id, true)
    )
  end

  @doc """
  Returns the context options used for diplomacy lookups.
  """
  @spec diplomacy_opts(Phoenix.LiveView.Socket.t()) :: Diplomacy.options()
  def diplomacy_opts(socket) do
    [
      tables: socket.assigns.cache_tables,
      sender: socket.assigns.sender,
      tribe_id: socket.assigns.tribe_id,
      pubsub: socket.assigns.pubsub
    ]
  end

  @doc """
  Parses a SUI-denominated price string into mist.
  """
  @spec parse_price_sui(String.t() | nil) :: {:ok, integer()} | :error
  def parse_price_sui(nil), do: :error

  @doc false
  def parse_price_sui(value) when is_binary(value) do
    case Decimal.parse(value) do
      {%Decimal{} = decimal, ""} ->
        amount =
          decimal |> Decimal.mult(1_000_000_000) |> Decimal.round(0) |> Decimal.to_integer()

        if amount > 0, do: {:ok, amount}, else: :error

      _other ->
        :error
    end
  end

  @doc """
  Returns a display-ready active character name.
  """
  @spec active_character_name(Character.t() | nil) :: String.t() | nil
  def active_character_name(%{metadata: %{name: name}}) when is_binary(name), do: name
  @doc false
  def active_character_name(_character), do: nil

  @doc """
  Humanizes Seal workflow status messages for the UI.
  """
  @spec humanize_seal_status(String.t()) :: String.t()
  def humanize_seal_status("encrypting"), do: "encrypting"
  @doc false
  def humanize_seal_status("uploading"), do: "uploading"
  @doc false
  def humanize_seal_status("fetching"), do: "fetching"
  @doc false
  def humanize_seal_status("decrypting"), do: "decrypting"
  @doc false
  def humanize_seal_status(status), do: status

  @doc """
  Formats a changeset into a single user-facing error string.
  """
  @spec changeset_error(Ecto.Changeset.t()) :: String.t()
  def changeset_error(changeset) do
    Enum.map_join(changeset.errors, ", ", fn {field, {message, _opts}} ->
      "#{Phoenix.Naming.humanize(field)} #{message}"
    end)
  end

  @doc """
  Maps intel report types onto the marketplace enum values.
  """
  @spec report_type_value(Sigil.Intel.IntelReport.report_type()) :: 1 | 2
  def report_type_value(:scouting), do: 2
  @doc false
  def report_type_value(_type), do: 1

  @doc """
  Resolves a blank string to nil.
  """
  @spec blank_to_nil(String.t() | nil) :: String.t() | nil
  def blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  @doc false
  def blank_to_nil(_value), do: nil

  defp maybe_put_sigil_package_id(opts, sigil_package_id) when is_binary(sigil_package_id) do
    Keyword.put(opts, :sigil_package_id, sigil_package_id)
  end

  defp maybe_put_sigil_package_id(opts, _sigil_package_id), do: opts

  defp maybe_put_walrus_client(opts, walrus_client) when is_atom(walrus_client) do
    Keyword.put(opts, :walrus_client, walrus_client)
  end

  defp maybe_put_walrus_client(opts, _walrus_client), do: opts

  defp maybe_put_reputation_registry_id(opts, reputation_registry_id)
       when is_binary(reputation_registry_id) do
    Keyword.put(opts, :reputation_registry_id, reputation_registry_id)
  end

  defp maybe_put_reputation_registry_id(opts, _reputation_registry_id), do: opts
end
