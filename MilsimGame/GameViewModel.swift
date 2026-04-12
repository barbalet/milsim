import Foundation
import simd

struct InventoryRow: Identifiable {
    let id: Int
    let label: String
    let isSelected: Bool
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
    var inventory: [InventoryRow] = []
    var victory = false
    var failed = false
}

final class GameViewModel: ObservableObject {
    @Published private(set) var hud = HUDSnapshot()

    fileprivate var state = GameState()
    private var hudAccumulator: Float = 0

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
}
