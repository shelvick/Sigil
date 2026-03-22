# lib/sigil_web/live/tribe_overview_live/

## Modules

- `SigilWeb.TribeOverviewLive.Components` (`components.ex`) — Template components: tribe_header/1 (name, short name tag, member count, diplomacy link), members_panel/1 (sorted member table with connected/chain-only badges), assemblies_panel/1 (grouped by member, type counts, aggregate stats), intel_panel/1 (location + scouting counts, View Intel link), standings_panel/1 (tier count badges, default standing with NBSI/NRDS label, manage standings link)

## Key Functions

### Components (components.ex)
- `tribe_header/1`: Tribe name (fallback to "Tribe #N"), short name tag, member count badge, Diplomacy link
- `members_panel/1`: Sorted members (connected first, then alphabetical), "(you)" marker for active character
- `assemblies_panel/1`: Assembly rows grouped under member names, type count badges, total count, navigation links
- `intel_panel/1`: "X assemblies with known locations", "Y scouting reports", "View Intel" link
- `standings_panel/1`: Tier count badges (Hostile through Allied), default standing with NBSI/NRDS label, "Manage Standings" or "Set Up Diplomacy" link

## Dependencies

- `SigilWeb.AssemblyHelpers` — assembly_type_label, assembly_name, assembly_status, status_badge_classes
- `Sigil.Diplomacy` — standing_atom type for display helpers
