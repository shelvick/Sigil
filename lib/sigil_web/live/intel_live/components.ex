defmodule SigilWeb.IntelLive.Components do
  @moduledoc """
  Template components for the intel feed LiveView.
  """

  use SigilWeb, :html

  import SigilWeb.AssemblyHelpers, only: [truncate_id: 1]

  alias Sigil.Intel.IntelReport
  alias SigilWeb.IntelHelpers

  @doc """
  Renders the intel report entry panel.
  """
  @spec report_entry_panel(map()) :: Phoenix.LiveView.Rendered.t()
  def report_entry_panel(assigns) do
    ~H"""
    <div class="rounded-[2rem] border border-space-600/80 bg-space-900/70 p-8 shadow-2xl shadow-black/40 backdrop-blur">
      <div class="flex flex-wrap gap-3">
        <button
          type="button"
          phx-click="toggle_report_type"
          phx-value-report_type="location"
          class={toggle_button_classes(@report_type == :location)}
        >
          Location
        </button>
        <button
          type="button"
          phx-click="toggle_report_type"
          phx-value-report_type="scouting"
          class={toggle_button_classes(@report_type == :scouting)}
        >
          Scouting
        </button>
      </div>

      <%= if @active_character do %>
        <%= if @intel_available do %>
          <%= if @static_data_pid do %>
            <.form id="intel-report-form" for={@form} phx-change="validate" phx-submit="submit_report" class="mt-6 space-y-5">
              <label class="block space-y-2">
                <span class="font-mono text-xs uppercase tracking-[0.24em] text-space-500">Assembly ID</span>
                <input
                  type="text"
                  name="report[assembly_id]"
                  value={@form.params["assembly_id"] || ""}
                  class="w-full rounded-2xl border border-space-600/80 bg-space-950/70 px-4 py-3 text-sm text-cream outline-none transition focus:border-quantum-400"
                />
              </label>

              <label class="block space-y-2">
                <span class="font-mono text-xs uppercase tracking-[0.24em] text-space-500">Solar System</span>
                <input
                  type="text"
                  name="report[solar_system_name]"
                  list="solar-systems"
                  value={@form.params["solar_system_name"] || ""}
                  class="w-full rounded-2xl border border-space-600/80 bg-space-950/70 px-4 py-3 text-sm text-cream outline-none transition focus:border-quantum-400"
                />
              </label>

              <datalist id="solar-systems">
                <option :for={system <- @solar_systems} value={system.name}></option>
              </datalist>

              <label class="block space-y-2">
                <span class="font-mono text-xs uppercase tracking-[0.24em] text-space-500">Label</span>
                <input
                  type="text"
                  name="report[label]"
                  value={@form.params["label"] || ""}
                  class="w-full rounded-2xl border border-space-600/80 bg-space-950/70 px-4 py-3 text-sm text-cream outline-none transition focus:border-quantum-400"
                />
              </label>

              <label class="block space-y-2">
                <span class="font-mono text-xs uppercase tracking-[0.24em] text-space-500">Notes</span>
                <textarea
                  name="report[notes]"
                  rows="4"
                  class="w-full rounded-2xl border border-space-600/80 bg-space-950/70 px-4 py-3 text-sm text-cream outline-none transition focus:border-quantum-400"
                ><%= @form.params["notes"] || "" %></textarea>
              </label>

              <input type="hidden" name="report[report_type]" value={Atom.to_string(@report_type)} />

              <button
                type="submit"
                class="inline-flex rounded-full bg-quantum-400 px-5 py-3 font-mono text-xs uppercase tracking-[0.25em] text-space-950 transition hover:bg-quantum-300"
              >
                Submit report
              </button>
            </.form>
          <% else %>
            <div class="mt-6 rounded-2xl border border-warning/40 bg-warning/10 p-4 text-sm text-warning">
              Solar system data not available
            </div>
          <% end %>
        <% else %>
          <div class="mt-6 rounded-2xl border border-warning/40 bg-warning/10 p-4 text-sm text-warning">
            Intel storage not available
          </div>
        <% end %>
      <% else %>
        <div class="mt-6 rounded-2xl border border-space-600/80 bg-space-800/70 p-4 text-sm text-space-500">
          Select a character to submit reports
        </div>
      <% end %>
    </div>
    """
  end

  @doc """
  Renders the recent intel report feed.
  """
  @spec report_feed_panel(map()) :: Phoenix.LiveView.Rendered.t()
  def report_feed_panel(assigns) do
    ~H"""
    <div class="rounded-[2rem] border border-space-600/80 bg-space-900/70 p-8 shadow-2xl shadow-black/40 backdrop-blur">
      <div class="flex items-center justify-between gap-4">
        <div>
          <p class="font-mono text-xs uppercase tracking-[0.3em] text-quantum-300">Feed</p>
          <h2 class="mt-3 text-2xl font-semibold text-cream">Recent Reports</h2>
        </div>
        <span class="rounded-full border border-space-600/80 bg-space-900/70 px-3 py-1 font-mono text-xs uppercase tracking-[0.2em] text-space-500">
          <%= length(@reports) %> total
        </span>
      </div>

      <%= if @reports == [] do %>
        <p class="mt-6 text-sm text-space-500">No intel reports yet. Be the first to share!</p>
      <% else %>
        <div class="mt-6 space-y-4">
          <div
            :for={report <- @reports}
            class="rounded-2xl border border-space-600/80 bg-space-800/70 p-5"
          >
            <div class="flex flex-col gap-4 md:flex-row md:items-start md:justify-between">
              <div class="space-y-3">
                <div class="flex flex-wrap items-center gap-3">
                  <span class={report_type_badge_classes(report.report_type)}>
                    <%= report_type_label(report.report_type) %>
                  </span>
                  <p class="font-mono text-xs uppercase tracking-[0.2em] text-space-500">
                    <%= report_system_name(@system_names, report.solar_system_id) %>
                  </p>

                  <.link
                    :if={is_integer(report.solar_system_id) and report.solar_system_id > 0}
                    navigate={~p"/map?system_id=#{report.solar_system_id}"}
                    class="inline-flex rounded-full border border-quantum-400/40 bg-quantum-400/10 px-3 py-1 font-mono text-xs uppercase tracking-[0.2em] text-quantum-300 transition hover:border-quantum-300 hover:text-cream"
                  >
                    View on Map
                  </.link>
                </div>

                <%= if report.label do %>
                  <p class="text-lg font-semibold text-cream"><%= report.label %></p>
                <% end %>

                <%= if report.notes do %>
                  <p class="text-sm leading-6 text-foreground"><%= report.notes %></p>
                <% end %>

                <div class="flex flex-wrap items-center gap-3 text-xs text-space-500">
                  <span><%= report.reported_by_name || "Unknown scout" %></span>
                  <.link
                    :if={is_binary(report.assembly_id)}
                    navigate={~p"/assembly/#{report.assembly_id}"}
                    title={report.assembly_id}
                    class="font-mono text-quantum-300 transition hover:text-cream"
                  >
                    <%= truncate_id(report.assembly_id) %>
                  </.link>
                  <span><%= timestamp_label(report) %></span>
                </div>
              </div>

              <button
                :if={can_delete_report?(report, @current_account, @is_leader_or_operator)}
                id={"delete-#{report.id}"}
                type="button"
                phx-click="delete_report"
                phx-value-report_id={report.id}
                class="inline-flex rounded-full border border-warning/40 px-4 py-2 font-mono text-xs uppercase tracking-[0.22em] text-warning transition hover:border-warning hover:text-cream"
              >
                Delete
              </button>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  @spec can_delete_report?(IntelReport.t(), map() | nil, boolean()) :: boolean()
  defp can_delete_report?(
         %IntelReport{reported_by: reported_by},
         %{address: address},
         is_leader_or_operator
       ) do
    reported_by == address or is_leader_or_operator
  end

  defp can_delete_report?(_report, _current_account, _is_leader_or_operator), do: false

  @spec report_type_label(IntelReport.report_type()) :: String.t()
  defp report_type_label(:location), do: "Location"
  defp report_type_label(:scouting), do: "Scouting"

  @spec report_type_badge_classes(IntelReport.report_type()) :: String.t()
  defp report_type_badge_classes(:location) do
    "rounded-full border border-quantum-400/40 bg-quantum-400/10 px-3 py-1 font-mono text-xs uppercase tracking-[0.2em] text-quantum-300"
  end

  defp report_type_badge_classes(:scouting) do
    "rounded-full border border-success/40 bg-success/10 px-3 py-1 font-mono text-xs uppercase tracking-[0.2em] text-success"
  end

  @spec toggle_button_classes(boolean()) :: String.t()
  defp toggle_button_classes(true) do
    "rounded-full border border-quantum-300 bg-quantum-400/10 px-4 py-2 font-mono text-xs uppercase tracking-[0.24em] text-cream"
  end

  defp toggle_button_classes(false) do
    "rounded-full border border-space-600/80 bg-space-800/70 px-4 py-2 font-mono text-xs uppercase tracking-[0.24em] text-space-500 transition hover:border-quantum-400 hover:text-cream"
  end

  @spec report_system_name(%{optional(integer()) => String.t()}, integer() | nil) :: String.t()
  defp report_system_name(_system_names, 0), do: "Location undisclosed"

  defp report_system_name(system_names, solar_system_id) when is_integer(solar_system_id) do
    Map.get(system_names, solar_system_id, Integer.to_string(solar_system_id))
  end

  defp report_system_name(_system_names, _solar_system_id), do: "Location undisclosed"

  @spec timestamp_label(IntelReport.t()) :: String.t()
  defp timestamp_label(%IntelReport{updated_at: %DateTime{} = updated_at}) do
    IntelHelpers.relative_timestamp_label(updated_at)
  end

  defp timestamp_label(%IntelReport{inserted_at: %DateTime{} = inserted_at}) do
    IntelHelpers.relative_timestamp_label(inserted_at)
  end

  defp timestamp_label(_report), do: "Just now"
end
