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

struct TacticalRouteSegment: Identifiable {
    let id: Int
    let start: SIMD2<Float>
    let end: SIMD2<Float>
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
    var wounds = ""
    var medical = ""
    var mission = ""
    var compass = ""
    var gridReference = ""
    var intelStatus = ""
    var radioReport = ""
    var routeSummary = ""
    var interactionHint = ""
    var campaignStatus = ""
    var saveStatus = ""
    var worldHalfSize = SIMD2<Float>(1400, 980)
    var mapExpanded = true
    var mapTiles: [TacticalMapTile] = []
    var mapMarkers: [TacticalMapMarker] = []
    var routeSegments: [TacticalRouteSegment] = []
    var inventory: [InventoryRow] = []
    var victory = false
    var failed = false
}

private struct ItemDefinitionsDocument: Decodable {
    let items: [ItemDefinitionRecord]
}

private struct ItemDefinitionRecord: Decodable {
    let id: String
    let name: String
    let kind: String
    let ammoType: String?
    let weaponClass: String?
    let quantity: Int?
    let magazineCapacity: Int?
    let roundsInMagazine: Int?
    let damage: Float?
    let range: Float?
    let suppressed: Bool?
    let recoil: Float?
    let muzzleVelocity: Float?
    let fireMode: String?
    let supportedFireModes: [String]?
    let supportsSuppressor: Bool?
    let supportsOptic: Bool?
    let opticMounted: Bool?
}

private struct MissionLootTablesDocument: Decodable {
    let loadouts: [MissionLoadoutRecord]
    let lootTables: [MissionLootTableRecord]
}

private struct MissionLoadoutRecord: Decodable {
    let mission: String
    let items: [MissionLoadoutItemRecord]
}

private struct MissionLoadoutItemRecord: Decodable {
    let template: String
    let slot: String
}

private struct MissionLootTableRecord: Decodable {
    let mission: String
    let spawns: [MissionLootSpawnRecord]
}

private struct MissionLootSpawnRecord: Decodable {
    let template: String
    let x: Float
    let y: Float
}

private struct MissionScriptsDocument: Decodable {
    let missions: [MissionScriptRecord]
}

private struct MissionScriptRecord: Decodable {
    let mission: String
    let name: String?
    let brief: String?
    let initialEvent: String?
    let quietReport: String?
    let clearReport: String?
    let interceptCallsign: String?
}

private struct MissionCampaignStats: Codable {
    var attempts = 0
    var completions = 0
    var bestTimeSeconds: Int?
    var bestKills = 0
    var bestLoot = 0
    var intelRecovered = false
}

private struct CampaignProgress: Codable {
    var completedMissions: [String] = []
    var missionStats: [String: MissionCampaignStats] = [:]
    var lastResult = "No operation archived yet."
}

private struct CampaignSaveEnvelope: Codable {
    let version: Int
    let savedAt: Date
    let mapExpanded: Bool
    let mission: String
    let campaign: CampaignProgress
    let stateSize: Int
    let stateBlob: Data
}

private enum CampaignStore {
    static let version = 3

    static var saveURL: URL {
        let fileManager = FileManager.default
        let supportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return supportURL
            .appendingPathComponent("MilsimGame", isDirectory: true)
            .appendingPathComponent("CampaignSave.json", isDirectory: false)
    }

    static func load() throws -> CampaignSaveEnvelope {
        let data = try Data(contentsOf: saveURL)
        return try JSONDecoder().decode(CampaignSaveEnvelope.self, from: data)
    }

    static func save(_ envelope: CampaignSaveEnvelope) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(envelope)
        let directoryURL = saveURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try data.write(to: saveURL, options: .atomic)
    }
}

private enum WoundMask {
    static let arm: UInt32 = 1 << 0
    static let leg: UInt32 = 1 << 1
    static let torso: UInt32 = 1 << 2
    static let head: UInt32 = 1 << 3
}

