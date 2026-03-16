defmodule SigilWeb.WalletSession do
  @moduledoc """
  Loads session-backed wallet resources into LiveView assigns.

  Reads the wallet address from the Phoenix cookie session, resolves the ETS
  cache tables (via test injection or the supervised `Sigil.Cache`), and
  assigns `:current_account`, `:cache_tables`, and `:pubsub` to the socket so
  every LiveView in the `:wallet` live_session has consistent dependencies.
  """

  alias Sigil.Accounts
  alias SigilWeb.CacheResolver

  @default_pubsub Sigil.PubSub

  @doc """
  Assigns the current account, cache tables, and pubsub dependency for a LiveView session.

  Invoked by the `:wallet` `live_session` on_mount hook.  The second argument
  is ignored — all relevant state comes from the Phoenix cookie session.
  """
  @spec on_mount(atom(), map(), map(), Phoenix.LiveView.Socket.t()) ::
          {:cont, Phoenix.LiveView.Socket.t()}
  def on_mount(_arg, _params, session, socket) do
    cache_tables = resolve_cache_tables(session)
    pubsub = Map.get(session, "pubsub", @default_pubsub)
    current_account = fetch_current_account(Map.get(session, "wallet_address"), cache_tables)

    {:cont,
     Phoenix.Component.assign(socket,
       current_account: current_account,
       cache_tables: cache_tables,
       pubsub: pubsub
     )}
  end

  @spec fetch_current_account(String.t() | nil, map() | nil) ::
          Sigil.Accounts.Account.t() | nil
  defp fetch_current_account(wallet_address, cache_tables)
       when is_binary(wallet_address) and is_map(cache_tables) do
    case Accounts.get_account(wallet_address, tables: cache_tables) do
      {:ok, account} -> account
      {:error, :not_found} -> nil
    end
  end

  defp fetch_current_account(_wallet_address, _cache_tables), do: nil

  @spec resolve_cache_tables(map()) :: map() | nil
  defp resolve_cache_tables(session) do
    Map.get(session, "cache_tables") || CacheResolver.application_cache_tables()
  end
end
