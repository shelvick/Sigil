defmodule Sigil.Accounts do
  @moduledoc """
  Wallet registration and account cache access backed by ETS.
  """

  alias Sigil.Cache
  alias Sigil.Sui.Client
  alias Sigil.Sui.Types.Character

  @sui_client Application.compile_env!(:sigil, :sui_client)
  @accounts_topic "accounts"

  defmodule Account do
    @moduledoc """
    Cached account state for a wallet address.
    """

    alias Sigil.Sui.Types.Character

    @enforce_keys [:address, :characters, :tribe_id]
    defstruct [:address, :characters, :tribe_id]

    @type t :: %__MODULE__{
            address: String.t(),
            characters: [Character.t()],
            tribe_id: non_neg_integer() | nil
          }
  end

  @typedoc "ETS tables required by the accounts context."
  @type tables() :: %{accounts: Cache.table_id(), characters: Cache.table_id()}

  @typedoc "Options accepted by the accounts context functions."
  @type option() ::
          {:tables, tables()}
          | {:pubsub, atom() | module()}
          | {:req_options, Client.request_opts()}

  @type options() :: [option()]

  @doc "Registers a wallet, caches its characters, and broadcasts the result."
  @spec register_wallet(String.t(), options()) ::
          {:ok, Account.t()} | {:error, :invalid_address | Client.error_reason()}
  def register_wallet(address, opts) when is_binary(address) and is_list(opts) do
    with :ok <- validate_address(address),
         canonical = String.downcase(address),
         {:ok, account, characters} <- load_account(canonical, opts) do
      cache_account(opts, canonical, account, characters)
      broadcast(Keyword.get(opts, :pubsub, Sigil.PubSub), {:account_registered, account})
      {:ok, account}
    end
  end

  @doc "Returns a cached account for a wallet address."
  @spec get_account(String.t(), options()) :: {:ok, Account.t()} | {:error, :not_found}
  def get_account(address, opts) when is_binary(address) and is_list(opts) do
    table = account_table(opts)
    canonical = String.downcase(address)

    case Cache.get(table, canonical) do
      %Account{} = account -> {:ok, account}
      nil -> {:error, :not_found}
    end
  end

  @doc "Refreshes a registered wallet from chain and broadcasts the updated account."
  @spec sync_from_chain(String.t(), options()) ::
          {:ok, Account.t()} | {:error, :not_found | Client.error_reason()}
  def sync_from_chain(address, opts) when is_binary(address) and is_list(opts) do
    canonical = String.downcase(address)

    case get_account(canonical, tables: Keyword.fetch!(opts, :tables)) do
      {:ok, _account} ->
        with {:ok, account, characters} <- load_account(canonical, opts) do
          cache_account(opts, canonical, account, characters)
          broadcast(Keyword.get(opts, :pubsub, Sigil.PubSub), {:account_updated, account})
          {:ok, account}
        end

      {:error, :not_found} ->
        {:error, :not_found}
    end
  end

  @spec load_account(String.t(), options()) ::
          {:ok, Account.t(), [Character.t()]} | {:error, Client.error_reason()}
  defp load_account(address, opts) do
    req_options = Keyword.get(opts, :req_options, [])

    with {:ok, all_characters} <- fetch_all_characters(nil, req_options, []) do
      characters =
        all_characters
        |> Enum.filter(&(&1.character_address == address))

      account = %Account{address: address, characters: characters, tribe_id: tribe_id(characters)}
      {:ok, account, characters}
    end
  end

  @spec fetch_all_characters(String.t() | nil, Client.request_opts(), [Character.t()]) ::
          {:ok, [Character.t()]} | {:error, Client.error_reason()}
  defp fetch_all_characters(cursor, req_options, acc) do
    filters =
      case cursor do
        nil -> [type: character_type_string()]
        c -> [type: character_type_string(), cursor: c]
      end

    with {:ok, %{data: characters_json, has_next_page: has_next_page, end_cursor: end_cursor}} <-
           @sui_client.get_objects(filters, req_options) do
      characters = Enum.map(characters_json, &Character.from_json/1)
      acc = Enum.reverse(characters) ++ acc

      if has_next_page and is_binary(end_cursor) do
        fetch_all_characters(end_cursor, req_options, acc)
      else
        {:ok, Enum.reverse(acc)}
      end
    end
  end

  @spec cache_account(options(), String.t(), Account.t(), [Character.t()]) :: :ok
  defp cache_account(opts, address, account, characters) do
    Cache.put(account_table(opts), address, account)
    Cache.put(character_table(opts), address, characters)
  end

  @spec account_table(options()) :: Cache.table_id()
  defp account_table(opts) do
    opts |> Keyword.fetch!(:tables) |> Map.fetch!(:accounts)
  end

  @spec character_table(options()) :: Cache.table_id()
  defp character_table(opts) do
    opts |> Keyword.fetch!(:tables) |> Map.fetch!(:characters)
  end

  @spec broadcast(atom() | module(), term()) :: :ok | {:error, term()}
  defp broadcast(pubsub, event) do
    Phoenix.PubSub.broadcast(pubsub, @accounts_topic, event)
  end

  @spec character_type_string() :: String.t()
  defp character_type_string do
    "#{world_package_id()}::character::Character"
  end

  @spec world_package_id() :: String.t()
  defp world_package_id do
    world = Application.fetch_env!(:sigil, :eve_world)
    worlds = Application.fetch_env!(:sigil, :eve_worlds)
    %{package_id: package_id} = Map.fetch!(worlds, world)
    package_id
  end

  @spec tribe_id([Character.t()]) :: non_neg_integer() | nil
  defp tribe_id([%Character{tribe_id: tribe_id} | _rest]), do: tribe_id
  defp tribe_id([]), do: nil

  @spec validate_address(String.t()) :: :ok | {:error, :invalid_address}
  defp validate_address(address) do
    if String.match?(address, ~r/\A0x[0-9a-fA-F]{64}\z/) do
      :ok
    else
      {:error, :invalid_address}
    end
  end
end