private enum FractureMask {
    static let arm: UInt32 = 1 << 0
    static let leg: UInt32 = 1 << 1
}

private enum CampaignSaveError: LocalizedError {
    case invalidVersion(Int)
    case invalidStateSize(expected: Int, actual: Int)
    case invalidMission(String)

    var errorDescription: String? {
        switch self {
        case .invalidVersion(let version):
            return "Unsupported campaign save version \(version)."
        case .invalidStateSize(let expected, let actual):
            return "Save data size mismatch (\(actual) bytes, expected \(expected))."
        case .invalidMission(let mission):
            return "Save file references an unknown mission '\(mission)'."
        }
    }
}

private enum GameContentBootstrap {
    static let loadIntoEngine: Void = {
        loadBundleContent()
    }()

    static func loadBundleContent() {
        let scriptURL = Bundle.main.url(forResource: "MissionScripts", withExtension: "json")
        guard
            let itemURL = Bundle.main.url(forResource: "ItemDefinitions", withExtension: "json"),
            let lootURL = Bundle.main.url(forResource: "MissionLootTables", withExtension: "json")
        else {
            return
        }

        let decoder = JSONDecoder()

        do {
            let itemDocument = try decoder.decode(ItemDefinitionsDocument.self, from: Data(contentsOf: itemURL))
            let missionDocument = try decoder.decode(MissionLootTablesDocument.self, from: Data(contentsOf: lootURL))
            let scriptDocument = try scriptURL.map { try decoder.decode(MissionScriptsDocument.self, from: Data(contentsOf: $0)) }
            game_content_reset()

            for item in itemDocument.items {
                guard let kind = itemKind(for: item.kind) else {
                    continue
                }

                let ammoType = ammoType(for: item.ammoType)
                let weaponClass = weaponClass(for: item.weaponClass)
                let fireMode = fireMode(for: item.fireMode)
                let supportedFireModes = fireModeMask(item.supportedFireModes, fallback: fireMode)

                withCStringPair(item.id, item.name) { identifierPointer, namePointer in
                    _ = game_content_add_item_template(
                        identifierPointer,
                        namePointer,
                        kind,
                        ammoType,
                        weaponClass,
                        Int32(item.quantity ?? defaultQuantity(for: kind)),
                        Int32(item.magazineCapacity ?? 0),
                        Int32(item.roundsInMagazine ?? 0),
                        item.damage ?? 0,
                        item.range ?? 0,
                        item.suppressed ?? false,
                        item.recoil ?? 0,
                        item.muzzleVelocity ?? 0,
                        fireMode,
                        supportedFireModes,
                        item.supportsSuppressor ?? false,
                        item.supportsOptic ?? false,
                        item.opticMounted ?? false
                    )
                }
            }

            for loadout in missionDocument.loadouts {
                guard let missionType = missionType(for: loadout.mission) else {
                    continue
                }

                for item in loadout.items {
                    item.template.withCString { templatePointer in
                        _ = game_content_add_mission_loadout_entry(
                            missionType,
                            templatePointer,
                            loadoutSlotHint(for: item.slot)
                        )
                    }
                }
            }

            for lootTable in missionDocument.lootTables {
                guard let missionType = missionType(for: lootTable.mission) else {
                    continue
                }

                for spawn in lootTable.spawns {
                    spawn.template.withCString { templatePointer in
                        _ = game_content_add_mission_loot_entry(
                            missionType,
                            templatePointer,
                            spawn.x,
                            spawn.y
                        )
                    }
                }
            }

            if let scriptDocument {
                for script in scriptDocument.missions {
                    guard let missionType = missionType(for: script.mission) else {
                        continue
                    }

                    withOptionalCString7(script.name,
                                         script.brief,
                                         script.initialEvent,
                                         script.quietReport,
                                         script.clearReport,
                                         script.interceptCallsign) { namePointer,
                        briefPointer,
                        initialEventPointer,
                        quietReportPointer,
                        clearReportPointer,
                        interceptCallsignPointer in
                            _ = game_content_set_mission_script(
                                missionType,
                                namePointer,
                                briefPointer,
                                initialEventPointer,
                                quietReportPointer,
                                clearReportPointer,
                                interceptCallsignPointer
                            )
                    }
                }
            }
        } catch {
            print("Failed to load bundled mission content: \(error.localizedDescription)")
        }
    }

