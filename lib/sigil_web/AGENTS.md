# lib/sigil_web/

## Modules

- `SigilWeb` (`sigil_web.ex`) — Module use macros: `:controller`, `:live_view`, `:html`, `:verified_routes`
- `SigilWeb.Endpoint` (`endpoint.ex`) — Bandit HTTP server, LiveView socket, static assets, session config
- `SigilWeb.Router` (`router.ex`) — Browser + API pipelines, `live_session :wallet_session` with `WalletSession` on_mount, session controller routes, health check, dev LiveDashboard
- `SigilWeb.WalletSession` (`wallet_session.ex`) — LiveView on_mount hook: resolves cache_tables, pubsub, current_account, active_character (from session cookie)
- `SigilWeb.CacheResolver` (`cache_resolver.ex`) — Shared supervisor lookup for Cache tables and MonitorSupervisor PID (used by WalletSession + SessionController + LiveViews)
- `SigilWeb.MonitorHelpers` (`monitor_helpers.ex`) — Shared helpers: monitor_dependencies/1 (resolve supervisor + registry), initial_depletion/1 (compute depletion for mount), relative_depletion_label/1 (format countdown text)
- `SigilWeb.AssemblyHelpers` (`assembly_helpers.ex`) — Shared display helpers: type labels, names, status badges, fuel gauges, ID truncation, descriptions, extension labels, location hashes, burn rates, timestamps, energy labels
- `SigilWeb.Layouts` (`components/layouts.ex`) — Root + app layout templates, `truncate_wallet/1`, `character_display_name/1`, `character_tribe_label/1`
- `SigilWeb.SessionController` (`controllers/session_controller.ex`) — POST/DELETE /session + PUT /session/character/:id: zkLogin-verified wallet auth, active character switching, friendly error messages
- `SigilWeb.DashboardLive` (`live/dashboard_live.ex`) — Dashboard at `/`: multi-account wallet connect (unauth), character-scoped assembly manifest (auth), character picker, PubSub subscriptions, monitor-driven updates via ensure_monitors
- `SigilWeb.DashboardLive.Components` (`live/dashboard_components.ex`) — Template components: authenticated_view (with character picker), assembly_manifest, wallet_connect_view, wallet_state_panel (idle/connecting/account_selection/signing/error)
- `SigilWeb.AssemblyDetailLive` (`live/assembly_detail_live.ex`) — Detail at `/assembly/:id`: type-specific rendering (Gate/Turret/StorageUnit/NetworkNode/Assembly), fuel/energy/connection panels, fuel depletion prediction with FuelCountdown JS hook, gate extension management (authorize via wallet signing), monitor-driven PubSub updates
- `SigilWeb.TribeOverviewLive` (`live/tribe_overview_live.ex`) — Tribe overview at `/tribe/:tribe_id`: member list (connected vs chain-only), assembly aggregation, standings summary, PubSub updates
- `SigilWeb.DiplomacyLive` (`live/diplomacy_live.ex`) — Diplomacy editor at `/tribe/:tribe_id/diplomacy`: page state machine, standings CRUD, wallet tx signing flow, PubSub updates
- `SigilWeb.DiplomacyLive.Components` (`live/diplomacy_components.ex`) — Extracted template components: no_table_view, select_table_view, signing_overlay, tribe_standings_section, pilot_overrides_section, default_standing_section + display helpers
- `SigilWeb.TribeHelpers` (`tribe_helpers.ex`) — Shared tribe authorization: authorize_tribe/2 validates URL tribe_id matches current_account
- `SigilWeb.HealthController` (`controllers/health_controller.ex`) — GET /api/health → `{"status":"ok"}`
- `SigilWeb.ErrorHTML` (`controllers/error_html.ex`) — Error page rendering
- `SigilWeb.Telemetry` (`telemetry.ex`) — Phoenix + Ecto telemetry metrics

## Key Functions

### WalletSession (wallet_session.ex)
- `on_mount/4`: Resolves cache_tables, pubsub, current_account, active_character from session → socket assigns

### CacheResolver (cache_resolver.ex)
- `application_cache_tables/0`: Supervisor.which_children lookup for Cache PID → Cache.tables/1
- `application_monitor_supervisor/0`: Supervisor.which_children lookup for MonitorSupervisor PID → pid | nil

### AssemblyHelpers (assembly_helpers.ex)
- `assembly_type_label/1`: Struct → "Gate"/"Turret"/"NetworkNode"/"StorageUnit"/"Assembly"
- `assembly_name/1`: Metadata name or truncated ID fallback
- `assembly_status/1`: Status atom → string
- `assembly_description/1`: Metadata description or "No description provided"
- `status_badge_classes/1`: :online → success, :offline → warning, default → space-600
- `fuel_label/1`, `fuel_percent/1`, `fuel_percent_label/1`: Fuel display helpers
- `truncate_id/1`: "0xabcd1234...ef78" truncation for hex IDs
- `truncate_or_placeholder/1`: Truncate or "Not set" for nil
- `linked_gate_label/1`, `extension_label/1`, `extension_active?/1`: Gate/extension display helpers
- `format_location_hash/1`: Binary hash → truncated hex string
- `format_burn_rate/1`: Milliseconds → "N per hour"/"N per minute"/"N ms"
- `format_timestamp/2`: Sui ms timestamp → "YYYY-MM-DD HH:MM:SS UTC" or "Not burning"
- `yes_no/1`, `optional_integer/1`: Boolean/optional formatting
- `energy_current_label/1`, `available_energy/1`: Energy source display helpers

