defmodule SigilWeb.TribeHelpers do
  @moduledoc """
  Shared helpers for tribe-scoped LiveViews (TribeOverviewLive, DiplomacyLive).
  """

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

      %{active_character: %{tribe_id: user_tribe_id}} when user_tribe_id != nil ->
        case Integer.parse(tribe_id_str) do
          {tribe_id, ""} when tribe_id == user_tribe_id ->
            {:ok, tribe_id}

          _ ->
            {:error, :unauthorized}
        end

      %{active_character: _} ->
        {:error, :unauthorized}
    end
  end
end
