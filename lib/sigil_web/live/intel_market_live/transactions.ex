defmodule SigilWeb.IntelMarketLive.Transactions do
  @moduledoc """
  Transaction-oriented workflows for the intel marketplace LiveView.
  """

  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [put_flash: 3, push_event: 3]

  alias Sigil.IntelMarket
  alias SigilWeb.IntelMarketLive.State
  alias SigilWeb.IntelMarketLive.Transactions.ListingFlow

  @doc """
  Validates listing input and starts the Seal encrypt-and-upload flow.
  """
  @spec submit_listing(Phoenix.LiveView.Socket.t(), map()) :: Phoenix.LiveView.Socket.t()
  defdelegate submit_listing(socket, params), to: ListingFlow

  @doc """
  Builds the unsigned create-listing transaction after Seal upload succeeds.
  """
  @spec build_listing_transaction(Phoenix.LiveView.Socket.t(), map(), map()) ::
          Phoenix.LiveView.Socket.t()
  defdelegate build_listing_transaction(socket, pending, payload), to: ListingFlow

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
    opts = State.market_opts(socket)

    result =
      case IntelMarket.get_listing(listing_id, opts) do
        %{seller_address: seller_address}
        when is_binary(socket.assigns.active_pseudonym) and
               seller_address == socket.assigns.active_pseudonym ->
          IntelMarket.build_pseudonym_cancel_listing_tx(
            listing_id,
            Keyword.put(opts, :pseudonym_address, socket.assigns.active_pseudonym)
          )

        %{seller_address: seller_address} when seller_address == socket.assigns.sender ->
          IntelMarket.build_cancel_listing_tx(listing_id, opts)

        nil ->
          {:error, :listing_not_found}

        _other_listing ->
          {:error, :not_listing_owner}
      end

    case result do
      {:ok, %{tx_bytes: tx_bytes, relay_signature: relay_signature}} ->
        socket
        |> assign(
          page_state: :signing_tx,
          pending_tx: %{
            kind: :cancel_listing_pseudonym,
            tx_bytes: tx_bytes,
            relay_signature: relay_signature,
            pseudonym_address: socket.assigns.active_pseudonym
          }
        )
        |> push_event("sign_pseudonym_tx", %{
          "pseudonym_address" => socket.assigns.active_pseudonym,
          "tx_bytes" => tx_bytes
        })

      {:ok, %{tx_bytes: tx_bytes}} ->
        socket
        |> assign(
          page_state: :signing_tx,
          pending_tx: %{kind: :cancel_listing, tx_bytes: tx_bytes}
        )
        |> push_event("request_sign_transaction", %{"tx_bytes" => tx_bytes})

      {:error, :listing_not_found} ->
        put_flash(socket, :error, "Listing not found")

      {:error, :not_listing_owner} ->
        put_flash(socket, :error, "Only the listing owner can cancel this listing")

      {:error, :missing_pseudonym} ->
        put_flash(socket, :error, "Select an active pseudonym to cancel this listing")

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
        %{assigns: %{pending_tx: %{kind: :create_listing_pseudonym} = pending_tx}} = socket,
        tx_bytes,
        pseudonym_signature
      )
      when pending_tx.tx_bytes == tx_bytes and is_binary(pseudonym_signature) do
    case IntelMarket.submit_pseudonym_transaction(
           tx_bytes,
           pseudonym_signature,
           pending_tx.relay_signature,
           State.market_opts(socket)
         ) do
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
        %{assigns: %{pending_tx: %{kind: :create_listing} = pending_tx}} = socket,
        tx_bytes,
        signature
      ) do
    opts = Keyword.put(State.market_opts(socket), :kind_bytes, pending_tx.tx_bytes)

    case IntelMarket.submit_signed_transaction(tx_bytes, signature, opts) do
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
        %{assigns: %{pending_tx: %{kind: :cancel_listing_pseudonym} = pending_tx}} = socket,
        tx_bytes,
        pseudonym_signature
      )
      when pending_tx.tx_bytes == tx_bytes and is_binary(pseudonym_signature) do
    case IntelMarket.submit_pseudonym_transaction(
           tx_bytes,
           pseudonym_signature,
           pending_tx.relay_signature,
           State.market_opts(socket)
         ) do
      {:ok, %{effects_bcs: effects_bcs}} ->
        socket
        |> assign(page_state: :ready, pending_tx: nil, seal_status: nil)
        |> maybe_push_effects(%{"bcs" => effects_bcs})
        |> put_flash(:info, "Listing cancelled")
        |> State.refresh_marketplace()

      {:error, _reason} ->
        socket
        |> assign(page_state: :ready, pending_tx: nil, seal_status: nil)
        |> put_flash(:error, "Transaction failed")
    end
  end

  @doc false
  def finalize_transaction(
        %{assigns: %{pending_tx: %{kind: kind} = pending_tx}} = socket,
        tx_bytes,
        signature
      )
      when kind in [:purchase, :cancel_listing, :confirm_quality, :report_bad_quality] do
    case submit_signed_tx(socket, tx_bytes, signature, pending_tx.tx_bytes) do
      {:ok, %{effects_bcs: effects_bcs}} ->
        socket
        |> assign(page_state: :ready, pending_tx: nil, seal_status: nil)
        |> maybe_push_effects(%{"bcs" => effects_bcs})
        |> handle_successful_signed_tx(kind, pending_tx)

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

  @doc """
  Builds buyer feedback transactions for decrypted purchased intel and requests wallet signing.
  """
  @spec submit_feedback(
          Phoenix.LiveView.Socket.t(),
          String.t(),
          :confirm_quality | :report_bad_quality
        ) ::
          Phoenix.LiveView.Socket.t()
  def submit_feedback(socket, listing_id, action)
      when is_binary(listing_id) and action in [:confirm_quality, :report_bad_quality] do
    case build_feedback_tx(listing_id, action, socket) do
      {:ok, %{tx_bytes: tx_bytes}} ->
        socket
        |> assign(
          page_state: :signing_tx,
          pending_tx: %{kind: action, tx_bytes: tx_bytes, listing_id: listing_id}
        )
        |> push_event("request_sign_transaction", %{"tx_bytes" => tx_bytes})

      {:error, :already_reviewed} ->
        put_flash(socket, :error, "Feedback already submitted")

      {:error, :listing_not_sold} ->
        put_flash(socket, :error, "Only sold listings can be reviewed")

      {:error, :listing_not_found} ->
        put_flash(socket, :error, "Listing not found")

      {:error, :reputation_unavailable} ->
        put_flash(socket, :error, "Feedback system unavailable")

      {:error, _reason} ->
        put_flash(socket, :error, "Transaction failed")
    end
  end

  @spec decode_decrypted_payload(map()) :: map()
  defp decode_decrypted_payload(%{"data" => decrypted_json}) when is_binary(decrypted_json) do
    case Jason.decode(decrypted_json) do
      {:ok, decoded} when is_map(decoded) -> decoded
      _other -> %{"raw" => decrypted_json}
    end
  end

  defp decode_decrypted_payload(payload) when is_map(payload), do: payload

  @spec build_feedback_tx(
          String.t(),
          :confirm_quality | :report_bad_quality,
          Phoenix.LiveView.Socket.t()
        ) :: {:ok, %{tx_bytes: String.t()}} | {:error, term()}
  defp build_feedback_tx(listing_id, :confirm_quality, socket) do
    IntelMarket.build_confirm_quality_tx(listing_id, State.market_opts(socket))
  end

  defp build_feedback_tx(listing_id, :report_bad_quality, socket) do
    IntelMarket.build_report_bad_quality_tx(listing_id, State.market_opts(socket))
  end

  @spec submit_signed_tx(Phoenix.LiveView.Socket.t(), String.t(), String.t(), String.t()) ::
          {:ok, %{digest: String.t(), effects_bcs: String.t() | nil}} | {:error, term()}
  defp submit_signed_tx(socket, tx_bytes, signature, kind_bytes) do
    opts = Keyword.put(State.market_opts(socket), :kind_bytes, kind_bytes)

    case socket.assigns.pending_tx.kind do
      kind when kind in [:confirm_quality, :report_bad_quality] ->
        IntelMarket.submit_feedback_transaction(tx_bytes, signature, opts)

      _other ->
        IntelMarket.submit_signed_transaction(tx_bytes, signature, opts)
    end
  end

  @spec handle_successful_signed_tx(
          Phoenix.LiveView.Socket.t(),
          :purchase | :cancel_listing | :confirm_quality | :report_bad_quality,
          map()
        ) :: Phoenix.LiveView.Socket.t()
  defp handle_successful_signed_tx(socket, :purchase, _pending_tx) do
    socket
    |> put_flash(:info, "Purchase successful — seller must reveal the canonical intel payload")
    |> State.refresh_marketplace()
  end

  defp handle_successful_signed_tx(socket, :cancel_listing, _pending_tx) do
    socket
    |> put_flash(:info, "Listing cancelled")
    |> State.refresh_marketplace()
  end

  defp handle_successful_signed_tx(socket, action, pending_tx)
       when action in [:confirm_quality, :report_bad_quality] do
    socket
    |> maybe_mark_feedback_recorded(pending_tx)
    |> put_flash(:info, "Feedback submitted")
    |> State.refresh_marketplace()
  end

  @spec maybe_mark_feedback_recorded(Phoenix.LiveView.Socket.t(), map()) ::
          Phoenix.LiveView.Socket.t()
  defp maybe_mark_feedback_recorded(socket, %{listing_id: listing_id})
       when is_binary(listing_id) do
    State.mark_feedback_recorded(socket, listing_id)
  end

  defp maybe_mark_feedback_recorded(socket, _pending_tx), do: socket

  defp maybe_push_effects(socket, %{"bcs" => effects_bcs}) when is_binary(effects_bcs) do
    push_event(socket, "report_transaction_effects", %{effects: effects_bcs})
  end

  defp maybe_push_effects(socket, _effects), do: socket
end
