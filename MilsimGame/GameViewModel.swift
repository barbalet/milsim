import Foundation
import simd

private enum MapConfig {
    static let columns = 14
    static let rows = 10
}

struct InventoryRow: Identifiable {
    let id: Int
    let label: String
    let isSelected: Bool
}

enum TacticalMaterial {
    case grass
    case road
    case mud
    case rock
    case compound
    case forest
}

struct TacticalMapTile: Identifiable {
    let id: Int
    let position: SIMD2<Float>
    let size: SIMD2<Float>
    let material: TacticalMaterial
    let conceals: Bool
}

enum TacticalMarkerKind {
    case player
    case objective
    case extraction
    case door
    case supply
    case deadDrop
    case radio
    case emplaced
    case enemy
}

struct TacticalMapMarker: Identifiable {
    let id: Int
    let position: SIMD2<Float>
    let kind: TacticalMarkerKind
    let label: String
    let prominent: Bool
}

struct HUDSnapshot {
    var missionName = ""
    var missionBrief = ""
    var objective = ""
    var event = ""
    var weapon = ""
    var ammo = ""
    var posture = ""
    var health = ""
    var stamina = ""
    var mission = ""
    var compass = ""
    var gridReference = ""
    var intelStatus = ""
    var interactionHint = ""
    var worldHalfSize = SIMD2<Float>(1400, 980)
    var mapExpanded = true
    var mapTiles: [TacticalMapTile] = []
    var mapMarkers: [TacticalMapMarker] = []
    var inventory: [InventoryRow] = []
    var victory = false
    var failed = false
}

final class GameViewModel: ObservableObject {
    @Published private(set) var hud = HUDSnapshot()

    fileprivate var state = GameState()
    private var hudAccumulator: Float = 0
    private var mapExpanded = true

    init() {
        game_init(&state)
        refreshHUD(force: true)
    }

    func reset() {
        game_restart(&state)
        hudAccumulator = 0
        refreshHUD(force: true)
    }

    func nextMission() {
        game_next_mission(&state)
        hudAccumulator = 0
        refreshHUD(force: true)
    }

    func toggleMap() {
        mapExpanded.toggle()
        refreshHUD(force: true)
    }

    func currentPlayerPosition() -> SIMD2<Float> {
        SIMD2<Float>(state.player.position.x, state.player.position.y)
    }

    func step(input: InputState, dt: Float) {
        var mutableInput = input
        game_update(&state, &mutableInput, dt)
        hudAccumulator += dt

        if hudAccumulator >= 0.05 || state.victory || state.missionFailed {
            hudAccumulator = 0
            refreshHUD(force: true)
        }
    }

    func withState<Result>(_ body: (UnsafePointer<GameState>) -> Result) -> Result {
        withUnsafePointer(to: &state, body)
    }

    private func string(from cString: UnsafePointer<CChar>?) -> String {
        guard let cString else {
            return ""
        }
        return String(cString: cString)
    }

