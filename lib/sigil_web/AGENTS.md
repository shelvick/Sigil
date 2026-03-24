# lib/sigil_web/

## Modules

- `SigilWeb` (`sigil_web.ex`) — Module use macros: `:controller`, `:live_view`, `:html`, `:verified_routes`
- `SigilWeb.Endpoint` (`endpoint.ex`) — Bandit HTTP server, LiveView socket, static assets, session config
- `SigilWeb.Router` (`router.ex`) — Browser + API pipelines, `live_session :wallet_session` with `WalletSession` on_mount, session controller routes, health check, dev LiveDashboard
- `SigilWeb.WalletSession` (`wallet_session.ex`) — LiveView on_mount hook: resolves cache_tables, pubsub, current_account, active_character, and static_data (from session cookie / app resolver)
- `SigilWeb.CacheResolver` (`cache_resolver.ex`) — Shared supervisor lookup for Cache tables, MonitorSupervisor PID, and StaticData PID (used by WalletSession + SessionController + LiveViews)
- `SigilWeb.MonitorHelpers` (`monitor_helpers.ex`) — Shared helpers: monitor_dependencies/1 (resolve supervisor + registry), initial_depletion/1 (compute depletion for mount), relative_depletion_label/1 (format countdown text)
- `SigilWeb.AssemblyHelpers` (`assembly_helpers.ex`) — Shared display helpers: type labels, names, status badges, fuel gauges, ID truncation, descriptions, extension labels, location hashes, burn rates, timestamps, energy labels
- `SigilWeb.Layouts` (`components/layouts.ex`) — Root + app layout templates, `truncate_wallet/1`, `character_display_name/1`, `character_tribe_label/1`
- `SigilWeb.SessionController` (`controllers/session_controller.ex`) — POST/DELETE /session + PUT /session/character/:id: zkLogin-verified wallet auth, active character switching, friendly error messages
- `SigilWeb.DashboardLive` (`live/dashboard_live.ex`) — Dashboard at `/`: multi-account wallet connect (unauth), character-scoped assembly manifest (auth), character picker, alerts summary widget, PubSub subscriptions for assemblies + alerts, monitor-driven updates via ensure_monitors
- `SigilWeb.DashboardLive.Components` (`live/dashboard_components.ex`) — Template components: authenticated_view (with character picker), alerts_summary, assembly_manifest, wallet_connect_view, wallet_state_panel (idle/connecting/account_selection/signing/error)
- `SigilWeb.AlertsLive` (`live/alerts_live.ex`) — Alerts at `/alerts`: account-scoped feed, acknowledge/dismiss actions, PubSub refresh, infinite scroll pagination, ownership-safe mutations
- `SigilWeb.AlertsLive.Components` (`live/alerts_live/components.ex`) — Template components: alerts_header (unread badge, dismissed toggle), alerts_feed (card list, mutation actions, infinite-scroll sentinel), sentinel_classes
- `SigilWeb.AlertsHelpers` (`alerts_helpers.ex`) — Shared alert display helpers: card_classes, severity_badge_classes, type_label, message_classes, timestamp_label
- `SigilWeb.AssemblyDetailLive` (`live/assembly_detail_live.ex`) — Detail at `/assembly/:id`: type-specific rendering, fuel/energy/connection panels, fuel depletion prediction with FuelCountdown JS hook, gate extension management (authorize via wallet signing), intel location display + Set Location action, monitor-driven PubSub updates
- `SigilWeb.AssemblyDetailLive.Components` (`live/assembly_detail_live/components.ex`) — Extracted template components: location_panel (location card + Set Location form), type_specific_section (gate/turret/storage/network_node/assembly)
- `SigilWeb.AssemblyDetailLive.IntelHelpers` (`live/assembly_detail_live/intel_helpers.ex`) — Intel helpers: current_tribe_id/2, intel_enabled?/2, intel_opts/3, character_name/1, resolve_location_name/2
- `SigilWeb.TribeOverviewLive` (`live/tribe_overview_live.ex`) — Tribe overview at `/tribe/:tribe_id`: member list, assembly aggregation, custodian standings summary, intel summary, and PubSub updates
- `SigilWeb.TribeOverviewLive.Components` (`live/tribe_overview_live/components.ex`) — Extracted template components: tribe_header, members_panel, assemblies_panel, intel_panel, standings_panel
- `SigilWeb.IntelLive` (`live/intel_live.ex`) — Intel feed at `/tribe/:tribe_id/intel`: report submission (location/scouting), solar system datalist picker, report feed with delete, PubSub real-time updates
- `SigilWeb.IntelLive.Components` (`live/intel_live/components.ex`) — Extracted template components: report_entry_panel (form + toggle), report_feed_panel (card list + delete)
- `SigilWeb.IntelHelpers` (`intel_helpers.ex`) — Shared intel display helpers: relative_timestamp_label/1 and /2 ("Just now", "5m ago", "2h ago", "3d ago")
- `SigilWeb.IntelMarketLive` (`live/intel_market_live.ex`) — Marketplace page: browse listings, sell intel (ZK proof + wallet sign), my listings. PubSub real-time updates.
  - `.State` (`live/intel_market_live/state.ex`) — State/form/filter helpers
  - `.Transactions` (`live/intel_market_live/transactions.ex`) — Transaction workflows
  - `.Components` (`live/intel_market_live/components.ex`) — Template components (filter_bar, listing_card, sell_form, proof_status, my_listings_panel)
