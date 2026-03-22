defmodule SigilWeb.IntelLive do
  @moduledoc """
  Tribe-scoped intel feed and report entry page.
  """

  use SigilWeb, :live_view

  import SigilWeb.TribeHelpers, only: [authorize_tribe: 2]

  alias Sigil.{Intel, StaticData}
  alias Sigil.Intel.IntelReport

  @doc """
  Mounts the tribe intel page for the authenticated tribe member.
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
          |> load_reports()
          |> maybe_warm_cache()
          |> maybe_load_solar_systems()
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

  @doc false
  @impl true
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("toggle_report_type", %{"report_type" => report_type}, socket) do
    {:noreply,
     socket
     |> assign(:report_type, parse_report_type(report_type))
     |> assign_form(%{})}
  end

  def handle_event("submit_report", _params, %{assigns: %{intel_available: false}} = socket) do
    {:noreply, put_flash(socket, :error, "Intel storage not available")}
  end

  def handle_event("submit_report", %{"report" => params}, socket) do
    {:noreply, submit_report(socket, params)}
  end

  def handle_event("validate", %{"report" => params}, socket) do
    {:noreply, assign_form(socket, params)}
  end

  def handle_event("delete_report", %{"report_id" => report_id}, socket) do
    delete_params = %{
      tribe_id: socket.assigns.tribe_id,
      reported_by: socket.assigns.current_account.address,
      is_leader_or_operator: socket.assigns.is_leader_or_operator
    }

    socket =
      case Intel.delete_intel(report_id, delete_params, intel_opts(socket)) do
        :ok ->
          socket
          |> put_flash(:info, "Report removed")
          |> load_reports()

        {:error, :unauthorized} ->
          put_flash(socket, :error, "Not authorized to delete this report")

        {:error, :not_found} ->
          put_flash(socket, :error, "Report not found")
      end

    {:noreply, socket}
  end

  @doc false
  @impl true
  @spec handle_info(term(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_info({:intel_updated, %IntelReport{tribe_id: tribe_id} = report}, socket)
      when tribe_id == socket.assigns.tribe_id do
    {:noreply,
     socket
     |> assign(:reports, replace_report(socket.assigns.reports, report))
     |> maybe_put_system_name(report)}
  end

  def handle_info({:intel_deleted, %IntelReport{tribe_id: tribe_id} = report}, socket)
      when tribe_id == socket.assigns.tribe_id do
    {:noreply,
     assign(socket, :reports, Enum.reject(socket.assigns.reports, &(&1.id == report.id)))}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  @doc false
  @impl true
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <section class="relative overflow-hidden px-4 py-12 sm:px-6 lg:px-8">
      <div class="mx-auto max-w-6xl space-y-8">
        <div class="rounded-[2rem] border border-space-600/80 bg-space-900/70 p-8 shadow-2xl shadow-black/40 backdrop-blur">
          <div class="flex flex-col gap-4 md:flex-row md:items-start md:justify-between">
            <div>
              <p class="font-mono text-xs uppercase tracking-[0.35em] text-quantum-300">Tribe intel</p>
              <h1 class="mt-3 text-4xl font-semibold text-cream">Intel Feed</h1>
              <p class="mt-3 max-w-2xl text-sm leading-6 text-space-500">
                Share confirmed locations and scouting updates with your tribe.
              </p>
            </div>
            <.link
              navigate={~p"/tribe/#{@tribe_id}"}
              class="inline-flex items-center rounded-full border border-space-600/80 bg-space-800/70 px-4 py-2 font-mono text-xs uppercase tracking-[0.2em] text-foreground transition hover:border-quantum-400 hover:text-quantum-300"
            >
              Tribe Overview
            </.link>
          </div>
        </div>

        <div class="grid gap-8 xl:grid-cols-[0.95fr_1.05fr]">
          <SigilWeb.IntelLive.Components.report_entry_panel
            report_type={@report_type}
            active_character={@active_character}
            intel_available={@intel_available}
            static_data_pid={@static_data_pid}
            form={@form}
            solar_systems={@solar_systems}
          />

          <SigilWeb.IntelLive.Components.report_feed_panel
            reports={@reports}
            system_names={@system_names}
            current_account={@current_account}
            is_leader_or_operator={@is_leader_or_operator}
          />
        </div>
      </div>
    </section>
    """
  end

  @spec assign_base_state(Phoenix.LiveView.Socket.t(), integer()) :: Phoenix.LiveView.Socket.t()
  defp assign_base_state(socket, tribe_id) do
    socket
    |> assign(
      tribe_id: tribe_id,
      page_title: "Tribe Intel",
      reports: [],
      report_type: :location,
      static_data_pid: socket.assigns[:static_data],
      solar_systems: [],
      system_names: %{},
      is_leader_or_operator: false,
      intel_available:
        is_map(socket.assigns[:cache_tables]) and
          Map.has_key?(socket.assigns[:cache_tables], :intel)
    )
    |> assign_form(%{})
  end

  @spec assign_form(Phoenix.LiveView.Socket.t(), map()) :: Phoenix.LiveView.Socket.t()
  defp assign_form(socket, params) do
    assign(
      socket,
      :form,
      to_form(%{"report_type" => Atom.to_string(socket.assigns.report_type)} |> Map.merge(params),
        as: :report
      )
    )
  end

  @spec maybe_warm_cache(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp maybe_warm_cache(%{assigns: %{cache_tables: cache_tables}} = socket)
       when is_map(cache_tables) do
    if Map.has_key?(cache_tables, :intel) do
      Intel.load_cache(socket.assigns.tribe_id, intel_opts(socket))
    end

    socket
  end

  defp maybe_warm_cache(socket), do: socket

  @spec maybe_load_solar_systems(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp maybe_load_solar_systems(%{assigns: %{static_data_pid: pid}} = socket)
       when is_pid(pid) do
    if connected?(socket) do
      assign(socket, :solar_systems, StaticData.list_solar_systems(pid))
    else
      socket
    end
  end

  defp maybe_load_solar_systems(socket), do: socket

  @spec maybe_subscribe(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp maybe_subscribe(socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(socket.assigns.pubsub, intel_topic(socket.assigns.tribe_id))
    end

    socket
  end

  @spec load_reports(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp load_reports(socket) do
    reports = Intel.list_intel(socket.assigns.tribe_id, intel_opts(socket))

    socket
    |> assign(:reports, reports)
    |> assign(:system_names, system_names(reports, socket.assigns.static_data_pid))
  end

  @spec submit_report(Phoenix.LiveView.Socket.t(), map()) :: Phoenix.LiveView.Socket.t()
  defp submit_report(socket, params) do
    with %{} = current_account <- socket.assigns.current_account,
         %{} = active_character <- socket.assigns.active_character,
         pid when is_pid(pid) <- socket.assigns.static_data_pid,
         %{} = solar_system <-
           StaticData.get_solar_system_by_name(pid, Map.get(params, "solar_system_name", "")) do
      attrs = %{
        tribe_id: socket.assigns.tribe_id,
        assembly_id: normalize_assembly_id(Map.get(params, "assembly_id")),
        solar_system_id: solar_system.id,
        label: blank_to_nil(Map.get(params, "label")),
        notes: blank_to_nil(Map.get(params, "notes")),
        reported_by: current_account.address,
        reported_by_name: character_name(active_character),
        reported_by_character_id: active_character.id
      }

      case persist_report(socket.assigns.report_type, attrs, socket) do
        {:ok, _report} ->
          socket
          |> put_flash(:info, "Report shared")
          |> load_reports()
          |> assign_form(%{})

        {:error, :unauthorized} ->
          put_flash(socket, :error, "Not your tribe")

        {:error, %Ecto.Changeset{} = changeset} ->
          socket
          |> put_flash(:error, changeset_error(changeset))
          |> assign_form(params)
      end
    else
      nil ->
        socket
        |> put_flash(:error, "Unknown or ambiguous solar system")
        |> assign_form(params)

      _other ->
        socket
        |> put_flash(:error, fallback_submit_error(socket))
        |> assign_form(params)
    end
  end

  @spec persist_report(:location | :scouting, map(), Phoenix.LiveView.Socket.t()) ::
          {:ok, IntelReport.t()} | {:error, Ecto.Changeset.t() | :unauthorized}
  defp persist_report(:location, attrs, socket),
    do: Intel.report_location(attrs, intel_opts(socket))

  defp persist_report(:scouting, attrs, socket),
    do: Intel.report_scouting(attrs, intel_opts(socket))

  @spec fallback_submit_error(Phoenix.LiveView.Socket.t()) :: String.t()
  defp fallback_submit_error(%{assigns: %{active_character: nil}}),
    do: "Select a character to submit reports"

  defp fallback_submit_error(%{assigns: %{static_data_pid: nil}}),
    do: "Solar system data not available"

  defp fallback_submit_error(_socket), do: "Unable to submit report"

  @spec replace_report([IntelReport.t()], IntelReport.t()) :: [IntelReport.t()]
  defp replace_report(
         reports,
         %IntelReport{report_type: :location, assembly_id: assembly_id} = report
       )
       when is_binary(assembly_id) do
    reports
    |> Enum.reject(fn existing ->
      existing.id == report.id or
        (existing.report_type == :location and existing.assembly_id == assembly_id)
    end)
    |> List.insert_at(0, report)
  end

  defp replace_report(reports, report) do
    [report | Enum.reject(reports, &(&1.id == report.id))]
  end

  @spec maybe_put_system_name(Phoenix.LiveView.Socket.t(), IntelReport.t()) ::
          Phoenix.LiveView.Socket.t()
  defp maybe_put_system_name(socket, report) do
    case resolve_system_name(socket.assigns.static_data_pid, report.solar_system_id) do
      nil ->
        socket

      name ->
        assign(
          socket,
          :system_names,
          Map.put(socket.assigns.system_names, report.solar_system_id, name)
        )
    end
  end

  @spec system_names([IntelReport.t()], pid() | nil) :: %{integer() => String.t()}
  defp system_names(reports, static_data_pid) do
    Enum.reduce(reports, %{}, fn report, acc ->
      case resolve_system_name(static_data_pid, report.solar_system_id) do
        nil -> acc
        name -> Map.put(acc, report.solar_system_id, name)
      end
    end)
  end

  @spec resolve_system_name(pid() | nil, integer() | nil) :: String.t() | nil
  defp resolve_system_name(pid, solar_system_id)
       when is_pid(pid) and is_integer(solar_system_id) do
    case StaticData.get_solar_system(pid, solar_system_id) do
      %{name: name} -> name
      _other -> nil
    end
  end

  defp resolve_system_name(_pid, _solar_system_id), do: nil

  @spec intel_opts(Phoenix.LiveView.Socket.t()) :: Intel.options()
  defp intel_opts(socket) do
    [
      tables: socket.assigns.cache_tables,
      pubsub: socket.assigns.pubsub,
      authorized_tribe_id: socket.assigns.tribe_id
    ]
  end

  @spec parse_report_type(String.t()) :: :location | :scouting
  defp parse_report_type("scouting"), do: :scouting
  defp parse_report_type(_value), do: :location

  @spec normalize_assembly_id(String.t() | nil) :: String.t() | nil
  defp normalize_assembly_id(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_assembly_id(_value), do: nil

  @spec blank_to_nil(String.t() | nil) :: String.t() | nil
  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(_value), do: nil

  @spec character_name(map()) :: String.t() | nil
  defp character_name(%{metadata: %{name: name}}) when is_binary(name), do: name
  defp character_name(_character), do: nil

  @spec changeset_error(Ecto.Changeset.t()) :: String.t()
  defp changeset_error(changeset) do
    Enum.map_join(changeset.errors, ", ", fn {field, {message, _opts}} ->
      "#{Phoenix.Naming.humanize(field)} #{message}"
    end)
  end

  @spec intel_topic(integer()) :: String.t()
  defp intel_topic(tribe_id), do: Sigil.Intel.topic(tribe_id)
end
