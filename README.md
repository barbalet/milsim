# MilsimGame

`MilsimGame` is a macOS tactical sandbox prototype built for Xcode with:

- SwiftUI for the app shell and HUD
- Metal for rendering
- C for the gameplay and simulation core

The current build is a playable tactical slice with completed Cycle 2 environment systems, persistence foundations, a broader Cycle 3 combat pass, and a deeper `First-Person Presentation` cycle: run four mission seeds, move through terrain tiles and compounds, use stance and lean to manage exposure, switch fire modes, vault low cover, collect military gear, work gates/crates/radios/emplaced guns, recover objective packages, and extract. Weapons, pickups, mission loot placement, and mission-script text load from bundled JSON, while the tactical map tracks discovered markers, live radio reports, authored mission phases, outcome branches, and a command route through the battlefield. The SwiftUI shell can also save and reload live campaign archives from Alpha, Bravo, or Charlie slots via the HUD or menu bar, and firefights now surface head and limb wounds, fractures, stamina shock, splint treatment, enemy fallback reactions, broader penetration behavior through select cover, vegetation damping, stronger weapon-signature feedback, and a toggleable first-person view with a depth-tested 3D world pass, terrain-aware skyline layers, richer terrain and prop breakup, warmer/cooler atmospheric lighting, more cohesive field palettes for terrain and props, world-hit sight and laser alignment, depth-aware focus prompts, muzzle flashes, material-specific impact bursts, smoother viewmodel transitions, reload and melee presentation beats, and spring-driven recoil recovery over the same tactical simulation.

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
- Toggleable first-person presentation pass with a depth-tested 3D battlefield layer for terrain, structures, pickups, enemies, and projectiles, plus separated skyline/backdrop rendering, richer terrain material breakup, more detailed prop silhouettes, an authored dust-and-olive field palette, warmer sun / cooler shadow atmospheric fog, overlay reticle, held-weapon view models, cover-based occlusion, world-hit sight alignment, active laser/light overlays, projected close-range focus cues, renderer-driven muzzle flashes, material-specific impact bursts, weapon swap transitions, reload/melee presentation beats, and spring-driven recoil/viewmodel animation over the live C simulation
- Bundled JSON item definitions and mission loot tables loaded into the C engine at startup
- Bundled JSON mission scripts for phase-driven briefs, objective/event overrides, route/intel callouts, and mission-outcome branches
- C simulation support for stance, lean, vaulting, fire modes, chamber-aware reloads, drag-affected projectiles, selective cover penetration, vegetation damping, suppression, bleeding, pain, head and limb wound zones, fractures, stamina shock, gauze-and-splint treatment, suppressor and passive attachment mounting, enemy fallback reactions, and objective extraction
- Collectible attachment expansion with PEQ-15 lasers, weapon lights, and vertical grips alongside existing rifles, pistols, blades, magazines, suppressors, and medical gear
- SwiftUI HUD support for mission briefs, authored phase/branch readouts, posture, chamber status, wound state, suppression, interaction hints, inventory state, weapon-signature summaries, first-person assist cues, presentation-mode status, operation cycling, and manual campaign save/load across Alpha, Bravo, and Charlie archive slots

## Project Layout

- `MilsimGame.xcodeproj`: Xcode project
- `MilsimGame/Engine`: C simulation core
- `MilsimGame/Content`: bundled JSON item definitions, loot tables, and mission scripts
- `MilsimGame/Rendering`: Metal view, renderer, and shaders
- `MilsimGame/UI`: SwiftUI game interface
- `plan.md`: researched multi-cycle roadmap toward a deeper ARMA-like milsim
