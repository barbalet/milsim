# Milsim Development Plan

## Goal

Build a macOS military-simulation sandbox inspired by the ARMA family: large tactical spaces, grounded weapon handling, item scavenging, squad-scale pressure, and a path toward logistics, command, and scenario authoring. The first implementation target is a playable Xcode prototype in SwiftUI, Metal, and a C gameplay core that supports full-screen play and detachable companion windows for tactical panels.

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
- SwiftUI app shell with detachable mission, operator, tactical map, controls, and loadout windows around Metal rendering
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
- Expanded damage modeling with head wounds, limb fractures, stamina shock, and combat splints so recovery now has separate bleeding and fracture treatment decisions.
- Added wounded-enemy fallback behavior plus pain and bleed penalties so hostile reactions feel less binary than patrol-or-fire.
- Added limited thin-cover penetration through doors and select low walls to start the Cycle 3 penetration-class work.
- Expanded attachment support beyond optics and suppressors with passive laser, weapon-light, and vertical-grip mounting on compatible firearms.
- Broadened surface interaction so projectiles can now degrade through select convoy cover and get softened by concealment foliage before reaching the target.
- Strengthened ballistic signature feedback with weapon report tiers, faster near-miss suppression, and HUD summaries for report, penetration, and mounted attachment state.

### First-Person Presentation First Pass Added

- Added a toggleable first-person presentation layer over the existing C simulation while retaining the tactical overhead view as an alternate camera.
- Projected structures, interactables, items, enemies, tracers, and a held-weapon silhouette into a forward-facing Metal scene with a basic horizon, reticle, and stance-aware camera height.
- Updated the HUD, in-game controls, and app commands so the player can switch presentation modes during a live operation without leaving the mission flow.

### First-Person Presentation Readability Pass Added

- Added a lightweight first-person occlusion field so buildings, convoy wrecks, doors, low walls, towers, ridges, and foliage can suppress targets and pickups behind cover instead of letting every cue stack through the scene.
- Tightened first-person sight readability with optic-ring alignment, iron-sight cues for non-optic weapons, and a closer weapon-to-reticle relationship during movement and recoil.
- Added active attachment feedback in first-person with visible laser beams and dots, light wash and hotspot overlays, plus focus highlights and HUD assist prompts for nearby interactables and field gear.

### Multi-Window Command Shell Added

- Replaced the single in-window pseudo-panel stack with independent macOS windows for mission, operator, tactical map, controls, and loadout views.
- Added panel-window coordination so the companion windows can be reopened from the menu bar and remain usable alongside a full-screen game window.
- Preserved the main battlefield as the authoritative input window so panel launches restore focus back to the live mission instead of trapping movement input in a HUD panel.

### True 3D First-Person World Pass Started

- Replaced the first-person world layer’s flat projected sprites with a depth-tested Metal 3D scene built from terrain tiles, structures, interactables, pickups, enemies, and projectile volumes.
- Separated the 3D battlefield pass from the 2D HUD and weapon overlay so camera composition, depth occlusion, and future sight alignment work can evolve without breaking the command shell.
- Established the rendering foundation for follow-up passes on proper world meshes, terrain silhouette cleanup, viewmodel animation, and more exact optic/laser convergence.

### True 3D First-Person Refinement Pass Added

- Moved the first-person backdrop behind the 3D battlefield and added projected skyline silhouettes so the horizon reads more like distant terrain and structures instead of a flat overlay.
- Refined the procedural 3D scene with more breakup on buildings, towers, and convoy hulks so the world pass is less blocky while it still uses placeholder box geometry.
- Replaced heuristic aim depth and loose focus highlighting with world-hit reticle alignment, depth-aware laser/light placement, projected focus brackets, and tighter aim-corridor HUD prompts.

### First-Person Combat Effects Pass Added

- Added renderer-driven muzzle flashes for the player and enemies so live firefights now throw visible bursts from the weapon line instead of relying on tracers alone.
- Added transient impact puffs and sparks keyed off projectile exits, with first-pass surface/material styling for dirt, stone, road, compound, convoy metal, and foliage strikes.
- Added stronger first-person recoil and viewmodel animation with persistent kick, drift, roll, and walk-driven motion so the weapon and hands now react to fire and movement as a readable combat layer.

