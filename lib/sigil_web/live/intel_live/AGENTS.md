# lib/sigil_web/live/intel_live/

## Modules

- `SigilWeb.IntelLive.Components` (`components.ex`) — Template components for the intel feed LiveView: report_entry_panel/1 (report type toggle, form fields, solar system datalist, validation states), report_feed_panel/1 (report card list with type badges, system names, truncated assembly IDs, relative timestamps, delete buttons, empty state)

## Key Functions

### Components (components.ex)
- `report_entry_panel/1`: Renders form with type toggle (Location/Scouting), datalist-backed solar system picker, Assembly ID/Label/Notes fields, disabled states for missing character/StaticData/intel storage
- `report_feed_panel/1`: Renders card-based report feed with type badges, system name resolution, assembly links, relative timestamps via IntelHelpers, author-only delete buttons

## Dependencies

- `SigilWeb.AssemblyHelpers` — truncate_id/1 for assembly ID display
- `SigilWeb.IntelHelpers` — relative_timestamp_label/1 for time display
- `Sigil.Intel.IntelReport` — struct type for pattern matching and report_type
