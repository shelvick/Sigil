defmodule SigilWeb.TransactionHelpers do
  @moduledoc """
  Shared helpers for world-aware transaction signing across LiveViews.

  Provides environment-aware signing: wallet-based on testnet/mainnet,
  server-side via LocalSigner on localnet.
  """

  alias Sigil.Worlds

  @sui_chains %{
    "stillness" => "sui:testnet",
    "utopia" => "sui:testnet",
    "internal" => "sui:testnet",
    "localnet" => "sui:testnet",
    "mainnet" => "sui:mainnet"
  }

  @doc "Returns true when running against a local Sui node for the given world."
  @spec localnet?(Worlds.world_name()) :: boolean()
  def localnet?(world) when is_binary(world), do: world == "localnet"

  @doc "Returns true when running against localnet for the default world."
  @spec localnet?() :: boolean()
  def localnet?, do: localnet?(Worlds.default_world())

  @doc "Returns the Sui wallet chain identifier for the given world."
  @spec sui_chain(Worlds.world_name()) :: String.t()
  def sui_chain(world) when is_binary(world) do
    Map.get(@sui_chains, world, "sui:testnet")
  end

  @doc "Returns the Sui wallet chain identifier for the default world."
  @spec sui_chain() :: String.t()
  def sui_chain, do: sui_chain(Worlds.default_world())

  @doc "Returns the localnet signer address for the given world, or nil if not localnet."
  @spec localnet_signer_address(Worlds.world_name()) :: String.t() | nil
  def localnet_signer_address(world) when is_binary(world) do
    if localnet?(world), do: Sigil.Diplomacy.LocalSigner.signer_address()
  end

  @doc "Returns the localnet signer address for the default world, or nil if not localnet."
  @spec localnet_signer_address() :: String.t() | nil
  def localnet_signer_address, do: localnet_signer_address(Worlds.default_world())
end
