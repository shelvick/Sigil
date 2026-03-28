defmodule SigilWeb.IntelMarketLive.State.Filtering do
  @moduledoc """
  Filtering and form-prefill helpers for IntelMarketLive state management.
  """

  alias Sigil.StaticData
  alias Sigil.Intel.IntelReport
  alias SigilWeb.IntelMarketLive.State

  @doc "Returns default browse filters for the marketplace listing grid."
  @spec default_filters() :: map()
  def default_filters do
    %{
      "report_type" => "",
      "solar_system_name" => "",
      "price_min_sui" => "",
      "price_max_sui" => ""
    }
  end

  @doc "Evaluates whether a listing matches the currently selected browse filters."
  @spec matches_filters?(map(), map(), pid() | nil) :: boolean()
  def matches_filters?(listing, filters, static_data_pid) do
    matches_report_type?(listing, filters["report_type"]) and
      matches_solar_system?(listing, filters["solar_system_name"], static_data_pid) and
      matches_price?(listing, filters["price_min_sui"], :min) and
      matches_price?(listing, filters["price_max_sui"], :max)
  end

  @doc "Prefills listing form fields from an existing intel report selection."
  @spec maybe_fill_from_report(map(), Phoenix.LiveView.Socket.t()) :: map()
  def maybe_fill_from_report(
        %{"entry_mode" => "existing", "report_id" => report_id} = params,
        socket
      )
      when is_binary(report_id) and report_id != "" do
    case Enum.find(socket.assigns.my_reports, &(&1.id == report_id)) do
      %IntelReport{} = report ->
        params
        |> Map.put("report_type", Integer.to_string(State.report_type_value(report.report_type)))
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

  def maybe_fill_from_report(params, _socket), do: params

  @doc "Fills `solar_system_id` from selected solar system name when resolvable."
  @spec maybe_fill_solar_system_id(map(), pid() | nil) :: map()
  def maybe_fill_solar_system_id(%{"solar_system_name" => name} = params, static_data_pid)
      when is_pid(static_data_pid) and is_binary(name) and name != "" do
    case StaticData.get_solar_system_by_name(static_data_pid, name) do
      %{id: id} -> Map.put(params, "solar_system_id", Integer.to_string(id))
      _other -> params
    end
  end

  def maybe_fill_solar_system_id(params, _static_data_pid), do: params

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
    case State.parse_price_sui(value) do
      {:ok, amount} -> listing.price_mist >= amount
      :error -> true
    end
  end

  defp matches_price?(listing, value, :max) do
    case State.parse_price_sui(value) do
      {:ok, amount} -> listing.price_mist <= amount
      :error -> true
    end
  end

  defp solar_system_name(pid, solar_system_id) when is_pid(pid) and is_integer(solar_system_id) do
    case StaticData.get_solar_system(pid, solar_system_id) do
      %{name: name} -> name
      _other -> ""
    end
  end

  defp solar_system_name(_pid, _solar_system_id), do: ""
end
