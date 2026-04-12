import Foundation
import simd

struct InventoryRow: Identifiable {
    let id: Int
    let label: String
    let isSelected: Bool
}

struct HUDSnapshot {
    var objective = ""
    var event = ""
    var weapon = ""
    var ammo = ""
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
        game_init(&state)
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
            let target = Int(game_collection_target())
            let collected = statePointer.pointee.collectedItemCount

            var ammoLine = "Close assault weapon ready"
            if selectedIndex >= 0, let selectedItem = game_inventory_item_at(statePointer, selectedIndex) {
                if selectedItem.pointee.kind == ItemKind_Gun {
                    let reserve = game_player_total_ammo(statePointer, selectedItem.pointee.ammoType)
                    let suppressorText = selectedItem.pointee.suppressed ? " | suppressed" : ""
                    ammoLine = "\(selectedItem.pointee.roundsInMagazine)/\(selectedItem.pointee.magazineCapacity) in mag | \(reserve) reserve\(suppressorText)"
                } else if selectedItem.pointee.weaponClass == WeaponClass_Knife {
                    ammoLine = "Knife readied for close contact"
                }
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
                    label += "  \(item.pointee.roundsInMagazine)/\(item.pointee.magazineCapacity) | \(reserve)"
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

            var objective = "Recover \(target) field items. \(collected)/\(target) secured."
            if collected >= target {
                objective = "Enough equipment recovered. Move to the yellow extraction ring."
            }
            if statePointer.pointee.victory {
                objective = "Extraction complete. Loadout and intel secured."
            }
            if statePointer.pointee.missionFailed {
                objective = "Operator down. Restart the exercise."
            }

            let missionLine = "Kills \(statePointer.pointee.kills) | Loot \(collected)/\(target) | Time \(Int(statePointer.pointee.missionTime))s"

            hud = HUDSnapshot(
                objective: objective,
                event: string(from: game_last_event(statePointer)),
                weapon: selectedName,
                ammo: ammoLine,
                health: "Health \(Int(game_player_health(statePointer)))",
                stamina: "Stamina \(Int(game_player_stamina(statePointer)))",
                mission: missionLine,
                inventory: rows,
                victory: statePointer.pointee.victory,
                failed: statePointer.pointee.missionFailed
            )
        }
    }
}

