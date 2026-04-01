defmodule SigilWeb.WalletSession do
  @moduledoc """
  Loads session-backed wallet resources into LiveView assigns.

  Reads the wallet address from the Phoenix cookie session, resolves the ETS
  cache tables (via test injection or the supervised `Sigil.Cache`), and
  assigns `:current_account`, `:active_character`, `:cache_tables`, `:pubsub`,
  and `:world` to the socket so every LiveView in the `:wallet` live_session
  has consistent dependencies.
  """

  alias Sigil.Accounts
  alias Sigil.Worlds
  alias SigilWeb.CacheResolver

  @default_pubsub Sigil.PubSub

  @doc """
  Assigns account, dependency, and world context for a LiveView session.

  Invoked by the `:wallet_session` `live_session` on_mount hook. The second
  argument is ignored — all relevant state comes from the Phoenix cookie
  session.
  """
  @spec on_mount(atom(), map(), map(), Phoenix.LiveView.Socket.t()) ::
          {:cont, Phoenix.LiveView.Socket.t()}
  def on_mount(_arg, _params, session, socket) do
    world = Map.get(session, "world") || Worlds.default_world()
    cache_tables = resolve_cache_tables(session, world)
    pubsub = Map.get(session, "pubsub", @default_pubsub)
    static_data = resolve_static_data(session)
    current_account = fetch_current_account(Map.get(session, "wallet_address"), cache_tables)

    active_character =
      resolve_active_character(current_account, Map.get(session, "active_character_id"))

    {:cont,
     Phoenix.Component.assign(socket,
       current_account: current_account,
       active_character: active_character,
       cache_tables: cache_tables,
       pubsub: pubsub,
       static_data: static_data,
       world: world
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

  @spec resolve_active_character(Sigil.Accounts.Account.t() | nil, String.t() | nil) ::
          Sigil.Sui.Types.Character.t() | nil
  defp resolve_active_character(%Accounts.Account{} = account, character_id) do
    Accounts.active_character(account, character_id)
  end

  defp resolve_active_character(nil, _character_id), do: nil

  @spec resolve_cache_tables(map(), Worlds.world_name()) :: map() | nil
  defp resolve_cache_tables(session, world) do
    Map.get(session, "cache_tables") || CacheResolver.application_cache_tables(world)
  end

  @spec resolve_static_data(map()) :: pid() | nil
  defp resolve_static_data(session) do
    Map.get(session, "static_data") || CacheResolver.application_static_data()
  end
end
