defmodule FrontierOSWeb.SessionController do
  @moduledoc """
  Starts and clears wallet-backed browser sessions.
  """

  use FrontierOSWeb, :controller

  alias FrontierOS.Accounts
  alias FrontierOS.Sui.ZkLoginVerifier
  alias FrontierOSWeb.CacheResolver

  @default_pubsub FrontierOS.PubSub

  @doc """
  Verifies a signed wallet challenge and stores the wallet in the browser session.
  """
  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create(conn, params) do
    with {:ok, auth_params} <- auth_params(params),
         %{} = tables <- resolve_cache_tables(conn),
         {:ok, verification} <- verify_wallet(auth_params, tables, conn),
         {:ok, _account} <- register_wallet(conn, verification.address, tables) do
      conn
      |> put_session(:wallet_address, verification.address)
      |> redirect(to: post_auth_path(verification))
    else
      {:error, :invalid_request} ->
        conn
        |> put_flash(:error, "Invalid authentication request")
        |> redirect(to: ~p"/")

      nil ->
        conn
        |> put_flash(:error, friendly_error(:cache_unavailable))
        |> redirect(to: ~p"/")

      {:error, reason} ->
        conn
        |> put_flash(:error, friendly_error(reason))
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

  @spec auth_params(map()) ::
          {:ok,
           %{address: String.t(), bytes: String.t(), signature: String.t(), nonce: String.t()}}
          | {:error, :invalid_request}
  defp auth_params(%{
         "wallet_address" => address,
         "bytes" => bytes,
         "signature" => signature,
         "nonce" => nonce
       })
       when is_binary(address) and is_binary(bytes) and is_binary(signature) and is_binary(nonce) do
    {:ok, %{address: address, bytes: bytes, signature: signature, nonce: nonce}}
  end

  defp auth_params(_params), do: {:error, :invalid_request}

  @spec verify_wallet(map(), map(), Plug.Conn.t()) ::
          {:ok, ZkLoginVerifier.verification_result()}
          | {:error,
             :invalid_nonce
             | :nonce_expired
             | :address_mismatch
             | :bytes_mismatch
             | :signature_invalid}
          | {:error, {:verification_failed, term()}}
  defp verify_wallet(auth_params, tables, conn) do
    ZkLoginVerifier.verify_and_consume(auth_params,
      tables: tables,
      req_options: session_req_options(conn)
    )
  end

  defp register_wallet(conn, wallet_address, tables) do
    Accounts.register_wallet(wallet_address,
      tables: tables,
      pubsub: session_pubsub(conn),
      req_options: session_req_options(conn)
    )
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

  @spec session_req_options(Plug.Conn.t()) :: keyword()
  defp session_req_options(conn) do
    get_session(conn, :req_options) || get_session(conn, "req_options") || []
  end

  @spec post_auth_path(ZkLoginVerifier.verification_result()) :: String.t()
  defp post_auth_path(%{item_id: item_id}) when is_binary(item_id), do: ~p"/assembly/#{item_id}"
  defp post_auth_path(_verification), do: ~p"/"

  @spec friendly_error(term()) :: String.t()
  defp friendly_error(:timeout), do: "timeout reaching the chain service — please try again"
  defp friendly_error(:cache_unavailable), do: "cache is starting up — please try again shortly"
  defp friendly_error(:invalid_request), do: "Invalid authentication request"
  defp friendly_error(:invalid_nonce), do: "Authentication expired — please try again"
  defp friendly_error(:nonce_expired), do: "Authentication expired — please try again"
  defp friendly_error(:address_mismatch), do: "Authentication failed — address mismatch"
  defp friendly_error(:bytes_mismatch), do: "Authentication failed — message tampered"
  defp friendly_error(:signature_invalid), do: "Wallet signature could not be verified"
  defp friendly_error({:verification_failed, reason}), do: friendly_error(reason)

  defp friendly_error({:graphql_errors, errors}) when is_list(errors) do
    "chain query failed — please try again"
  end

  defp friendly_error(reason) when is_atom(reason), do: to_string(reason)
end
