defmodule FrontierOSWeb.SessionController do
  @moduledoc """
  Starts and clears wallet-backed browser sessions.
  """

  use FrontierOSWeb, :controller

  alias FrontierOS.Accounts
  alias FrontierOSWeb.CacheResolver

  @default_pubsub FrontierOS.PubSub

  @doc """
  Registers a wallet address and stores it in the browser session.
  """
  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create(conn, params) do
    case Map.get(params, "wallet_address") do
      wallet_address when is_binary(wallet_address) ->
        case register_wallet(conn, wallet_address) do
          {:ok, _account} ->
            conn
            |> put_session(:wallet_address, wallet_address)
            |> redirect(to: ~p"/")

          {:error, :invalid_address} ->
            conn
            |> put_flash(:error, "Invalid wallet address")
            |> redirect(to: ~p"/")

          {:error, reason} ->
            conn
            |> put_flash(:error, "Unable to start wallet session: #{friendly_error(reason)}")
            |> redirect(to: ~p"/")
        end

      _other ->
        conn
        |> put_flash(:error, "Invalid wallet address")
        |> redirect(to: ~p"/")
    end
  end

  @doc """
  Clears the current wallet session.
  """
  @spec delete(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def delete(conn, _params) do
    conn
    |> clear_session()
    |> configure_session(drop: true)
    |> redirect(to: ~p"/")
  end

  @spec register_wallet(Plug.Conn.t(), String.t()) ::
          {:ok, FrontierOS.Accounts.Account.t()} | {:error, :invalid_address | term()}
  defp register_wallet(conn, wallet_address) do
    with %{} = tables <- resolve_cache_tables(conn) do
      Accounts.register_wallet(wallet_address,
        tables: tables,
        pubsub: session_pubsub(conn)
      )
    else
      nil -> {:error, :cache_unavailable}
    end
  end

  @spec resolve_cache_tables(Plug.Conn.t()) :: map() | nil
  defp resolve_cache_tables(conn) do
    session_cache_tables(conn) || CacheResolver.application_cache_tables()
  end

  @spec session_cache_tables(Plug.Conn.t()) :: map() | nil
  defp session_cache_tables(conn) do
    get_session(conn, :cache_tables) || get_session(conn, "cache_tables")
  end

  @spec session_pubsub(Plug.Conn.t()) :: atom() | module()
  defp session_pubsub(conn) do
    get_session(conn, :pubsub) || get_session(conn, "pubsub") || @default_pubsub
  end

  @spec friendly_error(term()) :: String.t()
  defp friendly_error(:timeout), do: "timeout reaching the chain service — please try again"
  defp friendly_error(:cache_unavailable), do: "cache is starting up — please try again shortly"

  defp friendly_error({:graphql_errors, errors}) when is_list(errors) do
    "chain query failed — please try again"
  end

  defp friendly_error(reason) when is_atom(reason), do: to_string(reason)
end