### 3D Presentation Materials Pass Added

- Broadened the first-person 3D terrain pass with road markings, compound pads, rock outcrops, mud sheen, grass breakup, and denser forest undergrowth so the battlefield starts reading as layered ground rather than flat placeholder slabs.
- Added a terrain-aware skyline backdrop pass plus more breakup on ridges, buildings, walls, towers, convoys, crates, radios, and emplaced weapons so distance composition and nearby props both feel more authored.
- Expanded impact feedback to use deeper surface-specific styling for stone, metal, mud, dust, and foliage, including secondary debris bursts on harder surfaces, so hits communicate what the round struck at a glance.

### First-Person Weapon Handling Pass Added

- Added renderer-side weapon swap transitions with raise-lower motion, smoother hand repositioning, and stance-aware carry offsets so switching between firearms, blades, and support gear reads as a deliberate presentation beat instead of an abrupt sprite swap.
- Added first-pass reload choreography for firearms with tilted receiver motion, magazine extraction/insertion staging, and support-hand movement timed off live weapon state so reloads finally feel like an action instead of a cooldown number.
- Reworked first-person recoil and melee presentation into spring-driven motion with slash trails, stronger knife swings, and more physical recovery on kick, drift, and roll so close-quarters handling feels more grounded and readable in motion.

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

## First-Person Presentation

- Build a player-centered first-person render path over the existing tactical simulation instead of replacing the C gameplay model.
- Project terrain context, structures, interactables, hostiles, pickups, tracers, and the held weapon into a readable forward-facing scene.
- Preserve the tactical overhead view and map tools as fast-switch command aids while the first-person layer matures.
- Tune occlusion, cover readability, sight alignment, muzzle effects, and interaction prompts for close and mid-range fights.
- Exit criteria: every mission remains playable in first-person with clear orientation, stable combat readability, and quick access to tactical context.

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

## Professional Polish Track

1. Replace the remaining projection-style first-person presentation with a fully realized 3D combat view: cleaner terrain silhouettes, better cover edges, proper world meshes, and exact sight/laser convergence.
2. Establish a coherent visual art direction across terrain, structures, props, pickups, materials, lighting, fog, muzzle flashes, and impact effects so the game stops reading as a prototype.
3. Build a real animation layer for locomotion, stance changes, vaulting, reloads, recoil, melee, hit reactions, and deaths so combat and movement feel authored rather than abstract.
4. Ship a production audio pass with distance-based gun reports, suppression cracks, footsteps by surface, gear handling, ambience, UI sounds, and mix tuning for tactical readability.
5. Redesign the SwiftUI shell and HUD around production hierarchy: scalable text, cleaner information density, clearer urgency states, stronger panel behavior, and less debug-style presentation.
6. Add a complete options stack for graphics quality, resolution behavior, mouse sensitivity, audio buses, key rebinding, fullscreen policy, and accessibility settings.
7. Refine macOS input and window ergonomics so the battlefield, menus, and detachable panels always make focus and control ownership obvious to the player.
8. Deepen AI polish with better cover use, search behavior, communication, suppression reactions, fallback logic, and small-unit coordination for both enemies and future friendlies.
9. Create stronger authored mission presentation with briefings, debriefs, failure framing, progression rewards, and scenario scripting so operations feel curated as well as simulated.
10. Finish with performance, stability, save migration, profiling, and regression coverage so the game is reliable enough for external testers and longer polish cycles.

## Environment and Tooling Plan

- Keep gameplay rules in C for portability and deterministic testing.
- Keep rendering and presentation in Swift/Metal for Apple-platform integration.
- Use SwiftUI for shell UI, settings, debug overlays, and editor tooling.
- Introduce external data for weapons, inventories, factions, and scenarios before content volume grows.
- Add automated build validation with `xcodebuild` and eventually simulation tests around C engine functions.

## Immediate Next Steps

- Start the first authored art-direction pass for terrain, structures, props, fog, and lighting so the improved 3D composition begins converging on a coherent visual language instead of just more detailed primitives.
- Expand mission scripting into branching triggers, authored objective phases, and richer campaign slots once the presentation layer feels stable enough to showcase them.
- Start the first Cycle 4 command-layer pass with friendly AI teammates or lightweight fireteam orders after the combat/readability passes stop moving core rendering assumptions.