- `SigilWeb.DiplomacyLive` (`live/diplomacy_live.ex`) — Diplomacy editor at `/tribe/:tribe_id/diplomacy`: custodian discovery state machine, leader/non-leader split, standings CRUD, wallet tx signing flow, PubSub updates
- `SigilWeb.DiplomacyLive.Components` (`live/diplomacy_components.ex`) — Extracted template components: `no_custodian_view`, `discovery_error_view`, `signing_overlay`, `tribe_standings_section`, `pilot_overrides_section`, `default_standing_section` + display helpers
- `SigilWeb.TribeHelpers` (`tribe_helpers.ex`) — Shared tribe authorization + diplomacy display helpers: `authorize_tribe/2`, `standing_display/1`, `nbsi_nrds_label/1`
- `SigilWeb.HealthController` (`controllers/health_controller.ex`) — GET /api/health → `{"status":"ok"}`
- `SigilWeb.ErrorHTML` (`controllers/error_html.ex`) — Error page rendering
- `SigilWeb.Telemetry` (`telemetry.ex`) — Phoenix + Ecto telemetry metrics

## Key Functions

### WalletSession (wallet_session.ex)
- `on_mount/4`: Resolves cache_tables, pubsub, current_account, active_character, and static_data from session → socket assigns

### CacheResolver (cache_resolver.ex)
- `application_cache_tables/0`: Supervisor.which_children lookup for Cache PID → `Cache.tables/1`
- `application_monitor_supervisor/0`: Supervisor.which_children lookup for MonitorSupervisor PID → `pid | nil`
- `application_static_data/0`: Supervisor.which_children lookup for StaticData PID → `pid | nil`

### AssemblyHelpers (assembly_helpers.ex)
- `assembly_type_label/1`: Struct → `"Gate" | "Turret" | "NetworkNode" | "StorageUnit" | "Assembly"`
- `assembly_name/1`: Metadata name or truncated ID fallback
- `assembly_status/1`: Status atom → string
- `assembly_description/1`: Metadata description or `"No description provided"`
- `status_badge_classes/1`: `:online` → success, `:offline` → warning, default → `space-600`
- `fuel_label/1`, `fuel_percent/1`, `fuel_percent_label/1`: Fuel display helpers
- `truncate_id/1`: `"0xabcd1234...ef78"` truncation for hex IDs
- `truncate_or_placeholder/1`: Truncate or `"Not set"` for nil
- `linked_gate_label/1`, `extension_label/1`, `extension_active?/1`: Gate/extension display helpers
- `format_location_hash/1`: Binary hash → truncated hex string
- `format_burn_rate/1`: Milliseconds → `"N per hour" | "N per minute" | "N ms"`
- `format_timestamp/2`: Sui ms timestamp → `"YYYY-MM-DD HH:MM:SS UTC"` or `"Not burning"`
- `yes_no/1`, `optional_integer/1`: Boolean/optional formatting
- `energy_current_label/1`, `available_energy/1`: Energy source display helpers