    private func refreshHUD(force: Bool) {
        _ = force

        withState { statePointer in
            let selectedIndex = Int(game_selected_inventory_index(statePointer))
            let selectedName = string(from: game_selected_item_name(statePointer))
            let objectiveCount = game_mission_objective_count(statePointer)
            let objectiveTarget = game_mission_objective_target(statePointer)
            let extractionReady = game_mission_ready_for_extract(statePointer)
            let lootCount = statePointer.pointee.collectedItemCount
            let missionName = string(from: game_mission_name(statePointer))
            let missionBrief = string(from: game_mission_brief(statePointer))
            let stance = string(from: game_player_stance_name(statePointer))
            let fireMode = string(from: game_selected_fire_mode_name(statePointer))
            let lean = game_player_lean(statePointer)
            let radioIntelUnlocked = game_radio_intel_unlocked(statePointer)
            let player = statePointer.pointee.player
            let playerPosition = SIMD2<Float>(player.position.x, player.position.y)
            let worldHalfSize = SIMD2<Float>(game_world_half_width(), game_world_half_height())

            var ammoLine = "Close assault weapon ready"
            if selectedIndex >= 0, let selectedItem = game_inventory_item_at(statePointer, selectedIndex) {
                if selectedItem.pointee.kind == ItemKind_Gun {
                    let reserve = game_player_total_ammo(statePointer, selectedItem.pointee.ammoType)
                    let suppressorText = selectedItem.pointee.suppressed ? " | suppressed" : ""
                    let opticText = selectedItem.pointee.opticMounted ? " | optic" : ""
                    ammoLine = "\(selectedItem.pointee.roundsInMagazine)/\(selectedItem.pointee.magazineCapacity) in mag | \(reserve) reserve | \(fireMode)\(suppressorText)\(opticText)"
                } else if selectedItem.pointee.weaponClass == WeaponClass_Knife {
                    ammoLine = "Knife readied for close contact"
                }
            }

            let leanText: String
            if lean > 0.25 {
                leanText = " | lean R"
            } else if lean < -0.25 {
                leanText = " | lean L"
            } else {
                leanText = ""
            }

            let inventoryCount = Int(game_inventory_count(statePointer))
            var rows: [InventoryRow] = []
            rows.reserveCapacity(inventoryCount)

            for index in 0..<inventoryCount {
                guard let item = game_inventory_item_at(statePointer, index) else {
                    continue
                }

                let name = string(from: game_inventory_item_name(statePointer, index))
                var label = name

                if item.pointee.kind == ItemKind_Gun {
                    let reserve = game_player_total_ammo(statePointer, item.pointee.ammoType)
                    let itemFireMode = (selectedIndex == index) ? fireMode : fireModeName(for: item.pointee.fireMode)
                    label += "  \(item.pointee.roundsInMagazine)/\(item.pointee.magazineCapacity) | \(reserve) | \(itemFireMode)"
                    if item.pointee.suppressed {
                        label += " | sup"
                    }
                } else if item.pointee.weaponClass == WeaponClass_Knife {
                    label += "  CQB"
                } else if item.pointee.quantity > 0 {
                    label += "  x\(item.pointee.quantity)"
                }

                rows.append(InventoryRow(id: index, label: label, isSelected: selectedIndex == index))
            }

            var objective = "Secure \(objectiveTarget) objective package"
            if objectiveTarget != 1 {
                objective += "s"
            }
            objective += ". \(objectiveCount)/\(objectiveTarget) recovered."

            if extractionReady {
                objective = "Objectives complete. Move to extraction."
            }
            if statePointer.pointee.victory {
                objective = "Operation complete. Team exfiltrated with the package."
            }
            if statePointer.pointee.missionFailed {
                objective = "Operator down. Restart or move to the next operation."
            }

            let missionLine = "Kills \(statePointer.pointee.kills) | Loot \(lootCount) | Time \(Int(statePointer.pointee.missionTime))s"
            let compass = compassString(for: SIMD2<Float>(player.aim.x, player.aim.y))
            let gridReference = gridReference(for: playerPosition, worldHalfSize: worldHalfSize)
            let intelStatus = radioIntelUnlocked
                ? "Radio intel live. Hostile markers are on the tactical map."
                : "Radio intel dark. Hostiles stay off the map until a relay is tapped."
            let interactionHint = interactionHint(for: statePointer, playerPosition: playerPosition)
            let mapTiles = buildMapTiles(from: statePointer)
            let mapMarkers = buildMapMarkers(from: statePointer, playerPosition: playerPosition, radioIntelUnlocked: radioIntelUnlocked)

            hud = HUDSnapshot(
                missionName: missionName,
                missionBrief: missionBrief,
                objective: objective,
                event: string(from: game_last_event(statePointer)),
                weapon: selectedName,
                ammo: ammoLine,
                posture: "\(stance)\(leanText)",
                health: "Health \(Int(game_player_health(statePointer)))",
                stamina: "Stamina \(Int(game_player_stamina(statePointer)))",
                mission: missionLine,
                compass: compass,
                gridReference: gridReference,
                intelStatus: intelStatus,
                interactionHint: interactionHint,
                worldHalfSize: worldHalfSize,
                mapExpanded: mapExpanded,
                mapTiles: mapTiles,
                mapMarkers: mapMarkers,
                inventory: rows,
                victory: statePointer.pointee.victory,
                failed: statePointer.pointee.missionFailed
            )
        }
    }

