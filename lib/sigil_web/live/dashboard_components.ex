defmodule SigilWeb.DashboardLive.Components do
  @moduledoc false

  use SigilWeb, :html

  import SigilWeb.AssemblyHelpers

  alias Sigil.Accounts.Account
  alias Sigil.Sui.Types.NetworkNode

  @doc false
  @spec authenticated_view(map()) :: Phoenix.LiveView.Rendered.t()
  def authenticated_view(assigns) do
    ~H"""
    <div class="grid gap-8">
      <div class="grid gap-4 lg:grid-cols-[2fr_1fr]">
        <div class="rounded-3xl border border-space-600/80 bg-space-800/80 p-6">
          <p class="font-mono text-xs uppercase tracking-[0.3em] text-quantum-300">Wallet linked</p>
          <h2 class="mt-4 text-2xl font-semibold text-cream"><%= truncate_id(@current_account.address) %></h2>
          <p class="mt-2 break-all font-mono text-sm text-foreground"><%= @current_account.address %></p>

          <dl class="mt-6 grid gap-4 sm:grid-cols-3">
            <div>
              <dt class="font-mono text-[0.65rem] uppercase tracking-[0.25em] text-space-500">Character</dt>
              <dd class="mt-2 text-sm text-cream"><%= primary_character_name(@current_account) %></dd>
            </div>
            <div>
              <dt class="font-mono text-[0.65rem] uppercase tracking-[0.25em] text-space-500">Tribe</dt>
              <dd class="mt-2 text-sm text-cream"><%= tribe_label(@current_account) %></dd>
            </div>
            <div>
              <dt class="font-mono text-[0.65rem] uppercase tracking-[0.25em] text-space-500">Crew count</dt>
              <dd class="mt-2 text-sm text-cream"><%= length(@current_account.characters) %> online</dd>
            </div>
          </dl>
        </div>

        <div class="rounded-3xl border border-space-600/80 bg-space-800/60 p-6">
          <p class="font-mono text-xs uppercase tracking-[0.3em] text-quantum-300">Session controls</p>
          <p class="mt-4 text-sm leading-6 text-space-500">
            Discovery stays synced while this command deck remains linked to the uplink.
          </p>
          <.link
            href={~p"/session"}
            method="delete"
            class="mt-6 inline-flex rounded-full bg-quantum-600 px-5 py-3 font-mono text-xs uppercase tracking-[0.25em] text-space-950 transition hover:bg-quantum-400"
          >
            Disconnect Wallet
          </.link>
        </div>
      </div>

      <.assembly_manifest assemblies={@assemblies} discovery_error={@discovery_error} />
    </div>
    """
  end

  @doc false
  @spec assembly_manifest(map()) :: Phoenix.LiveView.Rendered.t()
  def assembly_manifest(assigns) do
    ~H"""
    <div class="rounded-3xl border border-space-600/80 bg-space-800/70 p-6">
      <div class="flex items-center justify-between gap-4">
        <div>
          <p class="font-mono text-xs uppercase tracking-[0.3em] text-quantum-300">Assembly manifest</p>
          <h2 class="mt-3 text-2xl font-semibold text-cream">Operational Assets</h2>
        </div>
        <span class="rounded-full border border-space-600/80 bg-space-900/70 px-3 py-1 font-mono text-xs uppercase tracking-[0.2em] text-space-500">
          <%= length(@assemblies) %> tracked
        </span>
      </div>

      <%= if @assemblies == [] do %>
        <div class="mt-6 rounded-2xl border border-space-600/80 bg-space-900/70 p-5">
          <p class="text-sm text-cream">
            <%= if @discovery_error, do: "Assembly discovery is temporarily unavailable", else: "No assemblies found" %>
          </p>
          <p class="mt-2 text-sm text-space-500">
            <%= if @discovery_error,
              do: "Retry discovery by refreshing the command deck.",
              else: "Link another wallet or check again after more assets come online." %>
          </p>
        </div>
      <% else %>
        <div class="mt-6 overflow-x-auto">
          <table class="min-w-full border-separate border-spacing-y-3">
            <thead>
              <tr class="font-mono text-xs uppercase tracking-[0.25em] text-space-500">
                <th class="px-4 py-2 text-left">Type</th>
                <th class="px-4 py-2 text-left">Name</th>
                <th class="px-4 py-2 text-left">Status</th>
                <th class="px-4 py-2 text-left">Fuel</th>
              </tr>
            </thead>
            <tbody>
              <%= for assembly <- @assemblies do %>
                <tr class="cursor-pointer rounded-2xl bg-space-900/70 text-sm text-foreground transition hover:bg-space-800/80" phx-click={JS.navigate(~p"/assembly/#{assembly.id}")}>
                  <td class="rounded-l-2xl px-4 py-4 font-mono text-xs uppercase tracking-[0.2em] text-quantum-300">
                    <%= assembly_type_label(assembly) %>
                  </td>
                  <td class="px-4 py-4">
                    <.link navigate={~p"/assembly/#{assembly.id}"} class="font-semibold text-cream hover:text-quantum-300">
                      <%= assembly_name(assembly) %>
                    </.link>
                  </td>
                  <td class="px-4 py-4">
                    <span class={status_badge_classes(assembly)}>
                      <%= assembly_status(assembly) %>
                    </span>
                  </td>
                  <td class="rounded-r-2xl px-4 py-4">
                    <%= if match?(%NetworkNode{}, assembly) do %>
                      <div class="space-y-2">
                        <div class="flex items-center justify-between gap-3 font-mono text-xs uppercase tracking-[0.15em] text-space-500">
                          <span><%= fuel_label(assembly.fuel) %></span>
                          <span><%= fuel_percent_label(assembly.fuel) %></span>
                        </div>
                        <div class="h-2 rounded-full bg-space-700">
                          <div class="h-full rounded-full bg-quantum-400" style={"width: #{fuel_percent(assembly.fuel)}%"}></div>
                        </div>
                      </div>
                    <% else %>
                      <span class="font-mono text-xs uppercase tracking-[0.2em] text-space-500">-</span>
                    <% end %>
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      <% end %>
    </div>
    """
  end

  @doc false
  @spec wallet_connect_view(map()) :: Phoenix.LiveView.Rendered.t()
  def wallet_connect_view(assigns) do
    ~H"""
    <div class="grid gap-8 lg:grid-cols-[1.4fr_0.9fr]">
      <div class="space-y-6">
        <p class="font-mono text-xs uppercase tracking-[0.3em] text-quantum-300">EVE Frontier-ready interface</p>
        <h2 class="max-w-2xl text-4xl font-semibold leading-tight text-cream sm:text-6xl">
          Connect Your Wallet
        </h2>
        <p class="max-w-2xl text-base leading-7 text-space-500 sm:text-lg">
          Link a commander wallet to unlock tribe assemblies, live status telemetry, and shared frontier operations.
        </p>
      </div>

      <div class="rounded-3xl border border-space-600/80 bg-space-800/80 p-6">
        <button
          id="wallet-connect"
          type="button"
          phx-hook="WalletConnect"
          class="inline-flex w-full items-center justify-center rounded-full bg-quantum-400 px-5 py-3 font-mono text-xs uppercase tracking-[0.25em] text-space-950 transition hover:bg-quantum-300"
        >
          Connect Wallet
        </button>

        <.wallet_state_panel
          wallets={@wallets}
          wallet_state={@wallet_state}
          wallet_name={@wallet_name}
          wallet_error={@wallet_error}
        />
      </div>
    </div>
    """
  end

  @doc false
  @spec wallet_state_panel(map()) :: Phoenix.LiveView.Rendered.t()
  def wallet_state_panel(%{wallets: wallets, wallet_state: :idle} = assigns) when wallets != [] do
    ~H"""
    <div class="mt-6 space-y-3">
      <p class="font-mono text-xs uppercase tracking-[0.2em] text-space-500">
        Available wallets
      </p>
      <%= for {wallet, index} <- Enum.with_index(@wallets) do %>
        <button
          type="button"
          phx-click="select_wallet"
          phx-value-index={index}
          class="flex w-full items-center justify-between rounded-2xl border border-space-600/80 bg-space-900/70 px-4 py-3 text-left transition hover:border-quantum-400/40 hover:bg-space-900"
        >
          <span class="flex items-center gap-2 text-sm text-cream">
            <%= if icon = wallet["icon"] || wallet[:icon] do %>
              <img src={icon} alt="" class="h-5 w-5 rounded" />
            <% end %>
            <%= wallet_name(wallet) %>
          </span>
          <span class="font-mono text-xs uppercase tracking-[0.2em] text-quantum-300">
            Connect
          </span>
        </button>
      <% end %>
    </div>
    """
  end

  def wallet_state_panel(%{wallet_state: :error} = assigns) do
    ~H"""
    <div class="mt-6 rounded-2xl border border-warning/60 bg-warning/10 p-5">
      <p class="text-sm text-cream"><%= @wallet_error %></p>
      <button
        type="button"
        phx-click="wallet_retry"
        class="mt-4 inline-flex rounded-full border border-quantum-400/40 px-4 py-2 font-mono text-xs uppercase tracking-[0.2em] text-quantum-300 transition hover:border-quantum-300 hover:text-cream"
      >
        Try Again
      </button>
    </div>
    """
  end

  def wallet_state_panel(%{wallet_state: :signing} = assigns) do
    ~H"""
    <p class="mt-6 text-sm text-space-500">
      Please approve the signing request in your wallet...
    </p>
    """
  end

  def wallet_state_panel(%{wallet_state: :connecting} = assigns) do
    ~H"""
    <div class="mt-6 space-y-2">
      <p class="text-sm text-space-500">Connecting to wallet...</p>
      <p :if={@wallet_name} class="font-mono text-xs uppercase tracking-[0.2em] text-quantum-300">
        <%= @wallet_name %>
      </p>
    </div>
    """
  end

  def wallet_state_panel(assigns) do
    ~H"""
    <p class="mt-6 text-sm text-space-500">
      No Sui wallet detected. Install EVE Vault to continue.
    </p>
    """
  end

  @spec primary_character_name(Account.t()) :: String.t()
  defp primary_character_name(%Account{characters: [%{metadata: %{name: name}} | _rest]})
       when is_binary(name),
       do: name

  defp primary_character_name(%Account{characters: []}), do: "No characters synced"
  defp primary_character_name(%Account{}), do: "Commander profile"

  @spec tribe_label(Account.t()) :: String.t()
  defp tribe_label(%Account{tribe_id: tribe_id}) when is_integer(tribe_id),
    do: Integer.to_string(tribe_id)

  defp tribe_label(%Account{}), do: "Unaligned"

  @spec wallet_name(map()) :: String.t()
  defp wallet_name(%{"name" => name}) when is_binary(name), do: name
  defp wallet_name(%{name: name}) when is_binary(name), do: name
  defp wallet_name(_wallet), do: "Unknown Wallet"
end