### SessionController (controllers/session_controller.ex)
- `create/2`: auth_params → verify_wallet (`ZkLoginVerifier`) → register_wallet → put_session → redirect (`post_auth_path`)
- `update_character/2`: PUT `/session/character/:id` → validate ownership → put_session(`:active_character_id`) → redirect
- `delete/2`: clear_session + drop → redirect
- `friendly_error/1`: Maps error atoms/tuples to user-facing messages

### DashboardLive (live/dashboard_live.ex)
- `mount/3`: assign_base_state → maybe_load_assemblies (character-scoped) → maybe_load_alert_summary → maybe_subscribe → maybe_ensure_monitors
- `handle_event("wallet_detected")`: Store wallets, auto-connect if single, ignore during active auth/account_selection
- `handle_event("wallet_accounts")`: Multi-account → store accounts, set `:account_selection` state
- `handle_event("select_account")`: Push `select_account` to JS hook with chosen index
- `handle_event("wallet_connected")`: Generate nonce via `ZkLoginVerifier`, push `request_sign`
- `handle_event("wallet_account_changed")`: Flash `re-authenticate to switch` notification
- `handle_event("wallet_error")`: Flash error + set error state with retry
- `handle_info({:alert_created, _})`, `handle_info({:alert_acknowledged, _})`, `handle_info({:alert_dismissed, _})`: Refresh alerts summary window + unread count from PubSub
- `active_character_ids/1`: Returns `[active_character.id]` or `[]` for character-scoped discovery

### DashboardLive.Components (live/dashboard_components.ex)
- `authenticated_view/1`: Wallet panel (active character name/tribe) + character picker + session controls + alerts summary + assembly manifest + `View Tribe` link (when `tribe_id` present)
- `alerts_summary/1`: Dashboard alert relay widget with unread badge, active alert cards, and `View All Alerts` link
- `assembly_manifest/1`: Assembly table with type/name/status/fuel columns
- `wallet_connect_view/1`: Wallet connect prompt + button + state panel
- `wallet_state_panel/1`: Multi-clause: idle/connecting/account_selection/signing/error
- `account_display_name/1`: Label or truncated address fallback
- `active_character_name/2`, `active_character_tribe_label/1`, `character_name/1`, `character_tribe_label/1`: Display helpers

### AlertsLive (live/alerts_live.ex)
- `mount/3`: Require authenticated account → assign base state → load paginated feed + unread count → subscribe account alert topic
- `handle_event("acknowledge")`, `handle_event("dismiss")`: Parse alert id → perform ownership-safe lifecycle mutation via `Alerts` → refresh visible window + unread count
- `handle_event("toggle_dismissed")`: Flip dismissed-history mode → reset feed window + unread count
- `handle_event("load_more")`: Page older alerts using `before_id` cursor from the last loaded alert
- `handle_info({:alert_created, _})`, `handle_info({:alert_acknowledged, _})`, `handle_info({:alert_dismissed, _})`: Refresh current window + unread count after PubSub events

### AlertsLive.Components (live/alerts_live/components.ex)
- `alerts_header/1`: Page header with unread badge + Show/Hide Dismissed toggle
- `alerts_feed/1`: Alert cards with type/severity badges, assembly link, acknowledge/dismiss buttons, and infinite-scroll sentinel
- `sentinel_classes/1`: Sentinel visibility classes for `InfiniteScroll`

