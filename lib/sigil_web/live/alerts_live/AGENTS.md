# lib/sigil_web/live/alerts_live/

## Modules

- `SigilWeb.AlertsLive.Components` (`components.ex`) — Template components: alerts_header/1 (unread badge, dismissed toggle), alerts_feed/1 (alert card list, action buttons, infinite-scroll sentinel), sentinel_classes/1

## Key Functions

### AlertsLive (../alerts_live.ex)
- `mount/3`: Require authenticated account, assign base state, load paginated account alerts + unread count, subscribe to account alert PubSub topic
- `handle_event("acknowledge")`: Parse alert id, acknowledge via ownership-safe `Alerts.acknowledge_alert/2`, refresh visible window + unread count
- `handle_event("dismiss")`: Parse alert id, dismiss via ownership-safe `Alerts.dismiss_alert/2`, refresh visible window + unread count
- `handle_event("toggle_dismissed")`: Toggle dismissed-history mode, reload feed from page 1, refresh unread count
- `handle_event("load_more")`: Append older alerts using `before_id` cursor from the last loaded alert
- `handle_info({:alert_created, _})`, `handle_info({:alert_acknowledged, _})`, `handle_info({:alert_dismissed, _})`: Refresh current window + unread count after PubSub lifecycle updates

### Components (components.ex)
- `alerts_header/1`: Renders page heading, unread badge, and Show/Hide Dismissed toggle
- `alerts_feed/1`: Renders alert cards with severity/type badges, assembly links, acknowledge/dismiss actions, and `InfiniteScroll` sentinel
- `sentinel_classes/1`: Returns visible vs hidden sentinel classes based on `has_more`

## Dependencies

- `Sigil.Alerts` — account-scoped listing, unread counts, acknowledge/dismiss lifecycle, PubSub topics
- `SigilWeb.AlertsHelpers` — card/status/type/timestamp display helpers
