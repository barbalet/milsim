# Milsim Development Plan

## Goal

Build a macOS military-simulation sandbox inspired by the ARMA family: large tactical spaces, grounded weapon handling, item scavenging, squad-scale pressure, and a path toward logistics, command, and scenario authoring. The first implementation target is a playable single-window or full-screen prototype in Xcode using SwiftUI, Metal, and a C gameplay core.

## Genre Research Summary

- Bohemia frames Arma Reforger as a realistic multiplayer sandbox focused on strategic military simulator gameplay, dynamic battle spaces, logistics, cooperative scenarios, and modding through the same toolchain used internally. Source: [Arma Reforger FAQ](https://reforger.armaplatform.com/faq), [Arma Reforger Game](https://reforger.armaplatform.com/game)
- Official Reforger updates highlight helicopters, supply-system overhauls, repair, refuel, resupply, heal loops, and the idea that logistics is gameplay rather than background bookkeeping. Source: [Arma Reforger 1.0 Release](https://reforger.armaplatform.com/news/update-november-16-2023)
- Bohemia’s Arma 3 guidance emphasizes role separation, crew responsibilities, combined arms, communication protocols, and open military sandbox scenarios rather than tightly scripted corridor missions. Source: [Arma 3 Ground Vehicle Crew](https://arma3.com/news/new-arma-3-video-introduces-ground-vehicle-crew)
- Squad positions the milsim-adjacent space around communication, teamplay, vehicles, large maps, and authentic handling rather than pure arcade speed. Source: [Squad Authentic Combat](https://www.joinsquad.com/game-features/authentic-combat)
- A useful design takeaway from the broader genre is “accessible realism”: simulate what creates tactical meaning, then trim what becomes tedious. Source: [PC Gamer on '83](https://www.pcgamer.com/games/fps/83-is-a-milsim-going-for-accessible-realism-in-a-timeline-where-the-cold-war-exploded/)

## Product Pillars

- Authentic tactical pressure: weapons, magazines, suppression, stamina, wounds, line-of-sight pressure.
- Sandbox problem solving: open spaces, multiple approaches, recoverable gear, dynamic objectives, extraction.
- Logistics matter: ammunition, magazines, attachments, medical supplies, repair/refuel/resupply later.
- Readable command layer: clear HUD, contextual orders, map awareness, radio-style reporting.
- Mod-friendly architecture: engine systems in C, rendering in Metal, SwiftUI tools/HUD, data-driven content over time.

## Current Vertical Slice

- macOS app target in Xcode
- SwiftUI HUD layered over Metal rendering
- C simulation core for player state, enemies, projectiles, and inventory
- Collectible bullets, rifles, pistols, blade weapons, suppressors, and magazines
- Windowed play plus full-screen toggle support

## Current Status

### Cycle 1 Completed

- Implemented four mission seeds: cache raid, hostage recovery, recon-and-exfil, and convoy ambush.
- Replaced the flat arena feel with layered roads, ridges, buildings, low walls, convoy obstacles, and concealment foliage.
- Expanded firearms with distinct recoil, muzzle velocity, suppressor compatibility, and selectable fire modes where supported.
- Added infantry posture controls: crouch, prone, lean, and low-cover vaulting.
- Updated the HUD and mission flow so operations can be restarted or advanced to the next seed directly in-app.

### Cycle 2 Completed

- Added a tiled terrain system with material-driven movement and concealment.
- Added interactable gates, supply crates, dead drops, radios, and emplaced weapons across all mission seeds.
- Added a SwiftUI tactical map with compass heading, grid references, objective markers, and radio-unlocked hostile markers.
- Moved weapon definitions, pickup templates, and mission loot tables into bundled JSON so content can be extended without editing the C mission setup.
- Added a navigation graph with gate-aware patrol routes, command-route overlays, persistent marker discovery, and radio traffic summaries.
- The environment now contributes more to route choice and information gathering instead of serving as a flat combat board.
- Residual follow-up: tune the new route graph density per mission and deepen terrain-height effects during detection and firefights.

### Persistence Foundations Added

- Added bundled mission scripts so operation names, briefs, opening orders, and radio chatter can be authored from JSON instead of being hardwired in the C setup functions.
- Added campaign save/load support that archives the live `GameState`, current mission, tactical-map state, and cross-operation progress to disk.
- Added SwiftUI HUD and menu-bar controls for manual save/load so the prototype can be resumed between development sessions.

### Cycle 3 Started

- Added chamber-aware reload handling so firearms track a separate chambered round instead of treating the magazine as the only loaded state.
- Added first-pass suppression, bleeding, pain, and wound tracking for the player, with drag-affected projectile energy and enemy suppression reactions.
- Added combat-gauze treatment from loadout or pickups so the prototype now has a playable wound-treatment loop instead of health pickups only.
- Updated the SwiftUI HUD to surface wound, suppression, bleed, and treatment state in real time during firefights.

## Cycle 0: Foundation and Playable Slice

- Deliver a bootable macOS app with SwiftUI shell, Metal renderer, and C engine.
- Ship a small tactical raid map with player movement, aiming, firing, enemy patrols, pickup logic, reloads, stamina, and extraction.
- Stand up project conventions: source folders, build settings, shaders, engine headers, and roadmap docs.
- Exit criteria: the game launches from Xcode, runs in a window or full screen, and supports collection of core military items.

## Cycle 1: Infantry Sandbox

- Replace the prototype arena with a layered outdoor training island: ridge lines, compounds, roads, foliage clusters, and cover volumes.
- Expand firearms into classes with recoil signatures, fire modes, muzzle velocity, and attachment slots.
- Add stance changes, lean, prone, vaulting, and better hit reactions.
- Introduce mission seeds: cache raid, hostage recovery, recon-and-exfil, convoy ambush.
- Exit criteria: infantry-only missions feel tactically distinct and support multiple viable routes.

## Cycle 2: Terrain, Navigation, and Interaction

- Add a tiled terrain system with height, materials, and navigation metadata.
- Implement interactable doors, supply crates, dead-drop caches, radios, and emplaced weapons.
- Introduce a 2D tactical map, compass, grid references, and objective markers with limited intelligence.
- Move item definitions to external data files so weapons and loot tables can be extended without engine rewrites.
- Exit criteria: the environment itself becomes a tactical layer rather than a flat combat board.

## Cycle 3: Ballistics, Damage, and Medical Depth

- Simulate muzzle velocity, drag approximation, penetration classes, suppression, and audio signatures.
- Add wound zones, bleeding, pain, fractures, stamina shock, and field dressing mechanics.
- Distinguish loose rounds, magazines, and chambered states more explicitly.
- Expand attachment gameplay with optics, suppressors, lasers, lights, and under-barrel systems.
- Exit criteria: weapon and survival decisions create believable tradeoffs during longer engagements.

## Cycle 4: Squad AI and Command Layer

- Add friendly AI teammates with formation movement, rules of engagement, and breach/hold/flank orders.
- Build enemy AI behavior around patrol plans, alert states, suppression, search, and fallback positions.
- Add radio reports and lightweight command UI in SwiftUI.
- Introduce mission scoring based on stealth, tempo, casualties, and recovered matériel.
- Exit criteria: small-unit leadership becomes a core part of moment-to-moment play.

## Cycle 5: Vehicles and Logistics

- Add drivable ground vehicles first, then helicopters.
- Model crew roles, cargo capacity, fuel, field repair, and resupply.
- Build depots, forward arming points, and convoy gameplay loops.
- Expand maps to support insertion planning, vehicle routes, and extraction under pressure.
- Exit criteria: logistics and mobility reshape how missions are planned and won.

## Cycle 6: Scenario Authoring and Persistence

- Add a scenario editor for spawn zones, patrol routes, objectives, loot tables, and extraction logic.
- Save campaign state across operations: captured depots, destroyed assets, recovered intelligence, squad readiness.
- Create authored scenarios and dynamic operations using the same data schema.
- Add replay/debug tools for AI timelines, projectile traces, and encounter tuning.
- Exit criteria: content creation accelerates without needing engine rewrites for each mission.

## Cycle 7: Networked Operations

- Design deterministic or server-authoritative simulation boundaries.
- Replicate player state, inventory, projectiles, AI intent, and mission events.
- Add dedicated-host flow, session browser, drop-in co-op, and spectator/admin tools.
- Preserve the single-player path by keeping simulation systems authoritative independent of UI.
- Exit criteria: cooperative operations are stable enough for repeated playtests.

## Cycle 8: Production Hardening

- Replace placeholder art and primitive meshes with a coherent visual language.
- Add audio mixing, ambient soundscapes, VO/radio callouts, and accessibility settings.
- Profile AI, rendering, memory, and content streaming.
- Formalize test plans for simulation, save/load, map logic, and multiplayer regression.
- Exit criteria: the game is ready for closed external testing and a longer content roadmap.

## Environment and Tooling Plan

- Keep gameplay rules in C for portability and deterministic testing.
- Keep rendering and presentation in Swift/Metal for Apple-platform integration.
- Use SwiftUI for shell UI, settings, debug overlays, and editor tooling.
- Introduce external data for weapons, inventories, factions, and scenarios before content volume grows.
- Add automated build validation with `xcodebuild` and eventually simulation tests around C engine functions.

## Immediate Next Steps

- Expand Cycle 3 from first-pass treatment into fractures, richer wound zones, and stronger enemy damage-state reactions.
- Add penetration classes, stronger ballistic/audio signatures, and attachment expansion beyond optics and suppressors.
- Expand mission scripting into branching triggers, authored objective phases, and richer campaign slots.