### AlertsHelpers (alerts_helpers.ex)
- `card_classes/1`: Alert status → card chrome (`new`, `acknowledged`, `dismissed`)
- `severity_badge_classes/1`: Severity → badge palette (`critical`, `warning`, default info)
- `type_label/1`: Alert type → display label (`Fuel Low`, `Fuel Critical`, etc.)
- `message_classes/1`: Alert status → body copy color
- `timestamp_label/1`: Alert timestamp → relative label via `IntelHelpers.relative_timestamp_label/1`

### AssemblyDetailLive (live/assembly_detail_live.ex)
- `mount/3`: fetch_assembly from cache → assign (incl. signing_state, is_owner, depletion, location_report) → subscribe assembly + intel topics → ensure_monitors (or redirect if not found)
- `handle_event("authorize_extension")`: Build gate extension tx → push `request_sign_transaction` → set signing_state
- `handle_event("set_location")`: Resolve system name via StaticData → `Intel.report_location/2` → update location display
- `handle_event("transaction_signed")`: Submit signed tx → flash success → push `report_transaction_effects`
- `handle_event("transaction_error")`: Reset signing_state → flash error
- `handle_event("wallet_detected" | "wallet_error")`: No-op handlers for hook discovery events
- `handle_info({:assembly_monitor, _id, payload})`: Replace assembly + depletion assigns from monitor payload, reset signing_state if `:submitted`
- `handle_info({:assembly_updated, assembly})`: Replace assembly assigns, reset signing_state if `:submitted` (non-monitor paths)
- `handle_info({:intel_updated, report})`: Update location report if a matching assembly location report arrives
- `handle_info({:intel_deleted, report})`: Clear location report if the matching report is deleted

### TribeOverviewLive (live/tribe_overview_live.ex)
- `mount/3`: authorize → assign base state → subscribe `"tribes"`, `"diplomacy"`, and `"intel:#{tribe_id}"` (when intel cache exists) → load tribe data → load standings data → load member assemblies → load intel summary
- `load_standings_data/1`: derives `has_custodian` from `Diplomacy.get_active_custodian/1`, loads tribe-scoped standings summary + default standing
- `handle_info({:tribe_discovered, _})`: Refresh members + assemblies
- `handle_info({:standing_updated, _})`, `handle_info({:default_standing_updated, _})`: Refresh standings summary
- `handle_info({:custodian_discovered, _})`, `handle_info({:custodian_created, _})`: Refresh diplomacy CTA state
- `handle_info({:intel_updated, _})`, `handle_info({:intel_deleted, _})`: Reload intel summary counts

### IntelLive (live/intel_live.ex)
- `mount/3`: authorize_tribe → load reports + warm cache + load solar systems → subscribe intel topic
- `handle_event("submit_report")`: Resolve system name → persist report → reload feed
- `handle_event("toggle_report_type")`: Switch `:location` / `:scouting`, reset form
- `handle_event("delete_report")`: `Intel.delete_intel/3` → flash result → reload
- `handle_info({:intel_updated, report})`: Replace/prepend report in feed (upsert-aware for locations)
- `handle_info({:intel_deleted, report})`: Remove report from feed

### DiplomacyLive (live/diplomacy_live.ex)
- `mount/3`: authorize → assign base state → discover custodian state → load standings → subscribe `"diplomacy"`
- `discover_custodian_state/1`: connected mount discovers custodian from chain; disconnected mount uses cached active custodian; failure enters `:discovery_error`
- `apply_discovered_custodian/2`: sets `:no_custodian`, `:active`, or `:active_readonly` and updates `is_leader`
- Events: `create_custodian`, `retry_discovery`, `add_tribe_standing`, `set_standing`, `batch_set_standings`, `add_pilot_override`, `set_default_standing`, `filter_tribes`, `transaction_signed`, `transaction_error`
- Page states: `:loading -> :no_custodian | :discovery_error | :active | :active_readonly -> :signing_tx`
- `maybe_refresh_after_submission/1`: re-discovers custodian after successful creation when returning from `:no_custodian`

