defmodule Sigil.Sui.GasRelay do
  @moduledoc """
  Prepares and submits relay-sponsored Sui transactions.
  """

  alias Sigil.Sui.{Client, Signer, TransactionBuilder}

  require Logger

  @default_gas_budget 10_000_000
  @default_gas_price 1_000
  @default_key_path ".sigil/relay_key"
  @faucet_url "https://faucet.testnet.sui.io/v1/gas"

  @typedoc "Gas relay option."
  @type option ::
          {:client, module()}
          | {:relay_keypair, Signer.keypair()}
          | {:gas_budget, non_neg_integer()}
          | {:req_options, keyword()}
          | {:key_path, Path.t()}

  @typedoc "Gas relay options."
  @type options :: [option()]

  @typedoc "Prepared sponsored transaction payload."
  @type sponsored_tx :: %{tx_bytes: String.t(), relay_signature: String.t()}

  @typedoc "Submission result surfaced to callers."
  @type submission_result :: %{
          digest: String.t(),
          effects_bcs: String.t() | nil,
          effects: Client.tx_effects()
        }

  @doc "Builds sponsored transaction data for a pseudonymous sender."
  @spec prepare_sponsored(TransactionBuilder.kind_opts(), String.t(), options()) ::
          {:ok, sponsored_tx()}
          | {:error,
             :no_gas_coins | :insufficient_gas | :relay_key_not_found | Client.error_reason()}
  def prepare_sponsored(kind_opts, pseudonym_address, opts \\ [])
      when is_list(kind_opts) and is_binary(pseudonym_address) and is_list(opts) do
    client = client(opts)
    gas_budget = Keyword.get(opts, :gas_budget, @default_gas_budget)
    req_opts = request_opts(opts)

    with {:ok, relay_keypair} <- relay_keypair(opts),
         {:ok, coins} <- client.get_coins(relay_address_from_keypair(relay_keypair), req_opts),
         {:ok, gas_payment} <- select_gas_coins(coins, gas_budget),
         {:ok, sender} <- decode_sui_address(pseudonym_address) do
      tx_bytes =
        TransactionBuilder.build!(
          kind_opts ++
            [
              sender: sender,
              gas_owner: Signer.address_from_public_key(elem(relay_keypair, 0)),
              gas_payment: gas_payment,
              gas_price: @default_gas_price,
              gas_budget: gas_budget,
              expiration: :none
            ]
        )

      relay_signature =
        tx_bytes
        |> Signer.sign(elem(relay_keypair, 1))
        |> Signer.encode_signature(elem(relay_keypair, 0))
        |> Base.encode64()

      {:ok, %{tx_bytes: Base.encode64(tx_bytes), relay_signature: relay_signature}}
    end
  end

  @doc "Submits a sponsored transaction using both pseudonym and relay signatures."
  @spec submit_sponsored(String.t(), String.t(), String.t(), options()) ::
          {:ok, submission_result()} | {:error, Client.error_reason()}
  def submit_sponsored(tx_bytes, pseudonym_signature, relay_signature, opts \\ [])
      when is_binary(tx_bytes) and is_binary(pseudonym_signature) and is_binary(relay_signature) and
             is_list(opts) do
    case client(opts).execute_transaction(
           tx_bytes,
           [pseudonym_signature, relay_signature],
           request_opts(opts)
         ) do
      {:ok, %{"status" => "SUCCESS", "digest" => digest} = effects}
      when is_binary(digest) ->
        {:ok, %{digest: digest, effects_bcs: Map.get(effects, "effectsBcs"), effects: effects}}

      {:ok, %{"digest" => _digest}} ->
        {:error, :invalid_response}

      {:ok, _effects} ->
        {:error, :invalid_response}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Returns the relay Sui address for the configured keypair."
  @spec relay_address(options()) :: String.t()
  def relay_address(opts \\ []) when is_list(opts) do
    case relay_keypair(opts) do
      {:ok, keypair} -> relay_address_from_keypair(keypair)
      {:error, :relay_key_not_found} -> raise "unable to load or generate relay keypair"
    end
  end

  @spec client(options()) :: module()
  defp client(opts), do: Keyword.get(opts, :client, Application.fetch_env!(:sigil, :sui_client))

  @spec request_opts(options()) :: keyword()
  defp request_opts(opts) do
    opts
    |> Keyword.take([
      :req_options,
      :url,
      :test_pid,
      :get_coins_result,
      :execute_result
    ])
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end

  @spec relay_keypair(options()) :: {:ok, Signer.keypair()} | {:error, :relay_key_not_found}
  defp relay_keypair(opts) do
    case Keyword.fetch(opts, :relay_keypair) do
      {:ok, keypair} -> {:ok, keypair}
      :error -> load_or_generate_keypair(opts)
    end
  end

  @spec load_or_generate_keypair(options()) ::
          {:ok, Signer.keypair()} | {:error, :relay_key_not_found}
  defp load_or_generate_keypair(opts) do
    case load_from_env() do
      {:ok, _keypair} = ok ->
        ok

      :not_configured ->
        load_from_file_or_generate(opts)
    end
  end

  @spec load_from_env() :: {:ok, Signer.keypair()} | :not_configured
  defp load_from_env do
    case System.get_env("RELAY_KEYPAIR") do
      nil ->
        :not_configured

      encoded ->
        with {:ok, contents} <- Base.decode64(encoded),
             {:ok, _keypair} = ok <- decode_keypair(contents) do
          ok
        else
          _ -> :not_configured
        end
    end
  end

  @spec load_from_file_or_generate(options()) ::
          {:ok, Signer.keypair()} | {:error, :relay_key_not_found}
  defp load_from_file_or_generate(opts) do
    key_path = key_path(opts)

    case File.read(key_path) do
      {:ok, contents} ->
        decode_keypair(contents)

      {:error, :enoent} ->
        keypair = Signer.generate_keypair()

        with :ok <- persist_keypair(key_path, keypair) do
          maybe_fund_relay(keypair, opts)
          {:ok, keypair}
        end

      {:error, _reason} ->
        {:error, :relay_key_not_found}
    end
  end

  @max_faucet_attempts 10
  @initial_faucet_delay_ms 2_000

  @spec maybe_fund_relay(Signer.keypair(), options()) :: :ok
  defp maybe_fund_relay(keypair, opts) do
    client = client(opts)
    address = relay_address_from_keypair(keypair)
    req_opts = request_opts(opts)

    if client == Sigil.Sui.Client.HTTP do
      case client.get_coins(address, req_opts) do
        {:ok, [_ | _]} ->
          Logger.info("Gas relay #{address} already funded")
          :ok

        _ ->
          Logger.info("Gas relay #{address} has no coins, spawning faucet funding task...")
          Task.start(fn -> faucet_retry_loop(address, 1) end)
          :ok
      end
    else
      :ok
    end
  end

  @spec faucet_retry_loop(String.t(), pos_integer()) :: :ok
  defp faucet_retry_loop(address, attempt) when attempt > @max_faucet_attempts do
    Logger.error(
      "Faucet funding failed after #{@max_faucet_attempts} attempts for relay #{address}"
    )

    :ok
  end

  defp faucet_retry_loop(address, attempt) do
    delay = @initial_faucet_delay_ms * Integer.pow(2, attempt - 1)

    Logger.info(
      "Faucet attempt #{attempt}/#{@max_faucet_attempts} for relay #{address} (delay: #{delay}ms)"
    )

    :timer.sleep(delay)

    body = Jason.encode!(%{"FixedAmountRequest" => %{"recipient" => address}})

    case Req.post(url: @faucet_url, body: body, headers: [{"content-type", "application/json"}]) do
      {:ok, %Req.Response{status: status}} when status in 200..299 ->
        Logger.info("Faucet funded relay #{address} on attempt #{attempt}")
        :ok

      {:ok, %Req.Response{status: 429}} ->
        Logger.warning("Faucet rate-limited on attempt #{attempt}, retrying...")
        faucet_retry_loop(address, attempt + 1)

      {:ok, %Req.Response{status: status, body: resp_body}} ->
        Logger.warning("Faucet attempt #{attempt} failed: #{status} #{inspect(resp_body)}")
        faucet_retry_loop(address, attempt + 1)

      {:error, reason} ->
        Logger.warning("Faucet attempt #{attempt} error: #{inspect(reason)}")
        faucet_retry_loop(address, attempt + 1)
    end
  end

  @spec persist_keypair(Path.t(), Signer.keypair()) :: :ok | {:error, :relay_key_not_found}
  defp persist_keypair(key_path, keypair) do
    with :ok <- File.mkdir_p(Path.dirname(key_path)),
         :ok <- File.write(key_path, :erlang.term_to_binary(keypair)) do
      :ok
    else
      {:error, _reason} -> {:error, :relay_key_not_found}
    end
  end

  @spec key_path(options()) :: Path.t()
  defp key_path(opts), do: Keyword.get(opts, :key_path, @default_key_path)

  @spec decode_keypair(binary()) :: {:ok, Signer.keypair()} | {:error, :relay_key_not_found}
  defp decode_keypair(contents) when is_binary(contents) do
    try do
      case :erlang.binary_to_term(contents, [:safe]) do
        {<<_::binary-size(32)>> = public_key, <<_::binary-size(32)>> = private_key} ->
          {:ok, {public_key, private_key}}

        _other ->
          {:error, :relay_key_not_found}
      end
    rescue
      ArgumentError ->
        {:error, :relay_key_not_found}
    end
  end

  @spec select_gas_coins([Client.coin_info()], non_neg_integer()) ::
          {:ok, [Client.object_ref()]} | {:error, :no_gas_coins | :insufficient_gas}
  defp select_gas_coins([], _budget), do: {:error, :no_gas_coins}

  defp select_gas_coins(coins, budget) do
    {selected, total_balance} =
      Enum.reduce_while(coins, {[], 0}, fn %{balance: balance} = coin,
                                           {selected, total_balance} ->
        next_selected = [coin_ref(coin) | selected]
        next_total = total_balance + balance

        if next_total >= budget do
          {:halt, {Enum.reverse(next_selected), next_total}}
        else
          {:cont, {next_selected, next_total}}
        end
      end)

    if total_balance >= budget do
      {:ok, selected}
    else
      {:error, :insufficient_gas}
    end
  end

  @spec coin_ref(Client.coin_info()) :: Client.object_ref()
  defp coin_ref(%{object_id: object_id, version: version, digest: digest}) do
    {object_id, version, digest}
  end

  @spec relay_address_from_keypair(Signer.keypair()) :: String.t()
  defp relay_address_from_keypair({public_key, _private_key}) do
    public_key
    |> Signer.address_from_public_key()
    |> Signer.to_sui_address()
  end

  @spec decode_sui_address(String.t()) :: {:ok, <<_::256>>} | {:error, :invalid_response}
  defp decode_sui_address("0x" <> hex), do: decode_sui_address(hex)

  defp decode_sui_address(hex) when is_binary(hex) do
    padded = String.pad_leading(hex, 64, "0")

    case Base.decode16(padded, case: :mixed) do
      {:ok, <<_::binary-size(32)>> = bytes} -> {:ok, bytes}
      _other -> {:error, :invalid_response}
    end
  end
end