    static func withCStringPair<Result>(_ first: String,
                                        _ second: String,
                                        body: (UnsafePointer<CChar>, UnsafePointer<CChar>) -> Result) -> Result {
        first.withCString { firstPointer in
            second.withCString { secondPointer in
                body(firstPointer, secondPointer)
            }
        }
    }

    static func withOptionalCString7<Result>(_ first: String?,
                                             _ second: String?,
                                             _ third: String?,
                                             _ fourth: String?,
                                             _ fifth: String?,
                                             _ sixth: String?,
                                             body: (UnsafePointer<CChar>?,
                                                    UnsafePointer<CChar>?,
                                                    UnsafePointer<CChar>?,
                                                    UnsafePointer<CChar>?,
                                                    UnsafePointer<CChar>?,
                                                    UnsafePointer<CChar>?) -> Result) -> Result {
        withOptionalCString(first) { firstPointer in
            withOptionalCString(second) { secondPointer in
                withOptionalCString(third) { thirdPointer in
                    withOptionalCString(fourth) { fourthPointer in
                        withOptionalCString(fifth) { fifthPointer in
                            withOptionalCString(sixth) { sixthPointer in
                                body(firstPointer,
                                     secondPointer,
                                     thirdPointer,
                                     fourthPointer,
                                     fifthPointer,
                                     sixthPointer)
                            }
                        }
                    }
                }
            }
        }
    }

    static func withOptionalCString<Result>(_ string: String?,
                                            body: (UnsafePointer<CChar>?) -> Result) -> Result {
        guard let string else {
            return body(nil)
        }

        return string.withCString { body($0) }
    }

    static func missionType(for rawValue: String) -> MissionType? {
        switch rawValue.lowercased() {
        case "cache_raid":
            return MissionType_CacheRaid
        case "hostage_recovery":
            return MissionType_HostageRecovery
        case "recon_exfil":
            return MissionType_ReconExfil
        case "convoy_ambush":
            return MissionType_ConvoyAmbush
        default:
            return nil
        }
    }

    static func missionKey(for missionType: MissionType) -> String {
        switch missionType {
        case MissionType_CacheRaid:
            return "cache_raid"
        case MissionType_HostageRecovery:
            return "hostage_recovery"
        case MissionType_ReconExfil:
            return "recon_exfil"
        case MissionType_ConvoyAmbush:
            return "convoy_ambush"
        default:
            return "cache_raid"
        }
    }

    static func itemKind(for rawValue: String) -> ItemKind? {
        switch rawValue.lowercased() {
        case "bullet_box":
            return ItemKind_BulletBox
        case "gun":
            return ItemKind_Gun
        case "magazine":
            return ItemKind_Magazine
        case "blade":
            return ItemKind_Blade
        case "attachment":
            return ItemKind_Attachment
        case "medkit":
            return ItemKind_Medkit
        case "objective":
            return ItemKind_Objective
        default:
            return nil
        }
    }

    static func ammoType(for rawValue: String?) -> AmmoType {
        switch rawValue?.lowercased() {
        case "556":
            return AmmoType_556
        case "9mm":
            return AmmoType_9mm
        case "shell":
            return AmmoType_Shell
        default:
            return AmmoType_None
        }
    }

    static func weaponClass(for rawValue: String?) -> WeaponClass {
        switch rawValue?.lowercased() {
        case "rifle":
            return WeaponClass_Rifle
        case "carbine":
            return WeaponClass_Carbine
        case "pistol":
            return WeaponClass_Pistol
        case "knife":
            return WeaponClass_Knife
        default:
            return WeaponClass_None
        }
    }