### SessionController (controllers/session_controller.ex)
- `create/2`: auth_params → verify_wallet (ZkLoginVerifier) → register_wallet → put_session → redirect (post_auth_path)
- `update_character/2`: PUT /session/character/:id → validate ownership → put_session(:active_character_id) → redirect
- `delete/2`: clear_session + drop → redirect
- `friendly_error/1`: Maps error atoms/tuples to user-facing messages

### DashboardLive (live/dashboard_live.ex)
- `mount/3`: assign_base_state → maybe_load_assemblies (character-scoped) → maybe_subscribe → maybe_ensure_monitors
- `handle_event("wallet_detected")`: Store wallets, auto-connect if single, ignore during active auth/account_selection
- `handle_event("wallet_accounts")`: Multi-account → store accounts, set :account_selection state
- `handle_event("select_account")`: Push select_account to JS hook with chosen index
- `handle_event("wallet_connected")`: Generate nonce via ZkLoginVerifier, push request_sign
- `handle_event("wallet_account_changed")`: Flash "re-authenticate to switch" notification
- `handle_event("wallet_error")`: Flash error + set error state with retry
- `active_character_ids/1`: Returns `[active_character.id]` or `[]` for character-scoped discovery

### DashboardLive.Components (live/dashboard_components.ex)
- `authenticated_view/1`: Wallet panel (active character name/tribe) + character picker + session controls + assembly manifest + "View Tribe" link (when tribe_id present)
- `assembly_manifest/1`: Assembly table with type/name/status/fuel columns
- `wallet_connect_view/1`: Wallet connect prompt + button + state panel
- `wallet_state_panel/1`: Multi-clause: idle/connecting/account_selection/signing/error
- `account_display_name/1`: Label or truncated address fallback
- `active_character_name/2`, `active_character_tribe_label/1`, `character_name/1`, `character_tribe_label/1`: Display helpers

### AssemblyDetailLive (live/assembly_detail_live.ex)
- `mount/3`: fetch_assembly from cache → assign (incl. signing_state, is_owner, depletion) → subscribe → ensure_monitors (or redirect if not found)
- `handle_event("authorize_extension")`: Build gate extension tx → push request_sign_transaction → set signing_state
- `handle_event("transaction_signed")`: Submit signed tx → flash success → push report_transaction_effects
- `handle_event("transaction_error")`: Reset signing_state → flash error
- `handle_event("wallet_detected"|"wallet_error")`: No-op handlers for hook discovery events
- `handle_info({:assembly_monitor, _id, payload})`: Replace assembly + depletion assigns from monitor payload, reset signing_state if :submitted
- `handle_info({:assembly_updated, assembly})`: Replace assembly assigns, reset signing_state if :submitted (non-monitor paths)

### TribeOverviewLive (live/tribe_overview_live.ex)
- `mount/3`: authorize → load tribe/members/assemblies/standings → subscribe "tribes"+"diplomacy"
- `handle_info({:tribe_discovered, _})`: Refresh members + assemblies
- `handle_info({:standing_updated|:default_standing_updated|:table_discovered, _})`: Refresh standings summary

### DiplomacyLive (live/diplomacy_live.ex)
- `mount/3`: authorize → discover_tables → resolve tribe names → enter page state
- Events: select_table, create_table, add_tribe_standing, set_standing, batch_set_standings, add_pilot_override, set_default_standing, filter_tribes, transaction_signed, transaction_error
- Page states: :loading → :no_table | :select_table | :active ↔ :signing_tx

### TribeHelpers (tribe_helpers.ex)
- `authorize_tribe/2`: tribe_id_string × socket → {:ok, integer} | {:error, :unauthorized | :unauthenticated}

## Patterns

- Session DI: on_mount checks session for "cache_tables"/"pubsub" (test injection) before CacheResolver fallback
- LiveView connected? guard: PubSub subscribe + ensure_monitors only on connected mount
- Disconnected mount: pre-populate from ETS cache for fast static render
- Row navigation: `phx-click={JS.navigate(...)}` on table rows
- EVE Frontier theme tokens: quantum-* (accents), space-* (backgrounds), success/warning (status), cream/foreground (text)

## Dependencies

- `Sigil.Accounts` — wallet registration + account lookup
- `Sigil.Assemblies` — assembly discovery, listing, sync
- `Sigil.Cache` — ETS table resolution (including :nonces for auth)
- `Sigil.Sui.ZkLoginVerifier` — challenge nonce generation + zkLogin verification
- `Sigil.Diplomacy` — standings CRUD, tx building, tribe name resolution
- `Sigil.Tribes` — tribe member discovery + assembly aggregation
- `Sigil.GameState.MonitorSupervisor` — persistent assembly monitoring (ensure_monitors)
- `Sigil.GameState.FuelAnalytics` — fuel depletion computation (initial_depletion)
- `Phoenix.PubSub` — real-time updates

## JS Hooks

- `assets/js/hooks/wallet_hook.js` — WalletConnect hook: Sui Wallet Standard discovery, EVE Vault preference, multi-account selection (pendingAccounts + select_account), signPersonalMessage (auth), signTransaction (diplomacy + gate extension), reportTransactionEffects (wallet cache update), wallet change detection, hidden form POST. Registered in `assets/js/app.js`.
- `assets/js/hooks/fuel_countdown.js` — FuelCountdown hook: reads `data-depletes-at` ISO timestamp, runs `setInterval(1000)` countdown displaying "Xh Ym Zs", handles updated/destroyed lifecycle, sentinel values for not-burning/no-fuel. Registered in `assets/js/app.js`.
