defmodule SigilWeb.IntelMarketLive.PageHelpers do
  @moduledoc """
  Shared page-level helpers for IntelMarketLive mount and rendering state.
  """

  import Phoenix.Component, only: [assign: 2, assign: 3]

  alias Sigil.IntelMarket
  alias SigilWeb.IntelMarketLive.State

  @spec assign_seal_config_json(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def assign_seal_config_json(socket) do
    assign(
      socket,
      :seal_config_json,
      Jason.encode!(IntelMarket.build_seal_config(State.seal_opts(socket)))
    )
  end

  @spec maybe_load_marketplace(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def maybe_load_marketplace(%{assigns: %{authenticated?: false}} = socket), do: socket

  def maybe_load_marketplace(%{assigns: %{cache_tables: cache_tables}} = socket)
      when not is_map(cache_tables) do
    socket
  end

  def maybe_load_marketplace(socket) do
    case IntelMarket.discover_marketplace(State.market_opts(socket)) do
      {:ok, nil} ->
        assign(socket, marketplace_available?: false)

      {:ok, marketplace_info} ->
        socket
        |> assign(marketplace_available?: true, marketplace_info: marketplace_info)
        |> State.sync_and_load_data()

      {:error, _reason} ->
        assign(socket, marketplace_available?: false)
    end
  end

  @spec maybe_subscribe_marketplace(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def maybe_subscribe_marketplace(socket) do
    if Phoenix.LiveView.connected?(socket) and socket.assigns[:authenticated?] and
         socket.assigns[:pubsub] do
      Phoenix.PubSub.subscribe(
        socket.assigns.pubsub,
        IntelMarket.topic(world: socket.assigns.world)
      )
    end

    socket
  end

  @spec handle_pseudonym_error(Phoenix.LiveView.Socket.t(), String.t(), String.t()) ::
          Phoenix.LiveView.Socket.t()
  def handle_pseudonym_error(socket, "load", _reason) do
    socket
    |> State.reload_pseudonyms()
    |> assign(
      active_pseudonym: nil,
      pending_active_pseudonym: nil,
      pseudonym_error_message: "Failed to load pseudonyms"
    )
  end

  def handle_pseudonym_error(socket, "encrypt", _reason) do
    assign(socket, pseudonym_error_message: "Failed to create pseudonym")
  end

  def handle_pseudonym_error(socket, "activate", _reason) do
    assign(socket, pseudonym_error_message: "Failed to switch pseudonym")
  end

  def handle_pseudonym_error(socket, _phase, _reason) do
    assign(socket, pseudonym_error_message: "Failed to switch pseudonym")
  end

  @spec normalize_section(String.t()) :: :browsing | :my_listings
  def normalize_section("my_listings"), do: :my_listings
  def normalize_section(_section), do: :browsing

  @spec section_button_classes(boolean()) :: String.t()
  def section_button_classes(true) do
    "rounded-full border border-quantum-300 bg-quantum-400/10 px-4 py-2 font-mono text-xs uppercase tracking-[0.22em] text-cream"
  end

  def section_button_classes(false) do
    "rounded-full border border-space-600/80 bg-space-800/70 px-4 py-2 font-mono text-xs uppercase tracking-[0.22em] text-space-500 transition hover:border-quantum-400 hover:text-cream"
  end
end
