defmodule SigilWeb.DashboardLive.Components do
  @moduledoc false

  use SigilWeb, :html

  import SigilWeb.AlertsHelpers
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
          <button
            type="button"
            class="mt-2 inline-flex items-center gap-2 rounded-full border border-space-600/80 bg-space-900/70 px-3 py-1 font-mono text-xs text-space-500 transition hover:border-quantum-400/40 hover:text-quantum-300"
            onclick={"navigator.clipboard.writeText('#{@current_account.address}').then(() => { this.querySelector('span').textContent = 'Copied!'; setTimeout(() => { this.querySelector('span').textContent = 'Copy address'; }, 1500); })"}
          >
            <span>Copy address</span>
          </button>

          <dl class="mt-6 grid gap-4 sm:grid-cols-3">
            <div>
              <dt class="font-mono text-[0.65rem] uppercase tracking-[0.25em] text-space-500">Character</dt>
              <dd class="mt-2 text-sm text-cream"><%= active_character_name(@active_character, @current_account) %></dd>
            </div>
            <div>
              <dt class="font-mono text-[0.65rem] uppercase tracking-[0.25em] text-space-500">Tribe</dt>
              <dd class="mt-2 text-sm text-cream"><%= active_character_tribe_label(@active_character) %></dd>
            </div>
            <div>
              <dt class="font-mono text-[0.65rem] uppercase tracking-[0.25em] text-space-500">Characters</dt>
              <dd class="mt-2 text-sm text-cream"><%= length(@current_account.characters) %></dd>
            </div>
          </dl>

          <%= if length(@current_account.characters) > 1 do %>
            <div class="mt-6 space-y-3 border-t border-space-600/80 pt-6">
              <p class="font-mono text-xs uppercase tracking-[0.2em] text-space-500">Character roster</p>
              <%= for character <- @current_account.characters do %>
                <div class="flex items-center justify-between rounded-2xl border border-space-600/80 bg-space-900/70 px-4 py-3">
                  <div>
                    <p class="text-sm text-cream"><%= character_name(character) %></p>
                    <p class="font-mono text-xs text-space-500">Tribe: <%= character_tribe_label(character) %></p>
                  </div>
                  <%= if @active_character && @active_character.id == character.id do %>
                    <span class="font-mono text-xs uppercase tracking-[0.2em] text-quantum-300">Active</span>
                  <% else %>
                    <.link
                      method="put"
                      href={~p"/session/character/#{character.id}"}
                      class="font-mono text-xs uppercase tracking-[0.2em] text-quantum-300 hover:text-cream"
                    >
                      Switch
                    </.link>
                  <% end %>
                </div>
              <% end %>
            </div>
          <% end %>

          <.link
            :if={@active_character && @active_character.tribe_id && @active_character.tribe_id > 0}
            navigate={~p"/tribe/#{@active_character.tribe_id}"}
            class="mt-6 inline-flex rounded-full border border-quantum-400/40 px-4 py-2 font-mono text-xs uppercase tracking-[0.24em] text-quantum-300 transition hover:border-quantum-300 hover:text-cream"
          >
            View Tribe
          </.link>
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

      <.alerts_summary alert_summary={@alert_summary} unread_count={@unread_count} />
      <.assembly_manifest assemblies={@assemblies} discovery_error={@discovery_error} />
    </div>
    """
  end

  @doc """
  Renders the authenticated dashboard alert summary.
  """
  @spec alerts_summary(map()) :: Phoenix.LiveView.Rendered.t()
  def alerts_summary(assigns) do
    ~H"""
    <div class="rounded-3xl border border-space-600/80 bg-space-800/70 p-6">
      <div class="flex items-start justify-between gap-4">
        <div>
          <p class="font-mono text-xs uppercase tracking-[0.3em] text-quantum-300">Alert relay</p>
          <h2 class="mt-3 text-2xl font-semibold text-cream">Active Alerts</h2>
        </div>
        <span class="rounded-full border border-quantum-400/40 bg-quantum-400/10 px-3 py-1 font-mono text-xs uppercase tracking-[0.2em] text-quantum-300">
          <%= @unread_count %> unread
        </span>
      </div>

      <%= if @alert_summary == [] do %>
        <div class="mt-6 rounded-2xl border border-space-600/80 bg-space-900/70 p-5">
          <p class="text-sm text-cream">No active alerts</p>
        </div>
      <% else %>
        <div class="mt-6 space-y-4">
          <article :for={alert <- @alert_summary} class={card_classes(alert)}>
            <div class="flex flex-col gap-3 md:flex-row md:items-start md:justify-between">
              <div class="space-y-2">
                <div class="flex flex-wrap items-center gap-3">
                  <span class={severity_badge_classes(alert.severity)}><%= type_label(alert.type) %></span>
                  <span :if={alert.status == "new"} class="inline-flex h-2.5 w-2.5 rounded-full bg-quantum-300"></span>
                </div>
                <p class="text-sm font-semibold text-cream"><%= alert.assembly_name %></p>
                <p class={message_classes(alert.status)}><%= alert.message %></p>
                <p class="text-xs text-space-500"><%= timestamp_label(alert) %></p>
              </div>
            </div>
          </article>
        </div>

        <.link
          navigate={~p"/alerts"}
          class="mt-6 inline-flex rounded-full border border-quantum-400/40 px-4 py-2 font-mono text-xs uppercase tracking-[0.24em] text-quantum-300 transition hover:border-quantum-300 hover:text-cream"
        >
          View All Alerts
        </.link>
      <% end %>
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

      <%= if @assemblies != [] do %>
        <div class="mt-4 flex flex-wrap gap-2">
          <%= for {type, count} <- type_counts(@assemblies) do %>
            <span class="rounded-full border border-quantum-400/30 bg-quantum-400/5 px-3 py-1 font-mono text-xs uppercase tracking-[0.15em] text-quantum-300">
              <%= type %>: <%= count %>
            </span>
          <% end %>
        </div>
      <% end %>

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
                  <td class={["rounded-l-2xl px-4 py-4 font-mono text-xs uppercase tracking-[0.2em]", type_text_color(assembly)]}>
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
                          <div class={["h-full rounded-full", fuel_bar_color(assembly.fuel)]} style={"width: #{fuel_bar_width(assembly.fuel)}%"}></div>
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
          wallet_accounts={@wallet_accounts}
        />
      </div>
    </div>

    <div class="mt-12 grid gap-6 md:grid-cols-3">
      <div class="rounded-2xl border border-space-600/60 bg-space-800/50 p-6">
        <p class="font-mono text-xs uppercase tracking-[0.3em] text-quantum-300">Diplomacy</p>
        <p class="mt-3 text-sm font-semibold text-cream">On-Chain Standings</p>
        <p class="mt-2 text-sm leading-6 text-space-500">
          Set tribe standings that enforce gate access automatically via Sui Move smart contracts.
        </p>
      </div>
      <div class="rounded-2xl border border-space-600/60 bg-space-800/50 p-6">
        <p class="font-mono text-xs uppercase tracking-[0.3em] text-quantum-300">Infrastructure</p>
        <p class="mt-3 text-sm font-semibold text-cream">Assembly Monitoring</p>
        <p class="mt-2 text-sm leading-6 text-space-500">
          Track gates, nodes, turrets, and storage units with real-time fuel status and burn rate forecasting.
        </p>
      </div>
      <div class="rounded-2xl border border-space-600/60 bg-space-800/50 p-6">
        <p class="font-mono text-xs uppercase tracking-[0.3em] text-quantum-300">Coordination</p>
        <p class="mt-3 text-sm font-semibold text-cream">Tribe Operations</p>
        <p class="mt-2 text-sm leading-6 text-space-500">
          Aggregate tribe fleet view, shared governance, and coordinated infrastructure management.
        </p>
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

  def wallet_state_panel(%{wallet_state: :account_selection} = assigns) do
    ~H"""
    <div class="mt-6 space-y-3">
      <p class="font-mono text-xs uppercase tracking-[0.2em] text-space-500">
        Select Account
      </p>
      <%= for {account, index} <- Enum.with_index(@wallet_accounts) do %>
        <button
          type="button"
          phx-click="select_account"
          phx-value-index={index}
          class="flex w-full items-center justify-between rounded-2xl border border-space-600/80 bg-space-900/70 px-4 py-3 text-left transition hover:border-quantum-400/40 hover:bg-space-900"
        >
          <span class="text-sm text-cream">
            <%= account_display_name(account) %>
          </span>
          <span class="font-mono text-xs uppercase tracking-[0.2em] text-quantum-300">
            Select
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

  @spec active_character_name(Sigil.Sui.Types.Character.t() | nil, Account.t()) :: String.t()
  defp active_character_name(%{metadata: %{name: name}}, _account) when is_binary(name), do: name
  defp active_character_name(nil, %Account{characters: []}), do: "No characters synced"
  defp active_character_name(_, _account), do: "Commander profile"

  @spec active_character_tribe_label(Sigil.Sui.Types.Character.t() | nil) :: String.t()
  defp active_character_tribe_label(%{tribe_id: 0}), do: "Unaligned"

  defp active_character_tribe_label(%{tribe_id: tribe_id}) when is_integer(tribe_id),
    do: "Tribe #{tribe_id}"

  defp active_character_tribe_label(_character), do: "Unaligned"

  @spec character_name(Sigil.Sui.Types.Character.t()) :: String.t()
  defp character_name(%{metadata: %{name: name}}) when is_binary(name), do: name
  defp character_name(_character), do: "Unknown Character"

  @spec character_tribe_label(Sigil.Sui.Types.Character.t()) :: String.t()
  defp character_tribe_label(%{tribe_id: 0}), do: "Unaligned"

  defp character_tribe_label(%{tribe_id: tribe_id}) when is_integer(tribe_id),
    do: "Tribe #{tribe_id}"

  defp character_tribe_label(_character), do: "Unaligned"

  @spec account_display_name(map()) :: String.t()
  defp account_display_name(%{"label" => label}) when is_binary(label), do: label

  defp account_display_name(%{"address" => address}) when is_binary(address),
    do: truncate_id(address)

  defp account_display_name(_account), do: "Unknown Account"

  @spec wallet_name(map()) :: String.t()
  defp wallet_name(%{"name" => name}) when is_binary(name), do: name
  defp wallet_name(%{name: name}) when is_binary(name), do: name
  defp wallet_name(_wallet), do: "Unknown Wallet"

  @spec type_counts([term()]) :: [{String.t(), non_neg_integer()}]
  defp type_counts(assemblies) do
    assemblies
    |> Enum.group_by(&assembly_type_label/1)
    |> Enum.map(fn {type, list} -> {type, length(list)} end)
    |> Enum.sort_by(fn {type, _} -> type end)
  end
end
