# lib/sigil/alerts/

## Modules

- `Sigil.Alerts` (`../alerts.ex`) — Alert lifecycle context: create/dedup/cooldown/acknowledge/dismiss, webhook config upsert, PubSub broadcast. First Repo-backed context
- `Sigil.Alerts.Alert` (`alert.ex`) — Ecto schema: type/severity/status enums, partial unique index for active dedup, status_changeset for lifecycle transitions
- `Sigil.Alerts.WebhookConfig` (`webhook_config.ex`) — Ecto schema: per-tribe Discord webhook URL with service_type validation
- `Sigil.Alerts.Engine` (`engine.ex`) — Singleton GenServer: discovers monitors from Registry, subscribes to PubSub topics, evaluates rules, persists alerts, dispatches webhooks
- `Sigil.Alerts.Engine.Dispatcher` (`engine/dispatcher.ex`) — Async Task.start webhook delivery with Mox/Req.Test ownership wiring for spawned tasks
- `Sigil.Alerts.Engine.RuleEvaluator` (`engine/rule_evaluator.ex`) — Pure rule evaluation: fuel_low (<20%), fuel_critical (<2h depletion, suppresses fuel_low), assembly_offline, extension_changed
- `Sigil.Alerts.WebhookNotifier` (`webhook_notifier.ex`) — Behaviour: `deliver/3` callback for webhook delivery implementations
- `Sigil.Alerts.WebhookNotifier.Discord` (`webhook_notifier/discord.ex`) — Discord implementation: embed formatting, severity colors, retry-after normalization, single retry for 429/5xx

## Key Functions

### Alerts Context (../alerts.ex)
- `create_alert/2`: attrs × opts → {:ok, Alert.t()} | {:ok, :duplicate} | {:ok, :cooldown} | {:error, changeset} — dedup + cooldown + PubSub
- `list_alerts/2`: filters × opts → [Alert.t()] — account-scoped, newest first, cursor pagination
- `acknowledge_alert/2`: id × opts → {:ok, Alert.t()} | {:error, :not_found} — idempotent
- `dismiss_alert/2`: id × opts → {:ok, Alert.t()} | {:error, :not_found} — sets dismissed_at
- `unread_count/2`: account_address × opts → non_neg_integer()
- `active_alert_exists?/3`: assembly_id × type × opts → boolean
- `get_webhook_config/2`: tribe_id × opts → WebhookConfig.t() | nil
- `upsert_webhook_config/3`: tribe_id × attrs × opts → {:ok, WebhookConfig.t()} | {:error, changeset}
- `purge_old_dismissed/2`: days × opts → {count, nil}

### Engine (engine.ex)
- `start_link/1`: opts → GenServer.on_start()
- `get_state/1`: server → state() — test inspection

### Discord Notifier (webhook_notifier/discord.ex)
- `deliver/3`: alert × config × opts → :ok | {:error, {:webhook_failed, status}} | {:error, {:network_error, reason}}

## Patterns

- Repo-backed context (not ETS) — first in the project
- PubSub topic: `"alerts:#{account_address}"` for lifecycle events
- Options: `pubsub:` (optional), `cooldown_ms:` (optional, default 4h)
- Engine uses injectable funs: `create_alert_fun`, `dispatch_fun`, `subscribe_fun`, `now_fun`, `get_webhook_config_fun`
- Engine resolves Registry/tables lazily with retry on failure
- Webhook notifier: behaviour + compile_env DI (`@notifier Application.compile_env(:sigil, :webhook_notifier)`)
- Req.Test plug injection for Discord HTTP tests

## Dependencies

- `Sigil.Repo` for persistence
- `Sigil.Cache` for ETS owner/tribe resolution in Engine
- `Phoenix.PubSub` for alert lifecycle + monitor lifecycle events
- `Sigil.GameState.MonitorSupervisor` for Registry-based monitor discovery
- `Req` for Discord webhook HTTP
