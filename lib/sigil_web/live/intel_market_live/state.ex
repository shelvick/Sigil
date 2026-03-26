defmodule SigilWeb.IntelMarketLive.State do
  @moduledoc """
  Shared state, form, and filtering helpers for the intel marketplace LiveView.
  """

  import Phoenix.Component, only: [assign: 2, assign: 3, to_form: 2]

  alias Sigil.{Diplomacy, Intel, IntelMarket, StaticData}
  alias Sigil.Intel.IntelReport
  alias Sigil.Sui.Types.Character

  @doc """
  Assigns the baseline marketplace state for the current socket.
  """
  @spec assign_base_state(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def assign_base_state(socket) do
    sender = current_sender(socket)
    tribe_id = current_tribe_id(socket)

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
      filters: default_filters(),
      entry_mode: "existing",
      pending_listing: nil,
      pending_tx: nil,
      pending_decrypt_listing_id: nil,
      seal_status: nil,
      seal_error_message: nil,
      decrypted_intel: %{},
      static_data_pid: socket.assigns[:static_data],
      solar_systems: load_solar_systems(socket.assigns[:static_data])
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
    |> load_listings()
    |> load_reports()
    |> apply_filters(socket.assigns.filters)
  end

  @doc """
  Refreshes the rendered marketplace state without forcing a chain sync.
  """
  @spec refresh_marketplace(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def refresh_marketplace(socket) do
    socket
    |> load_listings()
    |> load_reports()
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
        &matches_filters?(&1, filters, socket.assigns.static_data_pid)
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
      |> maybe_fill_from_report(socket)
      |> maybe_fill_solar_system_id(socket.assigns.static_data_pid)

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
  @spec report_type_value(IntelReport.report_type()) :: 1 | 2
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

  defp load_listings(socket) do
    active_listings = IntelMarket.list_listings(market_opts(socket))

    assign(socket,
      listings: active_listings,
      my_listings:
        IntelMarket.list_seller_listings(socket.assigns.sender || "", market_opts(socket)),
      purchased_listings:
        IntelMarket.list_purchased_listings(socket.assigns.sender || "", market_opts(socket))
    )
  end

  defp load_reports(%{assigns: %{can_sell: false}} = socket) do
    socket
    |> assign(my_reports: [])
    |> assign_listing_form(%{"entry_mode" => "manual"})
  end

  defp load_reports(socket) do
    reports =
      socket.assigns.tribe_id
      |> Intel.list_intel(intel_opts(socket))
      |> Enum.filter(&(&1.reported_by == socket.assigns.sender))

    socket
    |> assign(my_reports: reports)
    |> ensure_entry_mode(reports)
  end

  defp ensure_entry_mode(socket, reports) do
    entry_mode = if reports == [], do: "manual", else: socket.assigns.entry_mode

    params = Map.put(socket.assigns.form.params || %{}, "entry_mode", entry_mode)

    socket
    |> assign(:entry_mode, entry_mode)
    |> assign_listing_form(params)
  end

  defp matches_filters?(listing, filters, static_data_pid) do
    matches_report_type?(listing, filters["report_type"]) and
      matches_solar_system?(listing, filters["solar_system_name"], static_data_pid) and
      matches_price?(listing, filters["price_min_sui"], :min) and
      matches_price?(listing, filters["price_max_sui"], :max)
  end

  defp matches_report_type?(_listing, value) when value in [nil, ""], do: true

  defp matches_report_type?(listing, value) do
    Integer.to_string(listing.report_type) == value
  end

  defp matches_solar_system?(_listing, value, _static_data_pid) when value in [nil, ""], do: true

  defp matches_solar_system?(listing, value, static_data_pid) when is_pid(static_data_pid) do
    case StaticData.get_solar_system_by_name(static_data_pid, value) do
      %{id: id} -> listing.solar_system_id == id
      _other -> false
    end
  end

  defp matches_solar_system?(_listing, _value, _static_data_pid), do: false

  defp matches_price?(_listing, value, _kind) when value in [nil, ""], do: true

  defp matches_price?(listing, value, :min) do
    case parse_price_sui(value) do
      {:ok, amount} -> listing.price_mist >= amount
      :error -> true
    end
  end

  defp matches_price?(listing, value, :max) do
    case parse_price_sui(value) do
      {:ok, amount} -> listing.price_mist <= amount
      :error -> true
    end
  end

  defp maybe_fill_from_report(
         %{"entry_mode" => "existing", "report_id" => report_id} = params,
         socket
       )
       when is_binary(report_id) and report_id != "" do
    case Enum.find(socket.assigns.my_reports, &(&1.id == report_id)) do
      %IntelReport{} = report ->
        params
        |> Map.put("report_type", Integer.to_string(report_type_value(report.report_type)))
        |> Map.put("assembly_id", report.assembly_id || "")
        |> Map.put("notes", report.notes || "")
        |> Map.put("solar_system_id", Integer.to_string(report.solar_system_id || 0))
        |> Map.put(
          "solar_system_name",
          solar_system_name(socket.assigns.static_data_pid, report.solar_system_id)
        )

      nil ->
        params
    end
  end

  defp maybe_fill_from_report(params, _socket), do: params

  defp maybe_fill_solar_system_id(%{"solar_system_name" => name} = params, static_data_pid)
       when is_pid(static_data_pid) and is_binary(name) and name != "" do
    case StaticData.get_solar_system_by_name(static_data_pid, name) do
      %{id: id} -> Map.put(params, "solar_system_id", Integer.to_string(id))
      _other -> params
    end
  end

  defp maybe_fill_solar_system_id(params, _static_data_pid), do: params

  defp current_sender(socket) do
    case socket.assigns[:current_account] do
      %{address: address} when is_binary(address) -> address
      _other -> nil
    end
  end

  defp current_tribe_id(socket) do
    case socket.assigns[:active_character] do
      %{tribe_id: tribe_id} when is_integer(tribe_id) and tribe_id > 0 -> tribe_id
      _other -> account_tribe_id(socket.assigns[:current_account])
    end
  end

  defp account_tribe_id(%{tribe_id: tribe_id}) when is_integer(tribe_id) and tribe_id > 0,
    do: tribe_id

  defp account_tribe_id(_account), do: nil

  defp load_solar_systems(pid) when is_pid(pid), do: StaticData.list_solar_systems(pid)
  defp load_solar_systems(_pid), do: []

  defp solar_system_name(pid, solar_system_id) when is_pid(pid) and is_integer(solar_system_id) do
    case StaticData.get_solar_system(pid, solar_system_id) do
      %{name: name} -> name
      _other -> ""
    end
  end

  defp solar_system_name(_pid, _solar_system_id), do: ""

  defp default_filters do
    %{
      "report_type" => "",
      "solar_system_name" => "",
      "price_min_sui" => "",
      "price_max_sui" => ""
    }
  end
end
