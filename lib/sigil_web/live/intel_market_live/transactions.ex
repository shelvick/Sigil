defmodule SigilWeb.IntelMarketLive.Transactions do
  @moduledoc """
  Transaction-oriented workflows for the intel marketplace LiveView.
  """

  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [put_flash: 3, push_event: 3]

  alias Sigil.{Diplomacy, Intel, IntelMarket, StaticData}
  alias Sigil.Intel.IntelReport
  alias SigilWeb.IntelMarketLive.State

  @doc """
  Validates listing input and starts the Seal encrypt-and-upload flow.
  """
  @spec submit_listing(Phoenix.LiveView.Socket.t(), map()) :: Phoenix.LiveView.Socket.t()
  def submit_listing(%{assigns: %{can_sell: false}} = socket, _params) do
    put_flash(socket, :error, "creating listings requires a tribe-backed intel record")
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
        "config" => IntelMarket.build_seal_config(State.market_opts(socket)),
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

  @doc """
  Builds the unsigned create-listing transaction after Seal upload succeeds.
  """
  @spec build_listing_transaction(Phoenix.LiveView.Socket.t(), map(), map()) ::
          Phoenix.LiveView.Socket.t()
  def build_listing_transaction(socket, pending, payload) do
    params = %{
      seal_id: Map.fetch!(payload, "seal_id"),
      encrypted_blob_id: Map.get(payload, "encrypted_blob_id") || Map.fetch!(payload, "blob_id"),
      price: pending.price_mist,
      report_type: pending.report_type,
      solar_system_id: pending.solar_system_id,
      description: pending.description,
      intel_report_id: pending.report.id
    }

    builder_result =
      if pending.restricted? do
        IntelMarket.build_create_restricted_listing_tx(params, State.market_opts(socket))
      else
        IntelMarket.build_create_listing_tx(params, State.market_opts(socket))
      end

    case builder_result do
      {:ok, %{tx_bytes: tx_bytes, client_nonce: client_nonce}} ->
        socket
        |> assign(
          pending_listing: Map.put(pending, :client_nonce, client_nonce),
          pending_tx: %{kind: :create_listing, tx_bytes: tx_bytes},
          page_state: :signing_tx,
          seal_status: nil,
          seal_error_message: nil
        )
        |> push_event("request_sign_transaction", %{"tx_bytes" => tx_bytes})

      {:error, :no_active_custodian} ->
        socket
        |> assign(page_state: :ready, pending_listing: nil, pending_tx: nil, seal_status: nil)
        |> put_flash(:error, "restricted listings require an active custodian")

      {:error, reason} ->
        socket
        |> assign(page_state: :ready, pending_listing: nil, pending_tx: nil, seal_status: nil)
        |> put_flash(:error, "Transaction failed: #{inspect(reason)}")
    end
  end

  @doc """
  Begins a purchase flow for the selected listing.
  """
  @spec begin_purchase(Phoenix.LiveView.Socket.t(), String.t()) :: Phoenix.LiveView.Socket.t()
  def begin_purchase(socket, listing_id) do
    case IntelMarket.build_purchase_tx(listing_id, State.market_opts(socket)) do
      {:ok, %{tx_bytes: tx_bytes}} ->
        socket
        |> assign(page_state: :signing_tx, pending_tx: %{kind: :purchase, tx_bytes: tx_bytes})
        |> push_event("request_sign_transaction", %{"tx_bytes" => tx_bytes})

      {:error, :cannot_purchase_own_listing} ->
        put_flash(socket, :error, "cannot purchase your own listing")

      {:error, :restricted_listing_requires_matching_tribe} ->
        put_flash(socket, :error, "restricted listing")

      {:error, :no_active_custodian} ->
        put_flash(socket, :error, "restricted listing")

      {:error, :listing_not_active} ->
        put_flash(socket, :error, "Listing is no longer active")

      {:error, _reason} ->
        put_flash(socket, :error, "Transaction failed")
    end
  end

  @doc """
  Starts browser-side Seal decryption for a sold listing.
  """
  @spec begin_decrypt(Phoenix.LiveView.Socket.t(), String.t()) :: Phoenix.LiveView.Socket.t()
  def begin_decrypt(socket, listing_id) do
    opts = State.market_opts(socket)

    case IntelMarket.get_listing(listing_id, opts) do
      %_{seal_id: seal_id, encrypted_blob_id: encrypted_blob_id} = listing ->
        if IntelMarket.blob_available?(listing_id, opts) do
          socket
          |> assign(
            page_state: :decrypting_listing,
            pending_decrypt_listing_id: listing_id,
            seal_status: "decrypting",
            seal_error_message: nil
          )
          |> push_event("decrypt_intel", %{
            "listing_id" => listing_id,
            "seal_id" => seal_id,
            "blob_id" => encrypted_blob_id,
            "seller_address" => listing.seller_address,
            "config" => IntelMarket.build_seal_config(opts)
          })
        else
          socket
          |> assign(page_state: :ready, pending_decrypt_listing_id: nil, seal_status: nil)
          |> put_flash(:error, "Encrypted blob is unavailable right now — retry in a moment")
        end

      nil ->
        put_flash(socket, :error, "Listing not found")
    end
  end

  @doc """
  Begins the cancel-listing signing flow for the selected listing.
  """
  @spec cancel_listing(Phoenix.LiveView.Socket.t(), String.t()) :: Phoenix.LiveView.Socket.t()
  def cancel_listing(socket, listing_id) do
    case IntelMarket.build_cancel_listing_tx(listing_id, State.market_opts(socket)) do
      {:ok, %{tx_bytes: tx_bytes}} ->
        socket
        |> assign(
          page_state: :signing_tx,
          pending_tx: %{kind: :cancel_listing, tx_bytes: tx_bytes}
        )
        |> push_event("request_sign_transaction", %{"tx_bytes" => tx_bytes})

      {:error, _reason} ->
        put_flash(socket, :error, "Transaction failed")
    end
  end

  @doc """
  Submits a signed marketplace transaction and refreshes the UI state.
  """
  @spec finalize_transaction(Phoenix.LiveView.Socket.t(), String.t(), String.t()) ::
          Phoenix.LiveView.Socket.t()
  def finalize_transaction(
        %{assigns: %{pending_tx: %{kind: :create_listing}}} = socket,
        tx_bytes,
        signature
      ) do
    case IntelMarket.submit_signed_transaction(tx_bytes, signature, State.market_opts(socket)) do
      {:ok, %{effects_bcs: effects_bcs}} ->
        socket
        |> assign(page_state: :ready, pending_listing: nil, pending_tx: nil, seal_status: nil)
        |> maybe_push_effects(%{"bcs" => effects_bcs})
        |> put_flash(:info, "Listing created")
        |> State.refresh_marketplace()

      {:error, _reason} ->
        socket
        |> assign(page_state: :ready, pending_tx: nil, pending_listing: nil, seal_status: nil)
        |> put_flash(:error, "Transaction failed")
    end
  end

  @doc false
  def finalize_transaction(
        %{assigns: %{pending_tx: %{kind: kind}}} = socket,
        tx_bytes,
        signature
      )
      when kind in [:purchase, :cancel_listing] do
    case IntelMarket.submit_signed_transaction(tx_bytes, signature, State.market_opts(socket)) do
      {:ok, %{effects_bcs: effects_bcs}} ->
        socket =
          socket
          |> assign(page_state: :ready, pending_tx: nil, seal_status: nil)
          |> maybe_push_effects(%{"bcs" => effects_bcs})

        case kind do
          :purchase ->
            socket
            |> put_flash(
              :info,
              "Purchase successful — seller must reveal the canonical intel payload"
            )
            |> State.refresh_marketplace()

          :cancel_listing ->
            socket
            |> put_flash(:info, "Listing cancelled")
            |> State.refresh_marketplace()
        end

      {:error, _reason} ->
        socket
        |> assign(page_state: :ready, pending_tx: nil, seal_status: nil)
        |> put_flash(:error, "Transaction failed")
    end
  end

  @doc false
  def finalize_transaction(socket, _tx_bytes, _signature) do
    socket
    |> assign(page_state: :ready, pending_tx: nil, pending_listing: nil, seal_status: nil)
    |> put_flash(:error, "Transaction failed")
  end

  @doc """
  Stores decrypted intel returned by the browser hook for the selected listing.
  """
  @spec complete_decrypt(Phoenix.LiveView.Socket.t(), String.t(), map()) ::
          Phoenix.LiveView.Socket.t()
  def complete_decrypt(socket, listing_id, payload) do
    decrypted_intel =
      Map.put(socket.assigns.decrypted_intel, listing_id, decode_decrypted_payload(payload))

    socket
    |> assign(
      page_state: :ready,
      pending_decrypt_listing_id: nil,
      seal_status: nil,
      decrypted_intel: decrypted_intel
    )
    |> put_flash(:info, "Intel decrypted")
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

  defp resolve_report(socket, params) do
    persist_manual_report(socket, params)
  end

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

  @spec decode_decrypted_payload(map()) :: map()
  defp decode_decrypted_payload(%{"data" => decrypted_json}) when is_binary(decrypted_json) do
    case Jason.decode(decrypted_json) do
      {:ok, decoded} when is_map(decoded) -> decoded
      _other -> %{"raw" => decrypted_json}
    end
  end

  defp decode_decrypted_payload(payload) when is_map(payload), do: payload

  defp maybe_push_effects(socket, %{"bcs" => effects_bcs}) when is_binary(effects_bcs) do
    push_event(socket, "report_transaction_effects", %{effects: effects_bcs})
  end

  defp maybe_push_effects(socket, _effects), do: socket
end
