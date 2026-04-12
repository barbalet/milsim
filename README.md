# MilsimGame

`MilsimGame` is a macOS tactical sandbox prototype built for Xcode with:

- SwiftUI for the app shell and HUD
- Metal for rendering
- C for the gameplay and simulation core

The current build is a playable Cycle 1 infantry sandbox slice: run four mission seeds, move through compounds and road networks, use stance and lean to manage exposure, switch fire modes, vault low cover, collect military gear, recover objective packages, and extract.

## Controls

- `W`, `A`, `S`, `D`: move
- `Shift`: sprint
- Mouse: aim
- Left mouse or `Space`: fire / attack
- `F` or right mouse: collect nearby equipment
- `R`: reload current firearm
- `B`: toggle fire mode
- `C`: crouch toggle
- `Z`: prone toggle
- `Q` / `E`: lean left / right
- `V`: vault low cover
- `Tab` or mouse wheel: cycle equipment
- `1`: primary weapon
- `2`: sidearm
- `3`: blade weapon
- `Control` + `Command` + `F`: toggle full screen

## Current Cycle 1 Features

- Four mission seeds: cache raid, hostage recovery, recon-and-exfil, convoy ambush
- Layered battlefield structures rendered in Metal: ridges, roads, compounds, low walls, towers, convoy hulks, and concealment foliage
- C simulation support for stance, lean, vaulting, fire modes, muzzle velocity, recoil, suppressor mounting, and objective extraction
- SwiftUI HUD support for mission briefs, posture, fire mode, inventory state, and operation cycling

## Project Layout

- `MilsimGame.xcodeproj`: Xcode project
- `MilsimGame/Engine`: C simulation core
- `MilsimGame/Rendering`: Metal view, renderer, and shaders
- `MilsimGame/UI`: SwiftUI game interface
- `plan.md`: researched multi-cycle roadmap toward a deeper ARMA-like milsim