    private func fireModeName(for mode: FireMode) -> String {
        switch mode {
        case FireMode_Semi:
            return "Semi"
        case FireMode_Burst:
            return "Burst"
        case FireMode_Auto:
            return "Auto"
        default:
            return "Semi"
        }
    }

    private func compassString(for aim: SIMD2<Float>) -> String {
        let normalized = simd_length_squared(aim) > 0.0001 ? simd_normalize(aim) : SIMD2<Float>(0, 1)
        var heading = atan2(Double(normalized.x), Double(normalized.y)) * 180 / .pi
        if heading < 0 {
            heading += 360
        }

        let directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let index = Int(((heading + 22.5) / 45).rounded(.down)) % directions.count
        return "\(directions[index]) \(Int(heading.rounded()))°"
    }

    private func gridReference(for position: SIMD2<Float>, worldHalfSize: SIMD2<Float>) -> String {
        let tileWidth = (worldHalfSize.x * 2) / Float(MapConfig.columns)
        let tileHeight = (worldHalfSize.y * 2) / Float(MapConfig.rows)

        let column = max(0, min(MapConfig.columns - 1, Int(floor((position.x + worldHalfSize.x) / tileWidth))))
        let row = max(0, min(MapConfig.rows - 1, Int(floor((position.y + worldHalfSize.y) / tileHeight))))
        let columnScalar = UnicodeScalar(65 + column)!
        let rowNumber = row + 1
        return "\(Character(columnScalar))\(rowNumber)"
    }

    private func buildMapTiles(from statePointer: UnsafePointer<GameState>) -> [TacticalMapTile] {
        let tileCount = Int(game_terrain_tile_count(statePointer))
        var tiles: [TacticalMapTile] = []
        tiles.reserveCapacity(tileCount)

        for index in 0..<tileCount {
            guard let tile = game_terrain_tile_at(statePointer, index)?.pointee else {
                continue
            }

            tiles.append(
                TacticalMapTile(
                    id: index,
                    position: SIMD2<Float>(tile.position.x, tile.position.y),
                    size: SIMD2<Float>(tile.size.x, tile.size.y),
                    material: mapMaterial(for: tile.material),
                    conceals: tile.conceals
                )
            )
        }

        return tiles
    }

