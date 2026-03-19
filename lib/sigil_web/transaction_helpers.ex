defmodule SigilWeb.TransactionHelpers do
  @moduledoc """
  Shared helpers for transaction signing across LiveViews.

  Provides environment-aware signing: wallet-based on testnet/mainnet,
  server-side via LocalSigner on localnet.
  """

  @sui_chains %{
    "stillness" => "sui:testnet",
    "utopia" => "sui:testnet",
    "internal" => "sui:testnet",
    "localnet" => "sui:testnet",
    "mainnet" => "sui:mainnet"
  }

  @doc "Returns true when running against a local Sui node."
  @spec localnet?() :: boolean()
  def localnet? do
    Application.fetch_env!(:sigil, :eve_world) == "localnet"
  end

  @doc "Returns the Sui wallet chain identifier for the current environment."
  @spec sui_chain() :: String.t()
  def sui_chain do
    world = Application.fetch_env!(:sigil, :eve_world)
    Map.get(@sui_chains, world, "sui:testnet")
  end

  @doc "Returns the localnet signer address, or nil if not configured."
  @spec localnet_signer_address() :: String.t() | nil
  def localnet_signer_address do
    if localnet?(), do: Sigil.Diplomacy.LocalSigner.signer_address()
  end
end
