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
  Validates listing input and starts the proof-generation flow.
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
      exported = Intel.export_for_commitment(report)

      socket
      |> assign(
        pending_listing: %{
          report: report,
          restricted?: Map.get(params, "restricted") == "true",
          price_mist: price_mist,
          description: description,
          report_type: exported.report_type,
          solar_system_id: exported.solar_system_id,
          assembly_id: exported.assembly_id,
          notes: exported.notes
        },
        proof_error_message: nil,
        proof_status: nil,
        page_state: :generating_proof
      )
      |> push_event("generate_proof", %{
        "report_type" => exported.report_type,
        "solar_system_id" => exported.solar_system_id,
        "assembly_id" => exported.assembly_id,
        "notes" => exported.notes
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
  Builds the unsigned create-listing transaction after proof generation succeeds.
  """
  @spec build_listing_transaction(Phoenix.LiveView.Socket.t(), map(), map()) ::
          Phoenix.LiveView.Socket.t()
  def build_listing_transaction(socket, pending, payload) do
    params = %{
      proof_points: Map.fetch!(payload, "proof_points"),
      public_inputs: Map.fetch!(payload, "public_inputs"),
      commitment: Map.fetch!(payload, "commitment"),
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
          proof_status: nil,
          proof_error_message: nil
        )
        |> push_event("request_sign_transaction", %{"tx_bytes" => tx_bytes})

      {:error, :no_active_custodian} ->
        socket
        |> assign(page_state: :ready, pending_listing: nil, pending_tx: nil, proof_status: nil)
        |> put_flash(:error, "restricted listings require an active custodian")

      {:error, reason} ->
        socket
        |> assign(page_state: :ready, pending_listing: nil, pending_tx: nil, proof_status: nil)
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

      {:error, _reason} ->
        put_flash(socket, :error, "Transaction failed")
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
        |> assign(page_state: :ready, pending_listing: nil, pending_tx: nil, proof_status: nil)
        |> maybe_push_effects(%{"bcs" => effects_bcs})
        |> put_flash(:info, "Listing created")
        |> State.refresh_marketplace()

      {:error, _reason} ->
        socket
        |> assign(page_state: :ready, pending_tx: nil, pending_listing: nil, proof_status: nil)
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
          |> assign(page_state: :ready, pending_tx: nil, proof_status: nil)
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
        |> assign(page_state: :ready, pending_tx: nil, proof_status: nil)
        |> put_flash(:error, "Transaction failed")
    end
  end

  @doc false
  def finalize_transaction(socket, _tx_bytes, _signature) do
    socket
    |> assign(page_state: :ready, pending_tx: nil, pending_listing: nil, proof_status: nil)
    |> put_flash(:error, "Transaction failed")
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
    with %{id: solar_system_id} <-
           StaticData.get_solar_system_by_name(
             socket.assigns.static_data_pid,
             Map.get(params, "solar_system_name", "")
           ),
         attrs <- manual_report_attrs(socket, params, solar_system_id),
         {:ok, report} <- persist_report(attrs, params, socket) do
      {:ok, report}
    else
      nil -> {:error, :unknown_solar_system}
      {:error, %Ecto.Changeset{} = changeset} -> {:error, changeset}
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

  defp maybe_push_effects(socket, %{"bcs" => effects_bcs}) when is_binary(effects_bcs) do
    push_event(socket, "report_transaction_effects", %{effects: effects_bcs})
  end

  defp maybe_push_effects(socket, _effects), do: socket
end
