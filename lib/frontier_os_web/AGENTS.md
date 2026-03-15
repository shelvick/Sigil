# lib/frontier_os_web/

## Modules

- `FrontierOSWeb` (`frontier_os_web.ex`) — Module use macros: `:controller`, `:live_view`, `:html`, `:verified_routes`
- `FrontierOSWeb.Endpoint` (`endpoint.ex`) — Bandit HTTP server, LiveView socket, static assets, session config
- `FrontierOSWeb.Router` (`router.ex`) — Browser + API pipelines, `live_session :wallet_session` with `WalletSession` on_mount, session controller routes, health check, dev LiveDashboard
- `FrontierOSWeb.WalletSession` (`wallet_session.ex`) — LiveView on_mount hook: resolves cache_tables (session injection or CacheResolver), pubsub, current_account
- `FrontierOSWeb.CacheResolver` (`cache_resolver.ex`) — Shared supervisor lookup for Cache tables (used by WalletSession + SessionController)
- `FrontierOSWeb.AssemblyHelpers` (`assembly_helpers.ex`) — Shared display helpers: type labels, names, status badges (success/warning/default), fuel gauges, ID truncation
- `FrontierOSWeb.Layouts` (`components/layouts.ex`) — Root + app layout templates, `truncate_wallet/1`
- `FrontierOSWeb.SessionController` (`controllers/session_controller.ex`) — POST/DELETE /session: wallet registration via Accounts context, friendly error messages
- `FrontierOSWeb.DashboardLive` (`live/dashboard_live.ex`) — Dashboard at `/`: wallet form (unauth), assembly manifest table (auth), PubSub subscriptions, linked StatePoller
- `FrontierOSWeb.AssemblyDetailLive` (`live/assembly_detail_live.ex`) — Detail at `/assembly/:id`: type-specific rendering (Gate/Turret/StorageUnit/NetworkNode/Assembly), fuel/energy/connection panels, PubSub updates
- `FrontierOSWeb.HealthController` (`controllers/health_controller.ex`) — GET /api/health → `{"status":"ok"}`
- `FrontierOSWeb.ErrorHTML` (`controllers/error_html.ex`) — Error page rendering
- `FrontierOSWeb.Telemetry` (`telemetry.ex`) — Phoenix + Ecto telemetry metrics

## Key Functions

### WalletSession (wallet_session.ex)
- `on_mount/4`: Resolves cache_tables, pubsub, current_account from session → socket assigns

### CacheResolver (cache_resolver.ex)
- `application_cache_tables/0`: Supervisor.which_children lookup for Cache PID → Cache.tables/1

### AssemblyHelpers (assembly_helpers.ex)
- `assembly_type_label/1`: Struct → "Gate"/"Turret"/"NetworkNode"/"StorageUnit"/"Assembly"
- `assembly_name/1`: Metadata name or truncated ID fallback
- `assembly_status/1`: Status atom → string
- `status_badge_classes/1`: :online → success, :offline → warning, default → space-600
- `fuel_label/1`, `fuel_percent/1`, `fuel_percent_label/1`: Fuel display helpers
- `truncate_id/1`: "0xabcd1234...ef78" truncation for hex IDs

### SessionController (controllers/session_controller.ex)
- `create/2`: Validate address → register_wallet → put_session → redirect
- `delete/2`: clear_session + drop → redirect

### DashboardLive (live/dashboard_live.ex)
- `mount/3`: assign_base_state → maybe_load_assemblies → maybe_subscribe → maybe_start_poller
- `handle_info({:assemblies_discovered, list})`: Replace assembly list, subscribe to new topics, update poller
- `handle_info({:assembly_updated, assembly})`: Replace single assembly in list

### AssemblyDetailLive (live/assembly_detail_live.ex)
- `mount/3`: fetch_assembly from cache → assign → subscribe → start poller (or redirect if not found)
- `handle_info({:assembly_updated, assembly})`: Replace assembly assigns

## Patterns

- Session DI: on_mount checks session for "cache_tables"/"pubsub" (test injection) before CacheResolver fallback
- LiveView connected? guard: PubSub subscribe + poller start only on connected mount
- Disconnected mount: pre-populate from ETS cache for fast static render
- Row navigation: `phx-click={JS.navigate(...)}` on table rows
- EVE Frontier theme tokens: quantum-* (accents), space-* (backgrounds), success/warning (status), cream/foreground (text)

## Dependencies

- `FrontierOS.Accounts` — wallet registration + account lookup
- `FrontierOS.Assemblies` — assembly discovery, listing, sync
- `FrontierOS.Cache` — ETS table resolution
- `FrontierOS.GameState.Poller` — linked assembly polling
- `Phoenix.PubSub` — real-time updates
