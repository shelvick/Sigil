defmodule SigilWeb.DiplomacyLive.Transactions do
  @moduledoc """
  Transaction building and submission helpers for diplomacy LiveView.
  """

  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [put_flash: 3, push_event: 3]

  import SigilWeb.TransactionHelpers, only: [localnet?: 1]

  alias Sigil.Diplomacy
  alias SigilWeb.DiplomacyLive.State

  @doc "Builds a diplomacy transaction and transitions to signing state on success."
  @spec build_transaction(
          Phoenix.LiveView.Socket.t(),
          (Diplomacy.options() -> {:ok, %{tx_bytes: String.t()}} | {:error, term()})
        ) :: Phoenix.LiveView.Socket.t()
  def build_transaction(socket, builder) when is_function(builder, 1) do
    opts = State.diplomacy_opts(socket)

    case socket.assigns.character_ref || State.maybe_resolve_character_ref(socket, opts) do
      nil ->
        put_flash(socket, :error, "Active character reference unavailable")

      character_ref ->
        socket
        |> assign(character_ref: character_ref)
        |> handle_tx_build_result(builder.(Keyword.put(opts, :character_ref, character_ref)))
    end
  end

  @spec handle_tx_build_result(
          Phoenix.LiveView.Socket.t(),
          {:ok, %{tx_bytes: String.t()}} | {:error, term()}
        ) :: Phoenix.LiveView.Socket.t()
  defp handle_tx_build_result(socket, {:ok, %{tx_bytes: tx_bytes}}),
    do: enter_signing(socket, tx_bytes)

  defp handle_tx_build_result(socket, {:error, :no_character_ref}),
    do: put_flash(socket, :error, "Active character reference unavailable")

  defp handle_tx_build_result(socket, {:error, :no_active_custodian}),
    do: put_flash(socket, :error, "No Tribe Custodian configured")

  defp handle_tx_build_result(socket, {:error, reason}) do
    put_flash(socket, :error, "Failed to build transaction: #{inspect(reason)}")
  end

  @spec enter_signing(Phoenix.LiveView.Socket.t(), String.t()) :: Phoenix.LiveView.Socket.t()
  defp enter_signing(socket, tx_bytes) do
    if localnet?(socket.assigns.world) do
      sign_and_submit_locally(socket, tx_bytes)
    else
      socket
      |> assign(
        page_state: :signing_tx,
        return_page_state: socket.assigns.page_state,
        pending_tx_bytes: tx_bytes
      )
      |> push_event("request_sign_transaction", %{"tx_bytes" => tx_bytes})
    end
  end

  @spec sign_and_submit_locally(Phoenix.LiveView.Socket.t(), String.t()) ::
          Phoenix.LiveView.Socket.t()
  defp sign_and_submit_locally(socket, kind_bytes) do
    opts = State.diplomacy_opts(socket)

    case Diplomacy.sign_and_submit_locally(kind_bytes, opts) do
      {:ok, %{digest: _digest}} ->
        socket
        |> put_flash(:info, "Transaction confirmed (local signing)")
        |> assign(page_state: socket.assigns.page_state, pending_tx_bytes: nil)
        |> State.maybe_refresh_after_submission()

      {:error, {:tx_failed, msg}} when is_binary(msg) ->
        if String.contains?(msg, "AlreadyRegistered") do
          socket
          |> put_flash(:info, "Custodian already exists — loading")
          |> assign(pending_tx_bytes: nil)
          |> State.discover_custodian_state()
          |> State.load_standings()
        else
          socket
          |> put_flash(:error, "Transaction failed: #{msg}")
          |> assign(pending_tx_bytes: nil)
        end

      {:error, reason} ->
        socket
        |> put_flash(:error, "Transaction failed: #{inspect(reason)}")
        |> assign(pending_tx_bytes: nil)
    end
  end
end
