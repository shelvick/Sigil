# lib/sigil_web/live/assembly_detail_live/

## Modules

- `SigilWeb.AssemblyDetailLive.Components` (`components.ex`) — Template components: location_panel/1 (location card + Set/Update Location form with datalist), type_specific_section/1 (gate/turret/storage/network_node/assembly dispatched rendering with fuel panel, depletion forecast, energy panel, connections, signing overlay)
- `SigilWeb.AssemblyDetailLive.IntelHelpers` (`intel_helpers.ex`) — Shared intel helpers: current_tribe_id/2, intel_enabled?/2, intel_opts/3, character_name/1, resolve_location_name/2

## Key Functions

### Components (components.ex)
- `location_panel/1`: Renders location card with solar system name or "Location unknown", optional Set/Update Location form with datalist-backed solar system picker
- `type_specific_section/1`: Multi-clause dispatching on assembly_type — renders gate (linked gate + extension + signing overlay), turret (extension), storage (inventory + item count), network_node (fuel panel + depletion + energy + connections), assembly (unknown type)

### IntelHelpers (intel_helpers.ex)
- `current_tribe_id/2`: Resolves tribe_id from active_character.tribe_id or current_account.tribe_id
- `intel_enabled?/2`: Checks cache_tables has :intel key and tribe_id is present
- `intel_opts/3`: Builds [tables: cache_tables, pubsub: pubsub, authorized_tribe_id: tribe_id]
- `character_name/1`: Extracts display name from Character.metadata.name
- `resolve_location_name/2`: Looks up solar system name via StaticData for a location report

## Dependencies

- `SigilWeb.AssemblyHelpers` — all display helpers (truncate_id, fuel_label, etc.)
- `SigilWeb.DiplomacyLive.Components` — signing_overlay/1
- `SigilWeb.MonitorHelpers` — relative_depletion_label/1
- `Sigil.Intel` — intel context (get_location, report_location)
- `Sigil.StaticData` — solar system lookup