### DiplomacyLive.Components (live/diplomacy_components.ex)
- `no_custodian_view/1`: Custodian creation CTA + 5-tier standings explainer
- `discovery_error_view/1`: Discovery failure card + retry CTA
- `signing_overlay/1`: Wallet approval overlay
- `tribe_standings_section/1`: Search, tribe standings table, leader-only inline edit + add form, non-leader banner
- `pilot_overrides_section/1`: Pilot standings table + leader-only add form
- `default_standing_section/1`: Standing badge + `NBSI/NRDS` label + leader-only action buttons
- `standing_badge_classes/1`, `standing_options/0`, `standing_value/1`: Display helpers for the 5-tier model

### TribeHelpers (tribe_helpers.ex)
- `authorize_tribe/2`: tribe_id_string × socket → `{:ok, integer} | {:error, :unauthorized | :unauthenticated}`
- `standing_display/1`: standing atom → user-facing label
- `nbsi_nrds_label/1`: standing atom → `"NBSI" | "NRDS"`

## Patterns

- Session DI: on_mount checks session for `"cache_tables"` / `"pubsub"` / `"static_data"` (test injection) before CacheResolver fallback
- LiveView connected? guard: PubSub subscribe + ensure_monitors only on connected mount
- Disconnected mount: pre-populate from ETS cache for fast static render
- Row navigation: `phx-click={JS.navigate(...)}` on table rows
- Diplomacy UI is custodian-first: no table-selection state, no legacy `create_table` / `select_table` events, no `no_table` copy
- Leader/non-leader split is render-driven via `is_leader` and page state (`:active` vs `:active_readonly`)
- EVE Frontier theme tokens: `quantum-*` (accents), `space-*` (backgrounds), `success`/`warning` (status), `cream`/`foreground` (text)

## Dependencies

- `Sigil.Accounts` — wallet registration + account lookup
- `Sigil.Assemblies` — assembly discovery, listing, sync
- `Sigil.Cache` — ETS table resolution (including `:nonces` for auth)
- `Sigil.Sui.ZkLoginVerifier` — challenge nonce generation + zkLogin verification
- `Sigil.Diplomacy` — custodian discovery, standings CRUD, tx building, tribe name resolution
- `Sigil.Tribes` — tribe member discovery + assembly aggregation
- `Sigil.GameState.MonitorSupervisor` — persistent assembly monitoring (ensure_monitors)
- `Sigil.GameState.FuelAnalytics` — fuel depletion computation (initial_depletion)
- `Sigil.Intel` — tribe-scoped intel CRUD (`report_location`, `report_scouting`, `list_intel`, `get_location`, `delete_intel`)
- `Sigil.Alerts` — account-scoped alert listing, unread counts, acknowledge/dismiss lifecycle, PubSub topics
- `Sigil.StaticData` — solar system name resolution + datalist population
- `Phoenix.PubSub` — real-time updates

## JS Hooks

- `assets/js/hooks/wallet_hook.js` — WalletConnect hook: Sui Wallet Standard discovery, EVE Vault preference, multi-account selection (`pendingAccounts` + `select_account`), `signPersonalMessage` (auth), `signTransaction` (diplomacy + gate extension), `reportTransactionEffects` (wallet cache update), wallet change detection, hidden form POST. Registered in `assets/js/app.js`.
- `assets/js/hooks/fuel_countdown.js` — FuelCountdown hook: reads `data-depletes-at` ISO timestamp, runs `setInterval(1000)` countdown displaying `Xh Ym Zs`, handles updated/destroyed lifecycle, sentinel values for not-burning/no-fuel. Registered in `assets/js/app.js`.
- `assets/js/hooks/infinite_scroll.js` — InfiniteScroll hook: observes the alerts feed sentinel with `IntersectionObserver`, pushes `load_more`, disconnects/rebinds on update, and stops when `data-has-more="false"`. Registered in `assets/js/app.js`.