    private func buildMapMarkers(from statePointer: UnsafePointer<GameState>,
                                 playerPosition: SIMD2<Float>,
                                 radioIntelUnlocked: Bool) -> [TacticalMapMarker] {
        var markers: [TacticalMapMarker] = []
        var markerID = 0

        func appendMarker(position: SIMD2<Float>, kind: TacticalMarkerKind, label: String, prominent: Bool) {
            markers.append(TacticalMapMarker(id: markerID, position: position, kind: kind, label: label, prominent: prominent))
            markerID += 1
        }

        appendMarker(position: playerPosition, kind: .player, label: "You", prominent: true)

        let extraction = statePointer.pointee.extractionZone
        appendMarker(
            position: SIMD2<Float>(extraction.x, extraction.y),
            kind: .extraction,
            label: "Extract",
            prominent: true
        )

        let worldItemCount = Int(game_world_item_count(statePointer))
        for index in 0..<worldItemCount {
            guard let item = game_world_item_at(statePointer, index)?.pointee else {
                continue
            }

            if item.kind == ItemKind_Objective {
                appendMarker(
                    position: SIMD2<Float>(item.position.x, item.position.y),
                    kind: .objective,
                    label: string(fromTuple: item.name),
                    prominent: true
                )
            }
        }

        let interactableCount = Int(game_interactable_count(statePointer))
        for index in 0..<interactableCount {
            guard let interactable = game_interactable_at(statePointer, index)?.pointee else {
                continue
            }

            if interactable.singleUse && interactable.toggled && interactable.kind != InteractableKind_Radio {
                continue
            }

            let label = string(fromTuple: interactable.name)
            let position = SIMD2<Float>(interactable.position.x, interactable.position.y)
            switch interactable.kind {
            case InteractableKind_Door:
                appendMarker(position: position, kind: .door, label: label, prominent: false)
            case InteractableKind_SupplyCrate:
                appendMarker(position: position, kind: .supply, label: label, prominent: false)
            case InteractableKind_DeadDrop:
                appendMarker(position: position, kind: .deadDrop, label: label, prominent: radioIntelUnlocked)
            case InteractableKind_Radio:
                appendMarker(position: position, kind: .radio, label: label, prominent: true)
            case InteractableKind_EmplacedWeapon:
                appendMarker(position: position, kind: .emplaced, label: label, prominent: false)
            default:
                break
            }
        }

        if radioIntelUnlocked {
            let enemyCount = Int(game_enemy_count(statePointer))
            for index in 0..<enemyCount {
                guard let enemy = game_enemy_at(statePointer, index)?.pointee else {
                    continue
                }

                appendMarker(
                    position: SIMD2<Float>(enemy.position.x, enemy.position.y),
                    kind: .enemy,
                    label: "Hostile",
                    prominent: false
                )
            }
        }

        return markers
    }

    private func interactionHint(for statePointer: UnsafePointer<GameState>, playerPosition: SIMD2<Float>) -> String {
        var bestDistance = Float.greatestFiniteMagnitude
        var hint = "Recover field gear and use radios, gates, crates, and emplaced guns with F."

        let interactableCount = Int(game_interactable_count(statePointer))
        for index in 0..<interactableCount {
            guard let interactable = game_interactable_at(statePointer, index)?.pointee else {
                continue
            }

            let position = SIMD2<Float>(interactable.position.x, interactable.position.y)
            let distance = simd_length(position - playerPosition)
            if distance > 96 || distance >= bestDistance {
                continue
            }

            bestDistance = distance
            let label = string(fromTuple: interactable.name)
            switch interactable.kind {
            case InteractableKind_Door:
                hint = "Use F to toggle \(label)."
            case InteractableKind_SupplyCrate:
                hint = "Use F to resupply from \(label)."
            case InteractableKind_DeadDrop:
                hint = "Use F to recover \(label)."
            case InteractableKind_Radio:
                hint = "Use F to copy \(label) intel."
            case InteractableKind_EmplacedWeapon:
                hint = "Use F to fire \(label)."
            default:
                break
            }
        }

        let worldItemCount = Int(game_world_item_count(statePointer))
        for index in 0..<worldItemCount {
            guard let item = game_world_item_at(statePointer, index)?.pointee else {
                continue
            }

            let position = SIMD2<Float>(item.position.x, item.position.y)
            let distance = simd_length(position - playerPosition)
            if distance > 86 || distance >= bestDistance {
                continue
            }

            bestDistance = distance
                hint = "Use F to recover \(string(fromTuple: item.name))."
        }

        return hint
    }

    private func mapMaterial(for material: TerrainMaterial) -> TacticalMaterial {
        switch material {
        case TerrainMaterial_Road:
            return .road
        case TerrainMaterial_Mud:
            return .mud
        case TerrainMaterial_Rock:
            return .rock
        case TerrainMaterial_Compound:
            return .compound
        case TerrainMaterial_Forest:
            return .forest
        default:
            return .grass
        }
    }

    private func string<T>(fromTuple tuple: T) -> String {
        withUnsafeBytes(of: tuple) { rawBuffer in
            guard let baseAddress = rawBuffer.bindMemory(to: CChar.self).baseAddress else {
                return ""
            }
            return String(cString: baseAddress)
        }
    }
}
