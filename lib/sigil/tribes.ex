defmodule Sigil.Tribes do
  @moduledoc """
  Tribe member discovery and cached tribe aggregation backed by ETS.
  """

  alias Sigil.Accounts.Account
  alias Sigil.Assemblies
  alias Sigil.Cache
  alias Sigil.Sui.Client
  alias Sigil.Sui.Types.Character

  @sui_client Application.compile_env!(:sigil, :sui_client)
  @tribes_topic "tribes"

  defmodule Tribe do
    @moduledoc """
    Cached tribe state for a discovered tribe.
    """

    alias Sigil.Tribes.TribeMember

    @enforce_keys [:tribe_id, :members, :discovered_at]
    defstruct [:tribe_id, :members, :discovered_at]

    @type t :: %__MODULE__{
            tribe_id: non_neg_integer(),
            members: [TribeMember.t()],
            discovered_at: DateTime.t()
          }
  end

  defmodule TribeMember do
    @moduledoc """
    Discovered member state for a tribe character.
    """

    @enforce_keys [:character_id, :character_name, :character_address, :tribe_id, :connected]
    defstruct [
      :character_id,
      :character_name,
      :character_address,
      :tribe_id,
      :connected,
      :wallet_address
    ]

    @type t :: %__MODULE__{
            character_id: String.t(),
            character_name: String.t() | nil,
            character_address: String.t(),
            tribe_id: non_neg_integer(),
            connected: boolean(),
            wallet_address: String.t() | nil
          }
  end

  @typedoc "ETS tables required by the tribes context."
  @type tables() :: %{
          tribes: Cache.table_id(),
          accounts: Cache.table_id(),
          assemblies: Cache.table_id()
        }

  @typedoc "Assembly types returned by tribe assembly aggregation."
  @type assembly() :: Assemblies.assembly()

  @typedoc "Options accepted by the tribes context functions."
  @type option() ::
          {:tables, tables()}
          | {:pubsub, atom() | module()}
          | {:req_options, Client.request_opts()}

  @type options() :: [option()]

  @doc "Discovers tribe members from chain, caches the tribe, and broadcasts the result."
  @spec discover_members(non_neg_integer(), options()) ::
          {:ok, Tribe.t()} | {:error, Client.error_reason()}
  def discover_members(tribe_id, opts)
      when is_integer(tribe_id) and tribe_id >= 0 and is_list(opts) do
    req_options = Keyword.get(opts, :req_options, [])

    with {:ok, characters} <- fetch_all_characters(req_options) do
      connected_accounts = connected_accounts(tribe_id, opts)

      members =
        characters
        |> Enum.filter(&(&1.tribe_id == tribe_id))
        |> Enum.map(&to_member(&1, connected_accounts))

      tribe = %Tribe{tribe_id: tribe_id, members: members, discovered_at: DateTime.utc_now()}

      Cache.put(tribe_table(opts), tribe_id, tribe)
      broadcast(Keyword.get(opts, :pubsub, Sigil.PubSub), {:tribe_discovered, tribe})

      {:ok, tribe}
    end
  end

  @doc "Returns cached tribe members for a tribe id."
  @spec list_members(non_neg_integer(), options()) :: [TribeMember.t()]
  def list_members(tribe_id, opts)
      when is_integer(tribe_id) and tribe_id >= 0 and is_list(opts) do
    case get_tribe(tribe_id, opts) do
      %Tribe{members: members} -> members
      nil -> []
    end
  end

  @doc "Returns the cached tribe struct for a tribe id."
  @spec get_tribe(non_neg_integer(), options()) :: Tribe.t() | nil
  def get_tribe(tribe_id, opts) when is_integer(tribe_id) and tribe_id >= 0 and is_list(opts) do
    Cache.get(tribe_table(opts), tribe_id)
  end

  @doc "Returns cached assemblies grouped by connected tribe member."
  @spec list_tribe_assemblies(non_neg_integer(), options()) :: [{TribeMember.t(), [assembly()]}]
  def list_tribe_assemblies(tribe_id, opts)
      when is_integer(tribe_id) and tribe_id >= 0 and is_list(opts) do
    case get_tribe(tribe_id, opts) do
      %Tribe{members: members} ->
        members
        |> Enum.filter(& &1.connected)
        |> Enum.map(fn %TribeMember{wallet_address: wallet_address} = member ->
          {member, assemblies_for_wallet(wallet_address, opts)}
        end)

      nil ->
        []
    end
  end

  @spec fetch_all_characters(Client.request_opts()) ::
          {:ok, [Character.t()]} | {:error, Client.error_reason()}
  defp fetch_all_characters(req_options) do
    fetch_characters_acc(nil, req_options, [])
  end

  @spec fetch_characters_acc(String.t() | nil, Client.request_opts(), [Character.t()]) ::
          {:ok, [Character.t()]} | {:error, Client.error_reason()}
  defp fetch_characters_acc(cursor, req_options, acc) do
    filters = character_filters(cursor)

    with {:ok, %{data: characters_json, has_next_page: has_next_page, end_cursor: end_cursor}} <-
           @sui_client.get_objects(filters, req_options) do
      characters = Enum.map(characters_json, &Character.from_json/1)
      acc = Enum.reverse(characters) ++ acc

      if has_next_page and is_binary(end_cursor) do
        fetch_characters_acc(end_cursor, req_options, acc)
      else
        {:ok, Enum.reverse(acc)}
      end
    end
  end

  @spec connected_accounts(non_neg_integer(), options()) :: %{String.t() => String.t()}
  defp connected_accounts(tribe_id, opts) do
    opts
    |> account_table()
    |> Cache.all()
    |> Enum.reduce(%{}, fn
      %Account{address: address, tribe_id: ^tribe_id, characters: characters}, acc ->
        Enum.reduce(characters, acc, fn %Character{id: character_id}, character_acc ->
          Map.put(character_acc, character_id, address)
        end)

      %Account{}, acc ->
        acc
    end)
  end

  @spec to_member(Character.t(), %{String.t() => String.t()}) :: TribeMember.t()
  defp to_member(%Character{} = character, connected_accounts) do
    wallet_address = Map.get(connected_accounts, character.id)

    %TribeMember{
      character_id: character.id,
      character_name: character_name(character),
      character_address: character.character_address,
      tribe_id: character.tribe_id,
      connected: not is_nil(wallet_address),
      wallet_address: wallet_address
    }
  end

  @spec character_name(Character.t()) :: String.t() | nil
  defp character_name(%Character{metadata: %{name: name}}), do: name
  defp character_name(%Character{metadata: nil}), do: nil

  @spec assemblies_for_wallet(String.t(), options()) :: [assembly()]
  defp assemblies_for_wallet(wallet_address, opts) do
    opts
    |> assemblies_table()
    |> Cache.match({:_, {wallet_address, :_}})
    |> Enum.map(fn {_assembly_id, {^wallet_address, assembly}} -> assembly end)
    |> Enum.sort_by(& &1.id)
  end

  @spec tribe_table(options()) :: Cache.table_id()
  defp tribe_table(opts) do
    opts |> Keyword.fetch!(:tables) |> Map.fetch!(:tribes)
  end

  @spec account_table(options()) :: Cache.table_id()
  defp account_table(opts) do
    opts |> Keyword.fetch!(:tables) |> Map.fetch!(:accounts)
  end

  @spec assemblies_table(options()) :: Cache.table_id()
  defp assemblies_table(opts) do
    opts |> Keyword.fetch!(:tables) |> Map.fetch!(:assemblies)
  end

  @spec broadcast(atom() | module(), term()) :: :ok | {:error, term()}
  defp broadcast(pubsub, event) do
    Phoenix.PubSub.broadcast(pubsub, @tribes_topic, event)
  end

  @spec character_filters(String.t() | nil) :: Client.object_filter()
  defp character_filters(nil), do: [type: character_type_string()]
  defp character_filters(cursor), do: [type: character_type_string(), cursor: cursor]

  @spec character_type_string() :: String.t()
  defp character_type_string do
    "#{world_package_id()}::character::Character"
  end

  @spec world_package_id() :: String.t()
  defp world_package_id do
    world = Application.fetch_env!(:sigil, :eve_world)
    worlds = Application.fetch_env!(:sigil, :eve_worlds)
    Map.fetch!(worlds, world)
  end
end
