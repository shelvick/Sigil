defmodule Sigil.Assemblies do
  @moduledoc """
  Assembly discovery and cache access backed by ETS.
  """

  alias Sigil.Cache
  alias Sigil.Sui.{Client, TransactionBuilder, TxGateExtension}
  alias Sigil.Sui.Types.{Assembly, Gate, NetworkNode, StorageUnit, Turret}

  @sui_client Application.compile_env!(:sigil, :sui_client)

  @typedoc "ETS tables required by the assemblies context."
  @type tables() :: %{assemblies: Cache.table_id()}

  @typedoc "Parsed assembly types cached by the context."
  @type assembly() :: Assembly.t() | Gate.t() | NetworkNode.t() | StorageUnit.t() | Turret.t()

  @typedoc "Options accepted by the assemblies context functions."
  @type option() ::
          {:tables, tables()}
          | {:pubsub, atom() | module()}
          | {:req_options, Client.request_opts()}
          | {:character_ids, [String.t()]}

  @type options() :: [option()]

  @doc """
  Discovers assemblies for a wallet, caches them, and broadcasts the result.

  Requires `:character_ids` — a list of Character object addresses whose
  OwnerCaps will be queried. On-chain, OwnerCaps are held by the Character
  object, not the wallet. The `owner` param is used only for caching and
  PubSub topic naming.
  """
  @spec discover_for_owner(String.t(), options()) ::
          {:ok, [assembly()]} | {:error, Client.error_reason()}
  def discover_for_owner(owner, opts) when is_binary(owner) and is_list(opts) do
    req_options = Keyword.get(opts, :req_options, [])
    query_owners = Keyword.fetch!(opts, :character_ids)

    with {:ok, owner_caps} <- fetch_all_owner_caps(query_owners, req_options) do
      assemblies =
        owner_caps
        |> Enum.map(&Map.fetch!(&1, "authorized_object_id"))
        |> Enum.reduce([], fn assembly_id, acc ->
          case fetch_assembly(assembly_id, req_options) do
            {:ok, assembly} ->
              cache_assembly(opts, owner, assembly)
              [assembly | acc]

            :skip ->
              acc

            {:error, _reason} ->
              acc
          end
        end)
        |> Enum.reverse()

      broadcast(
        Keyword.get(opts, :pubsub, Sigil.PubSub),
        owner_topic(owner),
        {:assemblies_discovered, assemblies}
      )

      {:ok, assemblies}
    end
  end

  @doc "Returns cached assemblies for a single owner."
  @spec list_for_owner(String.t(), options()) :: [assembly()]
  def list_for_owner(owner, opts) when is_binary(owner) and is_list(opts) do
    opts
    |> assembly_table()
    |> Cache.match({:_, {owner, :_}})
    |> Enum.map(fn {_assembly_id, {^owner, assembly}} -> assembly end)
  end

  @doc "Returns a cached assembly by id."
  @spec get_assembly(String.t(), options()) :: {:ok, assembly()} | {:error, :not_found}
  def get_assembly(assembly_id, opts) when is_binary(assembly_id) and is_list(opts) do
    table = assembly_table(opts)

    case Cache.get(table, assembly_id) do
      {_owner, assembly} -> {:ok, assembly}
      nil -> {:error, :not_found}
    end
  end

  @doc "Fetches an assembly from chain and caches it. Used as fallback when not in ETS."
  @spec fetch_and_cache(String.t(), options()) ::
          {:ok, assembly()} | {:error, :not_found | Client.error_reason()}
  def fetch_and_cache(assembly_id, opts) when is_binary(assembly_id) and is_list(opts) do
    req_options = Keyword.get(opts, :req_options, [])

    case fetch_assembly(assembly_id, req_options) do
      {:ok, assembly} ->
        cache_assembly(opts, "unknown", assembly)
        {:ok, assembly}

      :skip ->
        {:error, :not_found}

      {:error, _reason} = error ->
        error
    end
  end

  @doc "Returns whether the cached assembly belongs to the given owner."
  @spec assembly_owned_by?(String.t(), String.t(), options()) :: boolean()
  def assembly_owned_by?(assembly_id, owner, opts)
      when is_binary(assembly_id) and is_binary(owner) and is_list(opts) do
    case Cache.get(assembly_table(opts), assembly_id) do
      {^owner, _assembly} -> true
      _other -> false
    end
  end

  @doc "Refreshes a cached assembly from chain and broadcasts the updated value."
  @spec sync_assembly(String.t(), options()) ::
          {:ok, assembly()} | {:error, :not_found | Client.error_reason()}
  def sync_assembly(assembly_id, opts) when is_binary(assembly_id) and is_list(opts) do
    req_options = Keyword.get(opts, :req_options, [])

    table = assembly_table(opts)

    case Cache.get(table, assembly_id) do
      {owner, _cached_assembly} ->
        case fetch_assembly(assembly_id, req_options) do
          {:ok, assembly} ->
            cache_assembly(opts, owner, assembly)

            broadcast(
              Keyword.get(opts, :pubsub, Sigil.PubSub),
              assembly_topic(assembly_id),
              {:assembly_updated, assembly}
            )

            {:ok, assembly}

          :skip ->
            Cache.delete(table, assembly_id)
            {:error, :not_found}

          {:error, _reason} = error ->
            error
        end

      nil ->
        {:error, :not_found}
    end
  end

  @doc "Builds unsigned transaction bytes for gate extension authorization."
  @spec build_authorize_gate_extension_tx(String.t(), String.t(), options()) ::
          {:ok, %{tx_bytes: String.t()}}
          | {:error, :not_found | :not_a_gate | Client.error_reason()}
  def build_authorize_gate_extension_tx(gate_id, character_id, opts)
      when is_binary(gate_id) and is_binary(character_id) and is_list(opts) do
    req_options = Keyword.get(opts, :req_options, [])

    with {:ok, gate} <- fetch_cached_gate(gate_id, opts),
         {:ok, %{ref: owner_cap_ref}} <-
           @sui_client.get_object_with_ref(gate.owner_cap_id, req_options),
         {:ok, %{json: character_json}} <-
           @sui_client.get_object_with_ref(character_id, req_options),
         {:ok, %{json: gate_json}} <- @sui_client.get_object_with_ref(gate_id, req_options) do
      tx_bytes =
        %{
          object_id: hex_to_bytes(gate_id),
          initial_shared_version: parse_shared_version!(gate_json)
        }
        |> TxGateExtension.build_authorize_extension(
          owner_cap_ref,
          %{
            object_id: hex_to_bytes(character_id),
            initial_shared_version: parse_shared_version!(character_json)
          }
        )
        |> TransactionBuilder.build_kind!()
        |> Base.encode64()

      Cache.put(
        assembly_table(opts),
        {:pending_ext_tx, tx_bytes},
        {:authorize_gate_extension, gate_id}
      )

      {:ok, %{tx_bytes: tx_bytes}}
    end
  end

  @doc "Signs and submits a gate extension transaction locally (no wallet). For localnet only."
  @spec sign_and_submit_extension_locally(String.t(), options()) ::
          {:ok, %{digest: String.t()}} | {:error, term()}
  def sign_and_submit_extension_locally(kind_bytes_b64, opts)
      when is_binary(kind_bytes_b64) and is_list(opts) do
    alias Sigil.Diplomacy.LocalSigner

    case LocalSigner.sign_and_submit(kind_bytes_b64) do
      {:ok, digest} ->
        apply_pending_extension_tx(opts, kind_bytes_b64)
        {:ok, %{digest: digest}}

      {:error, _reason} = error ->
        error
    end
  end

  @doc "Submits a wallet-signed gate extension transaction and refreshes cache on success."
  @spec submit_signed_extension_tx(String.t(), String.t(), options()) ::
          {:ok, %{digest: String.t(), effects_bcs: String.t() | nil}}
          | {:error, Client.error_reason()}
  def submit_signed_extension_tx(tx_bytes, signature, opts)
      when is_binary(tx_bytes) and is_binary(signature) and is_list(opts) do
    req_options = Keyword.get(opts, :req_options, [])

    case @sui_client.execute_transaction(tx_bytes, [signature], req_options) do
      {:ok, %{"status" => "SUCCESS", "digest" => digest} = effects} ->
        pending_key = Keyword.get(opts, :kind_bytes, tx_bytes)
        apply_pending_extension_tx(opts, pending_key)
        {:ok, %{digest: digest, effects_bcs: effects["effectsBcs"]}}

      {:error, _reason} = error ->
        error
    end
  end

  @spec fetch_all_owner_caps([String.t()], Client.request_opts()) ::
          {:ok, [map()]} | {:error, Client.error_reason()}
  defp fetch_all_owner_caps(query_owners, req_options) do
    Enum.reduce_while(query_owners, {:ok, []}, fn query_owner, {:ok, acc} ->
      case @sui_client.get_objects(
             [type: owner_cap_type_string(), owner: query_owner],
             req_options
           ) do
        {:ok, %{data: caps}} -> {:cont, {:ok, acc ++ caps}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  @spec fetch_assembly(String.t(), Client.request_opts()) ::
          {:ok, assembly()} | :skip | {:error, Client.error_reason()}
  defp fetch_assembly(assembly_id, req_options) do
    with {:ok, json} <- @sui_client.get_object(assembly_id, req_options) do
      parse_assembly(json)
    end
  end

  @spec parse_assembly(map()) :: {:ok, assembly()} | :skip
  defp parse_assembly(%{"character_address" => _} = _json), do: :skip

  defp parse_assembly(%{"linked_gate_id" => _value} = json), do: {:ok, Gate.from_json(json)}

  defp parse_assembly(%{"fuel" => _fuel, "energy_source" => _energy_source} = json),
    do: {:ok, NetworkNode.from_json(json)}

  defp parse_assembly(%{"inventory_keys" => _inventory_keys} = json),
    do: {:ok, StorageUnit.from_json(json)}

  defp parse_assembly(%{"extension" => _extension} = json), do: {:ok, Turret.from_json(json)}
  defp parse_assembly(%{"type_id" => _} = json), do: {:ok, Assembly.from_json(json)}
  defp parse_assembly(_json), do: :skip

  @spec cache_assembly(options(), String.t(), assembly()) :: :ok
  defp cache_assembly(opts, owner, assembly) do
    Cache.put(assembly_table(opts), assembly.id, {owner, assembly})
  end

  @spec fetch_cached_gate(String.t(), options()) ::
          {:ok, Gate.t()} | {:error, :not_found | :not_a_gate}
  defp fetch_cached_gate(gate_id, opts) do
    case Cache.get(assembly_table(opts), gate_id) do
      nil -> {:error, :not_found}
      {_owner, %Gate{} = gate} -> {:ok, gate}
      {_owner, _assembly} -> {:error, :not_a_gate}
    end
  end

  @spec apply_pending_extension_tx(options(), String.t()) :: :ok
  defp apply_pending_extension_tx(opts, tx_bytes) do
    table = assembly_table(opts)

    case Cache.take(table, {:pending_ext_tx, tx_bytes}) do
      {:authorize_gate_extension, gate_id} ->
        case sync_assembly(gate_id, opts) do
          {:ok, _assembly} -> :ok
          {:error, _reason} -> :ok
        end

      nil ->
        :ok
    end
  end

  @spec parse_shared_version!(map()) :: non_neg_integer()
  defp parse_shared_version!(json) do
    case parse_shared_version(json) do
      nil -> raise ArgumentError, "missing initial shared version"
      version -> version
    end
  end

  @spec parse_shared_version(map()) :: non_neg_integer() | nil
  defp parse_shared_version(%{"initial_shared_version" => version}) when is_integer(version),
    do: version

  defp parse_shared_version(%{"shared" => %{"initialSharedVersion" => version}})
       when is_binary(version),
       do: String.to_integer(version)

  defp parse_shared_version(%{"initialSharedVersion" => version}) when is_binary(version),
    do: String.to_integer(version)

  defp parse_shared_version(_json), do: nil

  @spec assembly_table(options()) :: Cache.table_id()
  defp assembly_table(opts) do
    opts |> Keyword.fetch!(:tables) |> Map.fetch!(:assemblies)
  end

  @spec broadcast(atom() | module(), String.t(), term()) :: :ok | {:error, term()}
  defp broadcast(pubsub, topic, event) do
    Phoenix.PubSub.broadcast(pubsub, topic, event)
  end

  @spec hex_to_bytes(String.t()) :: binary()
  defp hex_to_bytes("0x" <> hex), do: Base.decode16!(hex, case: :mixed)

  @spec owner_cap_type_string() :: String.t()
  defp owner_cap_type_string do
    "#{world_package_id()}::access::OwnerCap"
  end

  @spec world_package_id() :: String.t()
  defp world_package_id do
    world = Application.fetch_env!(:sigil, :eve_world)
    worlds = Application.fetch_env!(:sigil, :eve_worlds)
    %{package_id: package_id} = Map.fetch!(worlds, world)
    package_id
  end

  @spec owner_topic(String.t()) :: String.t()
  defp owner_topic(owner), do: "assemblies:#{owner}"

  @spec assembly_topic(String.t()) :: String.t()
  defp assembly_topic(assembly_id), do: "assembly:#{assembly_id}"
end
