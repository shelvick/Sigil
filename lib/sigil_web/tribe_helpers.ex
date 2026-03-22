defmodule SigilWeb.TribeHelpers do
  @moduledoc """
  Shared helpers for tribe-scoped LiveViews and components.
  """

  alias Sigil.Diplomacy

  @doc """
  Authorizes a tribe_id URL parameter against the current session.

  Returns `{:ok, tribe_id}` when the parsed integer matches the user's tribe,
  `{:error, :unauthenticated}` when no account is present, or
  `{:error, :unauthorized}` for any mismatch.
  """
  @spec authorize_tribe(String.t(), Phoenix.LiveView.Socket.t()) ::
          {:ok, non_neg_integer()} | {:error, :unauthorized | :unauthenticated}
  def authorize_tribe(tribe_id_str, socket) do
    case socket.assigns do
      %{current_account: nil} ->
        {:error, :unauthenticated}

      %{current_account: current_account, active_character: active_character} ->
        case resolve_tribe_id(active_character) do
          active_tribe_id when is_integer(active_tribe_id) ->
            authorize_tribe_id(tribe_id_str, active_tribe_id)

          nil when is_nil(active_character) ->
            case resolve_tribe_id(current_account) do
              nil -> {:error, :unauthorized}
              account_tribe_id -> authorize_tribe_id(tribe_id_str, account_tribe_id)
            end

          nil ->
            {:error, :unauthorized}
        end
    end
  end

  defp authorize_tribe_id(tribe_id_str, user_tribe_id) when is_integer(user_tribe_id) do
    case Integer.parse(tribe_id_str) do
      {tribe_id, ""} when tribe_id == user_tribe_id ->
        {:ok, tribe_id}

      _ ->
        {:error, :unauthorized}
    end
  end

  @doc """
  Returns the display label for a standing atom.
  """
  @spec standing_display(Diplomacy.standing_atom()) :: String.t()
  def standing_display(:hostile), do: "Hostile"
  def standing_display(:unfriendly), do: "Unfriendly"
  def standing_display(:neutral), do: "Neutral"
  def standing_display(:friendly), do: "Friendly"
  def standing_display(:allied), do: "Allied"

  @doc """
  Returns the NBSI or NRDS policy label for a standing.
  """
  @spec nbsi_nrds_label(Diplomacy.standing_atom()) :: String.t()
  def nbsi_nrds_label(:hostile), do: "NBSI"
  def nbsi_nrds_label(:unfriendly), do: "NBSI"
  def nbsi_nrds_label(:neutral), do: "NRDS"
  def nbsi_nrds_label(:friendly), do: "NRDS"
  def nbsi_nrds_label(:allied), do: "NRDS"

  defp resolve_tribe_id(%{tribe_id: tribe_id}) when is_integer(tribe_id) and tribe_id > 0,
    do: tribe_id

  defp resolve_tribe_id(_value), do: nil
end
