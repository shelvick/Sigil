defmodule SigilWeb.IntelMarketLive.Components do
  @moduledoc """
  Template components for the intel marketplace LiveView.
  """

  use SigilWeb, :html

  import SigilWeb.AssemblyHelpers, only: [truncate_id: 1]

  alias Sigil.Intel.IntelListing
  alias Sigil.StaticData

  @doc """
  Renders the marketplace filter bar.
  """
  @spec filter_bar(map()) :: Phoenix.LiveView.Rendered.t()
  def filter_bar(assigns) do
    ~H"""
    <.form id="marketplace-filters" for={to_form(@filters, as: :filters)} phx-change="filter_listings" class="grid gap-4 rounded-[2rem] border border-space-600/80 bg-space-900/70 p-6 shadow-2xl shadow-black/30 backdrop-blur md:grid-cols-4">
      <label class="space-y-2">
        <span class="font-mono text-xs uppercase tracking-[0.24em] text-space-500">Report Type</span>
        <select
          name="filters[report_type]"
          class="w-full rounded-2xl border border-space-600/80 bg-space-950/70 px-4 py-3 text-sm text-cream outline-none transition focus:border-quantum-400"
        >
          <option value="">All reports</option>
          <option value="1" selected={@filters["report_type"] == "1"}>Location</option>
          <option value="2" selected={@filters["report_type"] == "2"}>Scouting</option>
        </select>
      </label>

      <label class="space-y-2">
        <span class="font-mono text-xs uppercase tracking-[0.24em] text-space-500">Solar System</span>
        <input
          type="text"
          name="filters[solar_system_name]"
          value={@filters["solar_system_name"] || ""}
          list="marketplace-solar-systems"
          class="w-full rounded-2xl border border-space-600/80 bg-space-950/70 px-4 py-3 text-sm text-cream outline-none transition focus:border-quantum-400"
        />
      </label>

      <label class="space-y-2">
        <span class="font-mono text-xs uppercase tracking-[0.24em] text-space-500">Min Price (SUI)</span>
        <input
          type="text"
          name="filters[price_min_sui]"
          value={@filters["price_min_sui"] || ""}
          class="w-full rounded-2xl border border-space-600/80 bg-space-950/70 px-4 py-3 text-sm text-cream outline-none transition focus:border-quantum-400"
        />
      </label>

      <label class="space-y-2">
        <span class="font-mono text-xs uppercase tracking-[0.24em] text-space-500">Max Price (SUI)</span>
        <input
          type="text"
          name="filters[price_max_sui]"
          value={@filters["price_max_sui"] || ""}
          class="w-full rounded-2xl border border-space-600/80 bg-space-950/70 px-4 py-3 text-sm text-cream outline-none transition focus:border-quantum-400"
        />
      </label>

      <datalist id="marketplace-solar-systems">
        <option :for={system <- @solar_systems} value={system.name}></option>
      </datalist>
    </.form>
    """
  end

  @doc """
  Renders the sell-intel form.
  """
  @spec sell_form(map()) :: Phoenix.LiveView.Rendered.t()
  def sell_form(assigns) do
    ~H"""
    <div class="rounded-[2rem] border border-space-600/80 bg-space-900/70 p-8 shadow-2xl shadow-black/30 backdrop-blur">
      <div class="flex items-start justify-between gap-4">
        <div>
          <p class="font-mono text-xs uppercase tracking-[0.3em] text-quantum-300">Sell Intel</p>
          <h2 class="mt-3 text-2xl font-semibold text-cream">Proof-backed listing</h2>
        </div>
        <span :if={@proof_status} class="rounded-full border border-quantum-400/40 bg-quantum-400/10 px-3 py-1 font-mono text-xs uppercase tracking-[0.2em] text-quantum-300">
          <%= @proof_status %>
        </span>
      </div>

      <%= if @can_sell do %>
        <.form id="sell-intel-form" for={@form} phx-change="validate_listing" phx-submit="submit_listing" class="mt-6 space-y-5">
          <div class="flex flex-wrap gap-3">
            <label class={entry_mode_classes(@entry_mode == "existing")}>
              <input type="radio" name="listing[entry_mode]" value="existing" checked={@entry_mode == "existing"} class="sr-only" />
              Select existing report
            </label>
            <label class={entry_mode_classes(@entry_mode == "manual")}>
              <input type="radio" name="listing[entry_mode]" value="manual" checked={@entry_mode == "manual"} class="sr-only" />
              Enter fresh data
            </label>
          </div>

          <%= if @entry_mode == "existing" do %>
            <label class="block space-y-2">
              <span class="font-mono text-xs uppercase tracking-[0.24em] text-space-500">Existing Intel</span>
              <select
                name="listing[report_id]"
                class="w-full rounded-2xl border border-space-600/80 bg-space-950/70 px-4 py-3 text-sm text-cream outline-none transition focus:border-quantum-400"
              >
                <option value="">Select a report</option>
                <option :for={report <- @my_reports} value={report.id} selected={selected_report?(@form.params, report.id)}>
                  <%= report_option_label(report) %>
                </option>
              </select>
            </label>
          <% end %>

          <div class="grid gap-5 md:grid-cols-2">
            <label class="block space-y-2">
              <span class="font-mono text-xs uppercase tracking-[0.24em] text-space-500">Report Type</span>
              <select
                name="listing[report_type]"
                class="w-full rounded-2xl border border-space-600/80 bg-space-950/70 px-4 py-3 text-sm text-cream outline-none transition focus:border-quantum-400"
              >
                <option value="1" selected={@form.params["report_type"] in [nil, "", "1"]}>Location</option>
                <option value="2" selected={@form.params["report_type"] == "2"}>Scouting</option>
              </select>
            </label>

            <label class="block space-y-2">
              <span class="font-mono text-xs uppercase tracking-[0.24em] text-space-500">Solar System</span>
              <input
                type="text"
                name="listing[solar_system_name]"
                list="seller-solar-systems"
                value={@form.params["solar_system_name"] || ""}
                class="w-full rounded-2xl border border-space-600/80 bg-space-950/70 px-4 py-3 text-sm text-cream outline-none transition focus:border-quantum-400"
              />
            </label>
          </div>

          <%= if solar_system_id = @form.params["solar_system_id"] do %>
            <p class="font-mono text-xs uppercase tracking-[0.2em] text-space-500">
              Canonical solar system ID: <%= solar_system_id %>
            </p>
          <% end %>

          <label class="block space-y-2">
            <span class="font-mono text-xs uppercase tracking-[0.24em] text-space-500">Assembly ID</span>
            <input
              type="text"
              name="listing[assembly_id]"
              value={@form.params["assembly_id"] || ""}
              class="w-full rounded-2xl border border-space-600/80 bg-space-950/70 px-4 py-3 text-sm text-cream outline-none transition focus:border-quantum-400"
            />
          </label>

          <label class="block space-y-2">
            <span class="font-mono text-xs uppercase tracking-[0.24em] text-space-500">Notes</span>
            <textarea
              name="listing[notes]"
              rows="4"
              class="w-full rounded-2xl border border-space-600/80 bg-space-950/70 px-4 py-3 text-sm text-cream outline-none transition focus:border-quantum-400"
            ><%= @form.params["notes"] || "" %></textarea>
          </label>

          <div class="grid gap-5 md:grid-cols-2">
            <label class="block space-y-2">
              <span class="font-mono text-xs uppercase tracking-[0.24em] text-space-500">Price (SUI)</span>
              <input
                type="text"
                name="listing[price_sui]"
                value={@form.params["price_sui"] || ""}
                class="w-full rounded-2xl border border-space-600/80 bg-space-950/70 px-4 py-3 text-sm text-cream outline-none transition focus:border-quantum-400"
              />
            </label>

            <label class="block space-y-2">
              <span class="font-mono text-xs uppercase tracking-[0.24em] text-space-500">Description</span>
              <input
                type="text"
                name="listing[description]"
                value={@form.params["description"] || ""}
                class="w-full rounded-2xl border border-space-600/80 bg-space-950/70 px-4 py-3 text-sm text-cream outline-none transition focus:border-quantum-400"
              />
            </label>
          </div>

          <label :if={@tribe_id} class="flex items-center gap-3 rounded-2xl border border-space-600/80 bg-space-950/50 px-4 py-3 text-sm text-cream">
            <input type="hidden" name="listing[restricted]" value="false" />
            <input type="checkbox" name="listing[restricted]" value="true" checked={@form.params["restricted"] == "true"} class="h-4 w-4 rounded border-space-600 bg-space-900 text-quantum-400 focus:ring-quantum-400" />
            Restrict to your tribe
          </label>

          <datalist id="seller-solar-systems">
            <option :for={system <- @solar_systems} value={system.name}></option>
          </datalist>

          <button
            type="submit"
            class="inline-flex rounded-full bg-quantum-400 px-5 py-3 font-mono text-xs uppercase tracking-[0.25em] text-space-950 transition hover:bg-quantum-300"
          >
            Create Listing
          </button>
        </.form>
      <% else %>
        <div class="mt-6 rounded-2xl border border-warning/40 bg-warning/10 p-4 text-sm leading-6 text-warning">
          creating listings requires a tribe-backed intel record
        </div>
      <% end %>
    </div>
    """
  end

  @doc """
  Renders a marketplace listing card.
  """
  @spec listing_card(map()) :: Phoenix.LiveView.Rendered.t()
  def listing_card(assigns) do
    assigns =
      assign(
        assigns,
        :purchase_action,
        purchase_action(assigns.listing, assigns.sender, assigns[:tribe_id])
      )

    ~H"""
    <article class="rounded-[2rem] border border-space-600/80 bg-space-900/70 p-6 shadow-xl shadow-black/20 backdrop-blur">
      <div class="flex flex-wrap items-start justify-between gap-4">
        <div class="space-y-3">
          <div class="flex flex-wrap items-center gap-2">
            <span class={report_type_badge_classes(@listing.report_type)}><%= report_type_label(@listing.report_type) %></span>
            <span :if={@listing.restricted_to_tribe_id} class="rounded-full border border-warning/40 bg-warning/10 px-3 py-1 font-mono text-xs uppercase tracking-[0.2em] text-warning">
              restricted
            </span>
            <span class="rounded-full border border-space-600/80 bg-space-950/60 px-3 py-1 font-mono text-xs uppercase tracking-[0.2em] text-space-500">
              <%= status_label(@listing.status) %>
            </span>
          </div>

          <h3 :if={present?(@listing.description)} class="text-xl font-semibold text-cream"><%= @listing.description %></h3>

          <p class="font-mono text-xs uppercase tracking-[0.2em] text-space-500">
            <%= system_name(@static_data, @listing.solar_system_id) %>
          </p>

          <p class="text-sm leading-6 text-space-500">
            Preview metadata is seller-declared; the on-chain commitment is the settlement anchor.
          </p>

          <div class="flex flex-wrap items-center gap-3 text-xs text-space-500">
            <span>Seller <%= truncate_id(@listing.seller_address) %></span>
            <span :if={@listing.buyer_address}>Buyer <%= truncate_id(@listing.buyer_address) %></span>
          </div>
        </div>

        <div class="space-y-3 text-right">
          <p class="font-mono text-sm uppercase tracking-[0.24em] text-quantum-300"><%= price_label(@listing.price_mist) %></p>
          <button
            :if={@purchase_action.visible?}
            type="button"
            phx-click={if @purchase_action.enabled?, do: "purchase_listing", else: nil}
            phx-value-listing_id={if @purchase_action.enabled?, do: @listing.id, else: nil}
            disabled={!@purchase_action.enabled?}
            title={@purchase_action.reason}
            aria-disabled={to_string(!@purchase_action.enabled?)}
            class={purchase_button_classes(@purchase_action.enabled?)}
          >
            Purchase
          </button>
        </div>
      </div>
    </article>
    """
  end

  @doc """
  Renders the user's listing panel.
  """
  @spec my_listings_panel(map()) :: Phoenix.LiveView.Rendered.t()
  def my_listings_panel(assigns) do
    ~H"""
    <div class="space-y-4 rounded-[2rem] border border-space-600/80 bg-space-900/70 p-8 shadow-2xl shadow-black/30 backdrop-blur">
      <div class="flex items-center justify-between gap-4">
        <div>
          <p class="font-mono text-xs uppercase tracking-[0.3em] text-quantum-300">My Listings</p>
          <h2 class="mt-3 text-2xl font-semibold text-cream">Operator inventory</h2>
        </div>
        <span class="rounded-full border border-space-600/80 bg-space-950/60 px-3 py-1 font-mono text-xs uppercase tracking-[0.2em] text-space-500">
          <%= length(@listings) %> total
        </span>
      </div>

      <%= if @listings == [] do %>
        <p class="text-sm text-space-500">No listings created yet.</p>
      <% else %>
        <div class="space-y-4">
          <article :for={listing <- @listings} class="rounded-2xl border border-space-600/80 bg-space-950/60 p-5">
            <div class="flex flex-wrap items-start justify-between gap-4">
              <div class="space-y-2">
                <p class="font-mono text-xs uppercase tracking-[0.2em] text-space-500"><%= listing.id %></p>
                <p class="text-lg font-semibold text-cream"><%= listing.description || "Untitled listing" %></p>
                <div class="flex flex-wrap items-center gap-3 text-xs text-space-500">
                  <span><%= system_name(@static_data, listing.solar_system_id) %></span>
                  <span><%= price_label(listing.price_mist) %></span>
                  <span><%= status_label(listing.status) %></span>
                </div>
              </div>

              <button
                :if={listing.status == :active}
                type="button"
                phx-click="cancel_listing"
                phx-value-listing_id={listing.id}
                class="inline-flex rounded-full border border-warning/40 px-4 py-2 font-mono text-xs uppercase tracking-[0.22em] text-warning transition hover:border-warning hover:text-cream"
              >
                Cancel
              </button>
            </div>
          </article>
        </div>
      <% end %>
    </div>
    """
  end

  @doc """
  Renders the proof generation state.
  """
  @spec proof_status(map()) :: Phoenix.LiveView.Rendered.t()
  def proof_status(assigns) do
    ~H"""
    <div :if={@status} class="rounded-2xl border border-quantum-400/40 bg-quantum-400/10 p-4 text-sm text-quantum-300">
      <%= @status %>
    </div>
    """
  end

  @doc """
  Renders a listing status badge.
  """
  @spec listing_status_badge(map()) :: Phoenix.LiveView.Rendered.t()
  def listing_status_badge(assigns) do
    ~H"""
    <span class="rounded-full border border-space-600/80 bg-space-950/60 px-3 py-1 font-mono text-xs uppercase tracking-[0.2em] text-space-500">
      <%= status_label(@status) %>
    </span>
    """
  end

  @spec report_option_label(map()) :: String.t()
  defp report_option_label(report) do
    [report.label || "Untitled report", report.assembly_id]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  @spec selected_report?(map(), String.t()) :: boolean()
  defp selected_report?(params, report_id), do: params["report_id"] == report_id

  @spec report_type_label(integer() | nil) :: String.t()
  defp report_type_label(2), do: "Scouting"
  defp report_type_label(_value), do: "Location"

  @spec report_type_badge_classes(integer() | nil) :: String.t()
  defp report_type_badge_classes(2) do
    "rounded-full border border-success/40 bg-success/10 px-3 py-1 font-mono text-xs uppercase tracking-[0.2em] text-success"
  end

  defp report_type_badge_classes(_value) do
    "rounded-full border border-quantum-400/40 bg-quantum-400/10 px-3 py-1 font-mono text-xs uppercase tracking-[0.2em] text-quantum-300"
  end

  @spec entry_mode_classes(boolean()) :: String.t()
  defp entry_mode_classes(true) do
    "rounded-full border border-quantum-300 bg-quantum-400/10 px-4 py-2 font-mono text-xs uppercase tracking-[0.24em] text-cream"
  end

  defp entry_mode_classes(false) do
    "rounded-full border border-space-600/80 bg-space-800/70 px-4 py-2 font-mono text-xs uppercase tracking-[0.24em] text-space-500 transition hover:border-quantum-400 hover:text-cream"
  end

  @spec system_name(pid() | nil, integer() | nil) :: String.t()
  defp system_name(static_data, solar_system_id)
       when is_pid(static_data) and is_integer(solar_system_id) do
    case StaticData.get_solar_system(static_data, solar_system_id) do
      %{name: name} -> name
      _other -> Integer.to_string(solar_system_id)
    end
  end

  defp system_name(_static_data, solar_system_id) when is_integer(solar_system_id),
    do: Integer.to_string(solar_system_id)

  defp system_name(_static_data, _solar_system_id), do: "Unknown system"

  @spec price_label(integer() | nil) :: String.t()
  defp price_label(price_mist) when is_integer(price_mist) and price_mist >= 0 do
    sui = price_mist / 1_000_000_000

    formatted =
      sui
      |> :erlang.float_to_binary(decimals: 2)
      |> String.trim_trailing("0")
      |> String.trim_trailing(".")

    formatted <> " SUI"
  end

  defp price_label(_price_mist), do: "0 SUI"

  @spec status_label(IntelListing.listing_status() | nil) :: String.t()
  defp status_label(status) when status in [:active, :sold, :cancelled],
    do: Atom.to_string(status)

  defp status_label(_status), do: "active"

  @spec purchase_action(IntelListing.t(), String.t() | nil, integer() | nil) :: %{
          visible?: boolean(),
          enabled?: boolean(),
          reason: String.t() | nil
        }
  defp purchase_action(%IntelListing{status: status}, _sender, _tribe_id)
       when status in [:sold, :cancelled] do
    %{visible?: false, enabled?: false, reason: nil}
  end

  defp purchase_action(%IntelListing{seller_address: seller_address}, sender, _tribe_id)
       when seller_address == sender do
    %{visible?: false, enabled?: false, reason: nil}
  end

  defp purchase_action(%IntelListing{restricted_to_tribe_id: nil}, _sender, _tribe_id) do
    %{visible?: true, enabled?: true, reason: nil}
  end

  defp purchase_action(
         %IntelListing{restricted_to_tribe_id: restricted_tribe_id},
         _sender,
         tribe_id
       )
       when restricted_tribe_id == tribe_id do
    %{visible?: true, enabled?: true, reason: nil}
  end

  defp purchase_action(%IntelListing{}, _sender, _tribe_id) do
    %{visible?: true, enabled?: false, reason: "Restricted to another tribe"}
  end

  @spec purchase_button_classes(boolean()) :: String.t()
  defp purchase_button_classes(true) do
    "inline-flex rounded-full bg-quantum-400 px-4 py-2 font-mono text-xs uppercase tracking-[0.2em] text-space-950 transition hover:bg-quantum-300"
  end

  defp purchase_button_classes(false) do
    "inline-flex cursor-not-allowed rounded-full border border-space-600/80 bg-space-900/40 px-4 py-2 font-mono text-xs uppercase tracking-[0.2em] text-space-500 opacity-70"
  end

  @spec present?(String.t() | nil) :: boolean()
  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_value), do: false
end