    static func fireMode(for rawValue: String?) -> FireMode {
        switch rawValue?.lowercased() {
        case "burst":
            return FireMode_Burst
        case "auto":
            return FireMode_Auto
        default:
            return FireMode_Semi
        }
    }

    static func loadoutSlotHint(for rawValue: String) -> LoadoutSlotHint {
        switch rawValue.lowercased() {
        case "primary":
            return LoadoutSlotHint_Primary
        case "secondary":
            return LoadoutSlotHint_Secondary
        case "melee":
            return LoadoutSlotHint_Melee
        case "gear":
            return LoadoutSlotHint_Gear
        default:
            return LoadoutSlotHint_Auto
        }
    }

    static func fireModeMask(_ rawModes: [String]?, fallback: FireMode) -> UInt32 {
        guard let rawModes, !rawModes.isEmpty else {
            return 1 << UInt32(fallback.rawValue)
        }

        return rawModes.reduce(0) { partialResult, rawValue in
            let mode = fireMode(for: rawValue)
            return partialResult | (1 << UInt32(mode.rawValue))
        }
    }

    static func defaultQuantity(for kind: ItemKind) -> Int {
        switch kind {
        case ItemKind_BulletBox, ItemKind_Magazine:
            return 1
        default:
            return 1
        }
    }
}

final class GameViewModel: ObservableObject {
    @Published private(set) var hud = HUDSnapshot()

    fileprivate var state = GameState()
    private var hudAccumulator: Float = 0
    private var mapExpanded = true
    private var campaignProgress = CampaignProgress()
    private var saveStatus = "No campaign save stored."
    private var lastSavedAt: Date?
    private var missionResolutionRecorded = false

    init() {
        _ = GameContentBootstrap.loadIntoEngine
        game_init(&state)
        if !loadCampaign(startup: true) {
            refreshHUD(force: true)
        }
    }

    func reset() {
        game_restart(&state)
        hudAccumulator = 0
        missionResolutionRecorded = false
        refreshHUD(force: true)
    }

    func nextMission() {
        recordMissionResolutionIfNeeded()
        game_next_mission(&state)
        hudAccumulator = 0
        missionResolutionRecorded = false
        refreshHUD(force: true)
    }

    func saveCampaign() {
        recordMissionResolutionIfNeeded()

        do {
            let savedAt = Date()
            let envelope = CampaignSaveEnvelope(
                version: CampaignStore.version,
                savedAt: savedAt,
                mapExpanded: mapExpanded,
                mission: GameContentBootstrap.missionKey(for: state.missionType),
                campaign: campaignProgress,
                stateSize: MemoryLayout<GameState>.size,
                stateBlob: encodedStateBlob()
            )
            try CampaignStore.save(envelope)
            lastSavedAt = savedAt
            saveStatus = "Campaign saved."
        } catch {
            saveStatus = "Save failed: \(error.localizedDescription)"
        }

        refreshHUD(force: true)
    }

