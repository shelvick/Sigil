defmodule SigilWeb.IntelMarketLive.Transactions.ListingFlow do
  @moduledoc """
  Listing creation flow helpers for IntelMarketLive transaction orchestration.
  """

  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [put_flash: 3, push_event: 3]

  alias Sigil.{Diplomacy, Intel, IntelMarket, StaticData}
  alias Sigil.Intel.IntelReport
  alias SigilWeb.IntelMarketLive.State

  @doc "Validates listing input and starts the Seal encrypt-and-upload flow."
  @spec submit_listing(Phoenix.LiveView.Socket.t(), map()) :: Phoenix.LiveView.Socket.t()
  def submit_listing(%{assigns: %{can_sell: false}} = socket, _params) do
    put_flash(socket, :error, "creating listings requires a tribe-backed intel record")
  end

  @doc false
  def submit_listing(%{assigns: %{active_pseudonym: pseudonym_address}} = socket, _params)
      when not is_binary(pseudonym_address) do
    put_flash(socket, :error, "Create and activate a pseudonym before listing intel")
  end

  @doc false
  def submit_listing(socket, params) do
    with :ok <- ensure_restriction_allowed(socket, params),
         {:ok, report} <- resolve_report(socket, params),
         {:ok, price_mist} <- State.parse_price_sui(Map.get(params, "price_sui")),
         description when is_binary(description) and description != "" <-
           Map.get(params, "description") do
      intel_data = export_intel_data(report, description)
      seal_id = random_seal_id()

      socket
      |> assign(
        pending_listing: %{
          report: report,
          restricted?: Map.get(params, "restricted") == "true",
          price_mist: price_mist,
          description: description,
          report_type: intel_data.report_type,
          solar_system_id: intel_data.solar_system_id,
          assembly_id: intel_data.assembly_id,
          notes: intel_data.notes,
          seal_id: seal_id
        },
        seal_error_message: nil,
        seal_status: "encrypting",
        page_state: :preparing_listing
      )
      |> push_event("encrypt_and_upload", %{
        "intel_data" => %{
          "report_type" => intel_data.report_type,
          "solar_system_id" => intel_data.solar_system_id,
          "assembly_id" => intel_data.assembly_id,
          "notes" => intel_data.notes,
          "label" => intel_data.label
        },
        "seal_id" => seal_id,
        "config" => IntelMarket.build_seal_config(State.seal_opts(socket)),
        "report_type" => intel_data.report_type,
        "solar_system_id" => intel_data.solar_system_id,
        "assembly_id" => intel_data.assembly_id,
        "notes" => intel_data.notes
      })
    else
      {:error, :missing_active_custodian} ->
        put_flash(socket, :error, "restricted listings require an active custodian")

      {:error, :unknown_report} ->
        put_flash(socket, :error, "Select an intel report")

      {:error, :unknown_solar_system} ->
        put_flash(socket, :error, "Unknown or ambiguous solar system")

      {:error, %Ecto.Changeset{} = changeset} ->
        put_flash(socket, :error, State.changeset_error(changeset))

      :error ->
        put_flash(socket, :error, "Enter a valid price")

      _other ->
        put_flash(socket, :error, "Unable to prepare listing")
    end
  end

  @doc "Builds the unsigned create-listing transaction after Seal upload succeeds."
  @spec build_listing_transaction(Phoenix.LiveView.Socket.t(), map(), map()) ::
          Phoenix.LiveView.Socket.t()
  def build_listing_transaction(socket, pending, payload) do
    params =
      %{
        seal_id: Map.fetch!(payload, "seal_id"),
        encrypted_blob_id:
          Map.get(payload, "encrypted_blob_id") || Map.fetch!(payload, "blob_id"),
        price: pending.price_mist,
        report_type: pending.report_type,
        solar_system_id: pending.solar_system_id,
        description: pending.description,
        intel_report_id: pending.report.id
      }
      |> maybe_put_restricted_tribe_id(pending, socket)

    case build_listing_builder_result(socket, params) do
      {:ok, %{tx_bytes: tx_bytes, relay_signature: relay_signature, client_nonce: client_nonce}} ->
        socket
        |> assign(
          pending_listing: Map.put(pending, :client_nonce, client_nonce),
          pending_tx: %{
            kind: :create_listing_pseudonym,
            tx_bytes: tx_bytes,
            relay_signature: relay_signature,
            pseudonym_address: socket.assigns.active_pseudonym
          },
          page_state: :signing_tx,
          seal_status: nil,
          seal_error_message: nil
        )
        |> push_event("sign_pseudonym_tx", %{
          "pseudonym_address" => socket.assigns.active_pseudonym,
          "tx_bytes" => tx_bytes
        })

      {:error, :no_active_custodian} ->
        socket
        |> assign(page_state: :ready, pending_listing: nil, pending_tx: nil, seal_status: nil)
        |> put_flash(:error, "restricted listings require an active custodian")

      {:error, :missing_pseudonym} ->
        socket
        |> assign(page_state: :ready, pending_listing: nil, pending_tx: nil, seal_status: nil)
        |> put_flash(:error, "Create and activate a pseudonym before listing intel")

      {:error, reason} ->
        socket
        |> assign(page_state: :ready, pending_listing: nil, pending_tx: nil, seal_status: nil)
        |> put_flash(:error, "Transaction failed: #{inspect(reason)}")
    end
  end

  @spec build_listing_builder_result(Phoenix.LiveView.Socket.t(), map()) ::
          {:ok,
           %{tx_bytes: String.t(), relay_signature: String.t(), client_nonce: non_neg_integer()}}
          | {:error, term()}
  defp build_listing_builder_result(socket, params) do
    opts = State.market_opts(socket)

    case socket.assigns.active_pseudonym do
      pseudonym_address when is_binary(pseudonym_address) ->
        IntelMarket.build_pseudonym_create_listing_tx(
          params,
          Keyword.put(opts, :pseudonym_address, pseudonym_address)
        )

      _other ->
        {:error, :missing_pseudonym}
    end
  end

  defp ensure_restriction_allowed(socket, %{"restricted" => "true"}) do
    if Diplomacy.get_active_custodian(State.diplomacy_opts(socket)) do
      :ok
    else
      {:error, :missing_active_custodian}
    end
  end

  defp ensure_restriction_allowed(_socket, _params), do: :ok

  defp resolve_report(socket, %{"entry_mode" => "existing", "report_id" => report_id}) do
    case Enum.find(socket.assigns.my_reports, &(&1.id == report_id)) do
      %IntelReport{} = report -> {:ok, report}
      nil -> {:error, :unknown_report}
    end
  end

  defp resolve_report(socket, params), do: persist_manual_report(socket, params)

  defp persist_manual_report(socket, params) do
    solar_system_name = Map.get(params, "solar_system_name", "") |> String.trim()

    solar_system_id =
      if solar_system_name == "" do
        nil
      else
        case StaticData.get_solar_system_by_name(
               socket.assigns.static_data_pid,
               solar_system_name
             ) do
          %{id: id} -> id
          nil -> :unknown
        end
      end

    if solar_system_id == :unknown do
      {:error, :unknown_solar_system}
    else
      attrs = manual_report_attrs(socket, params, solar_system_id)

      case persist_report(attrs, params, socket) do
        {:ok, report} -> {:ok, report}
        {:error, %Ecto.Changeset{} = changeset} -> {:error, changeset}
      end
    end
  end

  defp manual_report_attrs(socket, params, solar_system_id) do
    %{
      tribe_id: socket.assigns.tribe_id,
      assembly_id: State.blank_to_nil(Map.get(params, "assembly_id")),
      solar_system_id: solar_system_id,
      label: State.blank_to_nil(Map.get(params, "description")),
      notes: State.blank_to_nil(Map.get(params, "notes")),
      reported_by: socket.assigns.sender,
      reported_by_name: State.active_character_name(socket.assigns.active_character),
      reported_by_character_id: socket.assigns.active_character.id
    }
  end

  defp persist_report(attrs, %{"report_type" => "2"}, socket),
    do: Intel.report_scouting(attrs, State.intel_opts(socket))

  defp persist_report(attrs, _params, socket),
    do: Intel.report_location(attrs, State.intel_opts(socket))

  @spec export_intel_data(IntelReport.t(), String.t()) :: %{
          report_type: 1 | 2,
          solar_system_id: non_neg_integer(),
          assembly_id: String.t(),
          notes: String.t(),
          label: String.t()
        }
  defp export_intel_data(%IntelReport{} = report, description) when is_binary(description) do
    %{
      report_type: report_type_value(report.report_type),
      solar_system_id: report.solar_system_id || 0,
      assembly_id: report.assembly_id || "",
      notes: report.notes || "",
      label: description
    }
  end

  @spec report_type_value(IntelReport.report_type() | nil) :: 1 | 2
  defp report_type_value(:scouting), do: 2
  defp report_type_value(_report_type), do: 1

  @spec random_seal_id() :: String.t()
  defp random_seal_id do
    "0x" <> Base.encode16(:crypto.strong_rand_bytes(32), case: :lower)
  end

  defp maybe_put_restricted_tribe_id(params, %{restricted?: true}, socket) do
    Map.put(params, :restricted_to_tribe_id, socket.assigns.tribe_id)
  end

  defp maybe_put_restricted_tribe_id(params, _pending, _socket), do: params
end
