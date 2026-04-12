# MilsimGame

`MilsimGame` is a macOS tactical sandbox prototype built for Xcode with:

- SwiftUI for the app shell and HUD
- Metal for rendering
- C for the gameplay and simulation core

The current build is a playable vertical slice: move through a training raid, collect military gear, fight patrols, manage magazines and ammunition, and extract once enough field items have been secured.

## Controls

- `W`, `A`, `S`, `D`: move
- `Shift`: sprint
- Mouse: aim
- Left mouse or `Space`: fire / attack
- `E`: collect nearby equipment
- `R`: reload current firearm
- `Q` / `Tab`: cycle equipment
- `1`: primary weapon
- `2`: sidearm
- `3`: blade weapon
- `Control` + `Command` + `F`: toggle full screen

## Project Layout

- `MilsimGame.xcodeproj`: Xcode project
- `MilsimGame/Engine`: C simulation core
- `MilsimGame/Rendering`: Metal view, renderer, and shaders
- `MilsimGame/UI`: SwiftUI game interface
- `plan.md`: researched multi-cycle roadmap toward a deeper ARMA-like milsim