    @discardableResult
    func loadCampaign() -> Bool {
        loadCampaign(startup: false)
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
        recordMissionResolutionIfNeeded()
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

    private func loadCampaign(startup: Bool) -> Bool {
        do {
            let envelope = try CampaignStore.load()

            guard envelope.version == CampaignStore.version else {
                throw CampaignSaveError.invalidVersion(envelope.version)
            }

            let expectedStateSize = MemoryLayout<GameState>.size
            guard envelope.stateSize == expectedStateSize, envelope.stateBlob.count == expectedStateSize else {
                throw CampaignSaveError.invalidStateSize(expected: expectedStateSize, actual: envelope.stateBlob.count)
            }

            guard let missionType = GameContentBootstrap.missionType(for: envelope.mission) else {
                throw CampaignSaveError.invalidMission(envelope.mission)
            }

            restoreState(from: envelope.stateBlob)
            if state.missionType != missionType {
                state.missionType = missionType
            }

            game_set_mission_cursor(state.missionType)
            game_refresh_loaded_state(&state)

            campaignProgress = envelope.campaign
            mapExpanded = envelope.mapExpanded
            lastSavedAt = envelope.savedAt
            missionResolutionRecorded = state.victory || state.missionFailed
            hudAccumulator = 0
            saveStatus = startup
                ? "Campaign resumed."
                : "Campaign loaded."
            refreshHUD(force: true)
            return true
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            saveStatus = startup ? "No campaign save detected." : "No saved campaign found."
        } catch {
            saveStatus = startup
                ? "Campaign resume failed: \(error.localizedDescription)"
                : "Load failed: \(error.localizedDescription)"
        }

        return false
    }

    private func encodedStateBlob() -> Data {
        var stateCopy = state
        return withUnsafeBytes(of: &stateCopy) { Data($0) }
    }

    private func restoreState(from data: Data) {
        withUnsafeMutableBytes(of: &state) { destination in
            data.withUnsafeBytes { source in
                destination.copyBytes(from: source)
            }
        }
    }

    private func recordMissionResolutionIfNeeded() {
        guard !missionResolutionRecorded, state.victory || state.missionFailed else {
            return
        }

        let missionKey = GameContentBootstrap.missionKey(for: state.missionType)
        var stats = campaignProgress.missionStats[missionKey] ?? MissionCampaignStats()
        stats.attempts += 1
        stats.intelRecovered = stats.intelRecovered || state.radioIntelUnlocked

        if state.victory {
            stats.completions += 1
            stats.bestKills = max(stats.bestKills, Int(state.kills))
            stats.bestLoot = max(stats.bestLoot, Int(state.collectedItemCount))
            let missionTime = Int(state.missionTime.rounded())
            if let bestTimeSeconds = stats.bestTimeSeconds {
                stats.bestTimeSeconds = min(bestTimeSeconds, missionTime)
            } else {
                stats.bestTimeSeconds = missionTime
            }

            if !campaignProgress.completedMissions.contains(missionKey) {
                campaignProgress.completedMissions.append(missionKey)
                campaignProgress.completedMissions.sort()
            }
            campaignProgress.lastResult = "\(displayName(for: state.missionType)) cleared in \(missionTime)s."
        } else {
            campaignProgress.lastResult = "\(displayName(for: state.missionType)) ended with an operator loss."
        }

        campaignProgress.missionStats[missionKey] = stats
        missionResolutionRecorded = true
    }

    private func displayName(for missionType: MissionType) -> String {
        switch missionType {
        case MissionType_CacheRaid:
            return "Cache Raid"
        case MissionType_HostageRecovery:
            return "Hostage Recovery"
        case MissionType_ReconExfil:
            return "Recon & Exfil"
        case MissionType_ConvoyAmbush:
            return "Convoy Ambush"
        default:
            return "Operation"
        }
    }

    private func timestampString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func campaignStatusLine() -> String {
        let completedCount = campaignProgress.completedMissions.count
        let totalMissions = 4
        let intelCount = campaignProgress.missionStats.values.filter(\.intelRecovered).count
        return "Campaign \(completedCount)/\(totalMissions) ops cleared | Intel nets copied \(intelCount) | \(campaignProgress.lastResult)"
    }

    private func saveStatusLine() -> String {
        if let lastSavedAt {
            return "\(saveStatus) | Last archive \(timestampString(from: lastSavedAt))"
        }
        return saveStatus
    }

    private func woundSummary(for flags: UInt32) -> String {
        var wounds: [String] = []

        if (flags & WoundMask.head) != 0 {
            wounds.append("head")
        }
        if (flags & WoundMask.torso) != 0 {
            wounds.append("torso")
        }
        if (flags & WoundMask.leg) != 0 {
            wounds.append("leg")
        }
        if (flags & WoundMask.arm) != 0 {
            wounds.append("arm")
        }

        return wounds.isEmpty ? "stable" : wounds.joined(separator: ", ")
    }

    private func fractureSummary(for flags: UInt32) -> String {
        var fractures: [String] = []

        if (flags & FractureMask.leg) != 0 {
            fractures.append("leg")
        }
        if (flags & FractureMask.arm) != 0 {
            fractures.append("arm")
        }

        return fractures.isEmpty ? "none" : fractures.joined(separator: ", ")
    }

    private func formatRate(_ value: Float) -> String {
        String(format: "%.1f", value)
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
                    let chamberText = selectedItem.pointee.roundChambered ? 1 : 0
                    ammoLine = "\(selectedItem.pointee.roundsInMagazine)+\(chamberText) loaded | \(reserve) reserve | \(fireMode)\(suppressorText)\(opticText)"
                } else if selectedItem.pointee.weaponClass == WeaponClass_Knife {
                    ammoLine = "Knife readied for close contact"
                } else if selectedItem.pointee.kind == ItemKind_Medkit {
                    let selectedItemName = string(from: game_inventory_item_name(statePointer, selectedIndex))
                    if selectedItemName.lowercased().contains("splint") {
                        ammoLine = "\(selectedItemName) x\(selectedItem.pointee.quantity) | Press H to stabilize fractures"
                    } else {
                        ammoLine = "\(selectedItemName) x\(selectedItem.pointee.quantity) | Press H to treat"
                    }
                } else if selectedItem.pointee.quantity > 0 {
                    ammoLine = "\(selectedItem.pointee.quantity)x support item stowed"
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
            var gauzeCount = 0
            var splintCount = 0

            for index in 0..<inventoryCount {
                guard let item = game_inventory_item_at(statePointer, index) else {
                    continue
                }

                let name = string(from: game_inventory_item_name(statePointer, index))
                var label = name

                if item.pointee.kind == ItemKind_Gun {
                    let reserve = game_player_total_ammo(statePointer, item.pointee.ammoType)
                    let itemFireMode = (selectedIndex == index) ? fireMode : fireModeName(for: item.pointee.fireMode)
                    let chamberText = item.pointee.roundChambered ? 1 : 0
                    label += "  \(item.pointee.roundsInMagazine)+\(chamberText) | \(reserve) | \(itemFireMode)"
                    if item.pointee.suppressed {
                        label += " | sup"
                    }
                } else if item.pointee.weaponClass == WeaponClass_Knife {
                    label += "  CQB"
                } else if item.pointee.quantity > 0 {
                    label += "  x\(item.pointee.quantity)"
                }

                if item.pointee.kind == ItemKind_Medkit {
                    if name.lowercased().contains("splint") {
                        splintCount += Int(item.pointee.quantity)
                    } else {
                        gauzeCount += Int(item.pointee.quantity)
                    }
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
                ? "Radio intel live. Hostiles and route updates are on the tactical map."
                : "Radio intel dark. Discover sectors locally or tap a relay for hostile traffic."
            let radioReport = string(from: game_radio_report(statePointer))
            let baseInteractionHint = interactionHint(for: statePointer, playerPosition: playerPosition)
            let mapTiles = buildMapTiles(from: statePointer)
            let mapMarkers = buildMapMarkers(from: statePointer, playerPosition: playerPosition, radioIntelUnlocked: radioIntelUnlocked)
            let routeSegments = buildRouteSegments(from: statePointer)
            let routeSummary = routeSummary(from: statePointer, worldHalfSize: worldHalfSize)
            let campaignStatus = campaignStatusLine()
            let saveStatus = saveStatusLine()
            let healthLine = "Health \(Int(game_player_health(statePointer))) | Pain \(Int(player.pain.rounded())) | Shock \(Int(player.staminaShock.rounded()))"
            let staminaLine = "Stamina \(Int(game_player_stamina(statePointer))) | Supp \(Int(player.suppression.rounded()))%"
            let woundLine = "Wounds \(woundSummary(for: UInt32(player.woundFlags))) | Fractures \(fractureSummary(for: UInt32(player.fractureFlags)))"
            let medicalLine = "Bleed \(formatRate(player.bleedingRate))/s | Gauze x\(gauzeCount) | Splint x\(splintCount) | H to treat"
            let needsTreatment = player.bleedingRate > 0.1 ||
                player.pain > 18 ||
                player.woundFlags != 0 ||
                player.fractureFlags != 0 ||
                player.staminaShock > 12
            let treatmentHint = needsTreatment
                ? ((gauzeCount + splintCount) > 0 ? " Press H to treat wounds." : " Recover gauze or a splint to stabilize.")
                : ""
            let interactionHint = baseInteractionHint + treatmentHint

            hud = HUDSnapshot(
                missionName: missionName,
                missionBrief: missionBrief,
                objective: objective,
                event: string(from: game_last_event(statePointer)),
                weapon: selectedName,
                ammo: ammoLine,
                posture: "\(stance)\(leanText)",
                health: healthLine,
                stamina: staminaLine,
                wounds: woundLine,
                medical: medicalLine,
                mission: missionLine,
                compass: compass,
                gridReference: gridReference,
                intelStatus: intelStatus,
                radioReport: radioReport,
                routeSummary: routeSummary,
                interactionHint: interactionHint,
                campaignStatus: campaignStatus,
                saveStatus: saveStatus,
                worldHalfSize: worldHalfSize,
                mapExpanded: mapExpanded,
                mapTiles: mapTiles,
                mapMarkers: mapMarkers,
                routeSegments: routeSegments,
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
                guard item.discovered else {
                    continue
                }

                appendMarker(
                    position: SIMD2<Float>(item.position.x, item.position.y),
                    kind: .objective,
                    label: string(fromTuple: item.name),
                    prominent: true
                )
            } else if item.discovered {
                appendMarker(
                    position: SIMD2<Float>(item.position.x, item.position.y),
                    kind: .supply,
                    label: string(fromTuple: item.name),
                    prominent: false
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
            if !interactable.discovered {
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

    private func buildRouteSegments(from statePointer: UnsafePointer<GameState>) -> [TacticalRouteSegment] {
        let routePointCount = Int(game_command_route_count(statePointer))
        guard routePointCount >= 2 else {
            return []
        }

        var points: [SIMD2<Float>] = []
        points.reserveCapacity(routePointCount)

        for index in 0..<routePointCount {
            guard let point = game_command_route_point_at(statePointer, index)?.pointee else {
                continue
            }
            points.append(SIMD2<Float>(point.x, point.y))
        }

        guard points.count >= 2 else {
            return []
        }

        var segments: [TacticalRouteSegment] = []
        segments.reserveCapacity(points.count - 1)

        for index in 1..<points.count {
            segments.append(
                TacticalRouteSegment(
                    id: index - 1,
                    start: points[index - 1],
                    end: points[index]
                )
            )
        }

        return segments
    }

    private func routeSummary(from statePointer: UnsafePointer<GameState>, worldHalfSize: SIMD2<Float>) -> String {
        let routePointCount = Int(game_command_route_count(statePointer))
        guard routePointCount > 0,
              let routePoint = game_command_route_point_at(statePointer, max(0, routePointCount - 1))?.pointee else {
            return "Command route unavailable"
        }

        let destinationGrid = gridReference(
            for: SIMD2<Float>(routePoint.x, routePoint.y),
            worldHalfSize: worldHalfSize
        )
        let objectiveReady = game_mission_ready_for_extract(statePointer)
        return objectiveReady ? "Command route to extraction at \(destinationGrid)" : "Command route to search sector \(destinationGrid)"
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
