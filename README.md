# MilsimGame

`MilsimGame` is a macOS tactical sandbox prototype built for Xcode with:

- SwiftUI for the app shell and HUD
- Metal for rendering
- C for the gameplay and simulation core

The current build is a playable tactical slice with completed Cycle 2 environment systems, persistence foundations, a broader Cycle 3 combat pass, and a deeper `First-Person Presentation` cycle: run four mission seeds, move through terrain tiles and compounds, use stance and lean to manage exposure, switch fire modes, vault low cover, collect military gear, work gates/crates/radios/emplaced guns, recover objective packages, and extract. Weapons, pickups, mission loot placement, and mission-script text load from bundled JSON, while the tactical map tracks discovered markers, live radio reports, and a command route through the battlefield. The SwiftUI shell can also save and reload a live campaign archive from the HUD or menu bar, and firefights now surface head and limb wounds, fractures, stamina shock, splint treatment, enemy fallback reactions, broader penetration behavior through select cover, vegetation damping, stronger weapon-signature feedback, and a toggleable first-person view with cover-based occlusion, sight-alignment cues, live laser/light feedback, and close-range focus prompts over the same tactical simulation.

## Controls

- `W`, `A`, `S`, `D`: move
- `Shift`: sprint
- Mouse: aim
- Left mouse or `Space`: fire / attack
- `F` or right mouse: use or recover nearby equipment
- `R`: reload current firearm
- `H`: treat wounds / use combat gauze or splints
- `B`: toggle fire mode
- `C`: crouch toggle
- `Z`: prone toggle
- `Q` / `E`: lean left / right
- `V`: vault low cover
- `Tab` or mouse wheel: cycle equipment
- `1`: primary weapon
- `2`: sidearm
- `3`: blade weapon
- `P`: toggle first-person presentation or tactical overhead view
- `M`: expand or collapse the tactical map
- `Command` + `S`: save the current campaign archive
- `Command` + `L`: load the latest campaign archive
- `Control` + `Command` + `F`: toggle full screen

## Current Prototype Features

- Four mission seeds: cache raid, hostage recovery, recon-and-exfil, convoy ambush
- Tiled terrain metadata in the C engine with materials, concealment, and movement costs
- Navigation nodes and gate-aware route metadata for patrols and tactical planning
- Layered battlefield structures rendered in Metal: ridges, roads, compounds, low walls, towers, convoy hulks, gates, and concealment foliage
- Interactable gates, supply crates, dead drops, radios, and emplaced weapons
- SwiftUI tactical map with grid references, compass heading, discovered markers, command route overlays, radio reports, and radio-gated hostile intel
- Mission, operator, tactical map, controls, and loadout now run as independent macOS windows so they can be moved and resized separately from the game view, with a `Panels` menu to reopen or refocus them if closed
- Toggleable first-person presentation pass with projected structures, enemies, items, tracers, reticle, held-weapon view models, cover-based occlusion, sight-alignment cues, active laser/light overlays, and close-range focus highlighting over the live C simulation
- Bundled JSON item definitions and mission loot tables loaded into the C engine at startup
- Bundled JSON mission scripts for brief, initial-event, and radio-callout overrides
- C simulation support for stance, lean, vaulting, fire modes, chamber-aware reloads, drag-affected projectiles, selective cover penetration, vegetation damping, suppression, bleeding, pain, head and limb wound zones, fractures, stamina shock, gauze-and-splint treatment, suppressor and passive attachment mounting, enemy fallback reactions, and objective extraction
- Collectible attachment expansion with PEQ-15 lasers, weapon lights, and vertical grips alongside existing rifles, pistols, blades, magazines, suppressors, and medical gear
- SwiftUI HUD support for mission briefs, posture, chamber status, wound state, suppression, interaction hints, inventory state, weapon-signature summaries, first-person assist cues, presentation-mode status, operation cycling, and manual campaign save/load

## Project Layout

- `MilsimGame.xcodeproj`: Xcode project
- `MilsimGame/Engine`: C simulation core
- `MilsimGame/Content`: bundled JSON item definitions, loot tables, and mission scripts
- `MilsimGame/Rendering`: Metal view, renderer, and shaders
- `MilsimGame/UI`: SwiftUI game interface
- `plan.md`: researched multi-cycle roadmap toward a deeper ARMA-like milsim
