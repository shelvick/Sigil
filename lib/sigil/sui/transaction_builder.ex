defmodule Sigil.Sui.TransactionBuilder do
  @moduledoc """
  Builds, digests, and submits Sui programmable transactions.
  """

  alias Sigil.Sui.Client
  alias Sigil.Sui.Signer
  alias Sigil.Sui.TransactionBuilder.PTB

  @sui_client Application.compile_env!(:sigil, :sui_client)
  @intent_prefix <<0, 0, 0>>

  @typedoc "Keyword options used to build transaction data."
  @type build_opts :: [
          sender: PTB.bytes32(),
          gas_owner: PTB.bytes32(),
          gas_payment: [PTB.object_ref()],
          gas_price: non_neg_integer(),
          gas_budget: non_neg_integer(),
          inputs: [PTB.call_arg()],
          commands: [PTB.command()],
          expiration: PTB.expiration()
        ]

  @doc "Builds transaction data bytes and raises on invalid options."
  @spec build!(build_opts()) :: binary()
  def build!(opts) when is_list(opts) do
    sender = fetch_required!(opts, :sender)
    commands = fetch_commands!(opts)
    gas_payment = fetch_gas_payment!(opts)

    transaction_data = %{
      kind: %{
        inputs: Keyword.get(opts, :inputs, []),
        commands: commands
      },
      sender: sender,
      gas_data: %{
        payment: gas_payment,
        owner: Keyword.get(opts, :gas_owner, sender),
        price: fetch_required!(opts, :gas_price),
        budget: fetch_required!(opts, :gas_budget)
      },
      expiration: Keyword.get(opts, :expiration, :none)
    }

    PTB.encode_transaction_data(transaction_data)
  end

  @doc "Builds transaction data bytes and returns an error tuple for invalid options."
  @spec build(build_opts()) :: {:ok, binary()} | {:error, String.t()}
  def build(opts) when is_list(opts) do
    {:ok, build!(opts)}
  rescue
    error in ArgumentError -> {:error, Exception.message(error)}
  end

  @doc "Computes the Sui transaction digest for BCS bytes."
  @spec digest(binary()) :: binary()
  def digest(tx_bytes) when is_binary(tx_bytes) do
    Blake2.hash2b(@intent_prefix <> tx_bytes, 32)
  end

  @doc "Builds, signs, and submits a transaction through the configured client."
  @spec execute(build_opts(), Signer.private_key(), Signer.public_key()) ::
          {:ok, Client.tx_effects()} | {:error, Client.error_reason()}
  def execute(opts, private_key, public_key)
      when is_list(opts) and is_binary(private_key) and is_binary(public_key) do
    tx_bytes = build!(opts)

    signature =
      tx_bytes
      |> Signer.sign(private_key)
      |> Signer.encode_signature(public_key)

    @sui_client.execute_transaction(Base.encode64(tx_bytes), [Base.encode64(signature)], [])
  end

  defp fetch_required!(opts, key) do
    case Keyword.fetch(opts, key) do
      {:ok, value} -> value
      :error -> raise ArgumentError, "#{key} is required"
    end
  end

  defp fetch_commands!(opts) do
    case Keyword.get(opts, :commands) do
      commands when is_list(commands) and commands != [] -> commands
      _ -> raise ArgumentError, "at least one command is required"
    end
  end

  defp fetch_gas_payment!(opts) do
    case Keyword.get(opts, :gas_payment) do
      gas_payment when is_list(gas_payment) and gas_payment != [] -> gas_payment
      _ -> raise ArgumentError, "at least one gas payment coin is required"
    end
  end
end
