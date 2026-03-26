defmodule SigilWeb.IntelMarketLive.SellForm do
  @moduledoc """
  Renders the marketplace sell form and its local display helpers.
  """

  use SigilWeb, :html

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
          <h2 class="mt-3 text-2xl font-semibold text-cream">Seal-encrypted listing</h2>
        </div>
        <span :if={@seal_status} class="rounded-full border border-quantum-400/40 bg-quantum-400/10 px-3 py-1 font-mono text-xs uppercase tracking-[0.2em] text-quantum-300">
          <%= @seal_status %>
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
                placeholder="Optional — leave blank to keep private"
                class="w-full rounded-2xl border border-space-600/80 bg-space-950/70 px-4 py-3 text-sm text-cream outline-none transition placeholder:text-space-600 focus:border-quantum-400"
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
              placeholder="Optional — leave blank if not applicable"
              class="w-full rounded-2xl border border-space-600/80 bg-space-950/70 px-4 py-3 text-sm text-cream outline-none transition placeholder:text-space-600 focus:border-quantum-400"
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

  @spec report_option_label(map()) :: String.t()
  defp report_option_label(report) do
    [report.label || "Untitled report", report.assembly_id]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  @spec selected_report?(map(), String.t()) :: boolean()
  defp selected_report?(params, report_id), do: params["report_id"] == report_id

  @spec entry_mode_classes(boolean()) :: String.t()
  defp entry_mode_classes(true) do
    "rounded-full border border-quantum-300 bg-quantum-400/10 px-4 py-2 font-mono text-xs uppercase tracking-[0.24em] text-cream"
  end

  defp entry_mode_classes(false) do
    "rounded-full border border-space-600/80 bg-space-800/70 px-4 py-2 font-mono text-xs uppercase tracking-[0.24em] text-space-500 transition hover:border-quantum-400 hover:text-cream"
  end
end
