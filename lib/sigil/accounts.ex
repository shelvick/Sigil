defmodule Sigil.Accounts do
  @moduledoc """
  Wallet registration and account cache access backed by ETS.
  """

  alias Sigil.Cache
  alias Sigil.Sui.Client
  alias Sigil.Sui.Types.Character
  alias Sigil.Worlds

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
          | {:world, Worlds.world_name()}
          | {:active_worlds, [Worlds.world_name()]}

  @type options() :: [option()]

  @doc "Registers a wallet, caches its characters, and broadcasts the result."
  @spec register_wallet(String.t(), options()) ::
          {:ok, Account.t()} | {:error, :invalid_address | Client.error_reason()}
  def register_wallet(address, opts) when is_binary(address) and is_list(opts) do
    with :ok <- validate_address(address),
         canonical = String.downcase(address),
         {:ok, account, characters} <- load_account(canonical, opts) do
      cache_account(opts, canonical, account, characters)
      broadcast(Keyword.get(opts, :pubsub, Sigil.PubSub), {:account_registered, account}, opts)
      {:ok, account}
    end
  end

  @doc "Detects a wallet's world by probing active worlds for matching Characters."
  @spec detect_world(String.t(), options()) :: Worlds.world_name()
  def detect_world(address, opts) when is_binary(address) and is_list(opts) do
    case configured_active_worlds(opts) do
      [single_world] ->
        single_world

      active_worlds ->
        canonical = String.downcase(address)
        req_options = Keyword.get(opts, :req_options, [])

        Enum.find(active_worlds, world(opts), fn world_name ->
          request_opts = request_opts_for_world(req_options, world_name, active_worlds)

          case fetch_all_characters(world_name, nil, request_opts, []) do
            {:ok, characters} -> Enum.any?(characters, &(&1.character_address == canonical))
            {:error, _reason} -> false
          end
        end)
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

  @doc "Resolves the active character for an account and optional session selection."
  @spec active_character(Account.t(), String.t() | nil) :: Character.t() | nil
  def active_character(%Account{characters: []}, _character_id), do: nil
  def active_character(%Account{characters: [first | _rest]}, nil), do: first

  def active_character(%Account{characters: characters}, character_id)
      when is_binary(character_id) do
    Enum.find(characters, List.first(characters), &(&1.id == character_id))
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
          broadcast(Keyword.get(opts, :pubsub, Sigil.PubSub), {:account_updated, account}, opts)
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
    selected_world = world(opts)
    request_opts = request_opts_for_world(req_options, selected_world, [selected_world])

    with {:ok, all_characters} <- fetch_all_characters(selected_world, nil, request_opts, []) do
      characters =
        all_characters
        |> Enum.filter(&(&1.character_address == address))

      account = %Account{address: address, characters: characters, tribe_id: tribe_id(characters)}
      {:ok, account, characters}
    end
  end

  @spec fetch_all_characters(
          Worlds.world_name(),
          String.t() | nil,
          Client.request_opts(),
          [Character.t()]
        ) ::
          {:ok, [Character.t()]} | {:error, Client.error_reason()}
  defp fetch_all_characters(world_name, cursor, req_options, acc)
       when is_binary(world_name) and is_list(req_options) and is_list(acc) do
    filters =
      case cursor do
        nil -> [type: character_type_string(world_name)]
        c -> [type: character_type_string(world_name), cursor: c]
      end

    with {:ok, %{data: characters_json, has_next_page: has_next_page, end_cursor: end_cursor}} <-
           @sui_client.get_objects(filters, req_options) do
      characters = Enum.map(characters_json, &Character.from_json/1)
      acc = Enum.reverse(characters) ++ acc

      if has_next_page and is_binary(end_cursor) do
        fetch_all_characters(world_name, end_cursor, req_options, acc)
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

  @spec broadcast(atom() | module(), term(), options()) :: :ok | {:error, term()}
  defp broadcast(pubsub, event, opts) do
    Phoenix.PubSub.broadcast(pubsub, Worlds.topic(world(opts), @accounts_topic), event)
  end

  @spec character_type_string(Worlds.world_name()) :: String.t()
  defp character_type_string(world_name) when is_binary(world_name) do
    "#{world_package_id(world_name)}::character::Character"
  end

  @spec world_package_id(Worlds.world_name()) :: String.t()
  defp world_package_id(world_name) when is_binary(world_name) do
    Worlds.package_id(world_name)
  end

  @spec world(options()) :: Worlds.world_name()
  defp world(opts) when is_list(opts) do
    Keyword.get(opts, :world, Worlds.default_world())
  end

  @spec configured_active_worlds(options()) :: [Worlds.world_name()]
  defp configured_active_worlds(opts) when is_list(opts) do
    configured_worlds = Application.fetch_env!(:sigil, :eve_worlds)
    known_worlds = Map.keys(configured_worlds)

    worlds =
      case Keyword.get(opts, :active_worlds, Worlds.active_worlds()) do
        configured when is_list(configured) -> configured
        _other -> [world(opts)]
      end

    filtered_worlds =
      worlds
      |> Enum.filter(&is_binary/1)
      |> Enum.uniq()
      |> Enum.filter(&(&1 in known_worlds))

    case filtered_worlds do
      [] ->
        resolved_world = world(opts)

        if resolved_world in known_worlds do
          [resolved_world]
        else
          [Worlds.default_world()]
        end

      _non_empty ->
        filtered_worlds
    end
  end

  @spec request_opts_for_world(Client.request_opts(), Worlds.world_name(), [Worlds.world_name()]) ::
          Client.request_opts()
  defp request_opts_for_world(req_options, world_name, active_worlds)
       when is_list(req_options) and is_binary(world_name) and is_list(active_worlds) do
    # Only inject :world when probing multiple worlds; preserve legacy opts shape
    # in single-world mode so existing Hammox request_opt contracts stay valid.
    if length(active_worlds) > 1 do
      Keyword.put(req_options, :world, world_name)
    else
      req_options
    end
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
