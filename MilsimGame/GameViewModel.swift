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

struct FireteamMemberRow: Identifiable {
    let id: Int
    let name: String
    let detail: String
    let isDowned: Bool
}

struct MissionScoreRow: Identifiable {
    let id: Int
    let label: String
    let detail: String
}

enum FireteamOrderChoice: Int, CaseIterable, Identifiable {
    case follow
    case hold
    case assault

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .follow:
            return "Follow"
        case .hold:
            return "Hold"
        case .assault:
            return "Assault"
        }
    }

    init(cValue: FireteamOrder) {
        switch cValue {
        case FireteamOrder_Hold:
            self = .hold
        case FireteamOrder_Assault:
            self = .assault
        default:
            self = .follow
        }
    }

    var cValue: FireteamOrder {
        switch self {
        case .follow:
            return FireteamOrder_Follow
        case .hold:
            return FireteamOrder_Hold
        case .assault:
            return FireteamOrder_Assault
        }
    }
}

enum CampaignSlot: String, CaseIterable, Codable, Identifiable {
    case alpha
    case bravo
    case charlie

    var id: String { rawValue }

    var title: String {
        switch self {
        case .alpha:
            return "Alpha"
        case .bravo:
            return "Bravo"
        case .charlie:
            return "Charlie"
        }
    }

    var fileName: String {
        "CampaignSlot\(title).json"
    }
}

struct CampaignSlotSummary: Identifiable {
    let id: CampaignSlot
    let title: String
    let detail: String
    let isActive: Bool
    let hasArchive: Bool
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
    case friendly
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
    var missionPhase = ""
    var missionBranch = ""
    var objective = ""
    var event = ""
    var weapon = ""
    var ammo = ""
    var signature = ""
    var presentation = ""
    var presentationAssist = ""
    var posture = ""
    var fireteamOrder: FireteamOrderChoice = .follow
    var fireteamStatus = ""
    var fireteamMembers: [FireteamMemberRow] = []
    var enemyActivity = ""
    var scoreHeadline = ""
    var scoreSummary = ""
    var scoreRows: [MissionScoreRow] = []
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
    var campaignSlots: [CampaignSlotSummary] = []
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
    let supportsLaser: Bool?
    let supportsLight: Bool?
    let supportsUnderbarrel: Bool?
    let opticMounted: Bool?
    let laserMounted: Bool?
    let lightMounted: Bool?
    let underbarrelMounted: Bool?
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
    let phases: [MissionScriptPhaseRecord]?
    let branches: [MissionScriptBranchRecord]?
}

private struct MissionScriptPhaseRecord: Decodable {
    let id: String
    let title: String
    let brief: String?
    let objective: String?
    let event: String?
    let radio: String?
    let intelStatus: String?
    let routeSummary: String?
    let interactionHint: String?
    let condition: MissionScriptConditionRecord?
}

private struct MissionScriptBranchRecord: Decodable {
    let id: String
    let title: String
    let summary: String
    let campaignResult: String?
    let objective: String?
    let event: String?
    let routeSummary: String?
    let condition: MissionScriptConditionRecord?
}

private struct MissionScriptConditionRecord: Decodable {
    let objectiveCountAtLeast: Int?
    let objectiveCountAtMost: Int?
    let objectiveTargetReached: Bool?
    let radioIntelUnlocked: Bool?
    let extractionReady: Bool?
    let victory: Bool?
    let failed: Bool?
    let killsAtLeast: Int?
    let killsAtMost: Int?
    let lootAtLeast: Int?
    let lootAtMost: Int?
    let intelRecovered: Bool?

    init(objectiveCountAtLeast: Int? = nil,
         objectiveCountAtMost: Int? = nil,
         objectiveTargetReached: Bool? = nil,
         radioIntelUnlocked: Bool? = nil,
         extractionReady: Bool? = nil,
         victory: Bool? = nil,
         failed: Bool? = nil,
         killsAtLeast: Int? = nil,
         killsAtMost: Int? = nil,
         lootAtLeast: Int? = nil,
         lootAtMost: Int? = nil,
         intelRecovered: Bool? = nil) {
        self.objectiveCountAtLeast = objectiveCountAtLeast
        self.objectiveCountAtMost = objectiveCountAtMost
        self.objectiveTargetReached = objectiveTargetReached
        self.radioIntelUnlocked = radioIntelUnlocked
        self.extractionReady = extractionReady
        self.victory = victory
        self.failed = failed
        self.killsAtLeast = killsAtLeast
        self.killsAtMost = killsAtMost
        self.lootAtLeast = lootAtLeast
        self.lootAtMost = lootAtMost
        self.intelRecovered = intelRecovered
    }

    func matches(_ context: MissionScriptEvaluationContext) -> Bool {
        if let objectiveCountAtLeast, context.objectiveCount < objectiveCountAtLeast {
            return false
        }
        if let objectiveCountAtMost, context.objectiveCount > objectiveCountAtMost {
            return false
        }
        if let objectiveTargetReached, context.objectiveTargetReached != objectiveTargetReached {
            return false
        }
        if let radioIntelUnlocked, context.radioIntelUnlocked != radioIntelUnlocked {
            return false
        }
        if let extractionReady, context.extractionReady != extractionReady {
            return false
        }
        if let victory, context.victory != victory {
            return false
        }
        if let failed, context.failed != failed {
            return false
        }
        if let killsAtLeast, context.kills < killsAtLeast {
            return false
        }
        if let killsAtMost, context.kills > killsAtMost {
            return false
        }
        if let lootAtLeast, context.loot < lootAtLeast {
            return false
        }
        if let lootAtMost, context.loot > lootAtMost {
            return false
        }
        if let intelRecovered, context.intelRecovered != intelRecovered {
            return false
        }
        return true
    }
}

private struct MissionScriptEvaluationContext {
    let objectiveCount: Int
    let objectiveTarget: Int
    let extractionReady: Bool
    let radioIntelUnlocked: Bool
    let victory: Bool
    let failed: Bool
    let kills: Int
    let loot: Int
    let intelRecovered: Bool

    var objectiveTargetReached: Bool {
        objectiveTarget > 0 && objectiveCount >= objectiveTarget
    }
}

private struct MissionPresentationSnapshot {
    var missionBrief: String?
    var missionPhase: String?
    var missionBranch: String?
    var objective: String?
    var event: String?
    var radioReport: String?
    var intelStatus: String?
    var routeSummary: String?
    var interactionHint: String?
    var campaignResult: String?
}

private struct MissionScoreSnapshot {
    let total: Int
    let grade: String
    let summary: String
    let stealth: Int
    let tempo: Int
    let casualties: Int
    let materiel: Int
}

private struct EnemyContactSnapshot {
    let engaged: Int
    let search: Int
    let alert: Int
    let fallback: Int
    let focusGrid: String?
}

private struct MissionCampaignStats: Codable {
    var attempts = 0
    var completions = 0
    var bestTimeSeconds: Int?
    var bestKills = 0
    var bestLoot = 0
    var intelRecovered = false
    var bestScore = 0
    var bestGrade = "Ungraded"
}

private struct CampaignProgress: Codable {
    var completedMissions: [String] = []
    var missionStats: [String: MissionCampaignStats] = [:]
    var lastResult = "No operation archived yet."
}

private struct CampaignSaveEnvelope: Codable {
    let version: Int
    let savedAt: Date
    let slot: String?
    let mapExpanded: Bool
    let mission: String
    let campaign: CampaignProgress
    let stateSize: Int
    let stateBlob: Data
}

private enum CampaignStore {
    static let version = 7

    static var supportDirectoryURL: URL {
        let fileManager = FileManager.default
        let supportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return supportURL.appendingPathComponent("MilsimGame", isDirectory: true)
    }

    static var legacySaveURL: URL {
        supportDirectoryURL.appendingPathComponent("CampaignSave.json", isDirectory: false)
    }

    static func saveURL(for slot: CampaignSlot) -> URL {
        supportDirectoryURL.appendingPathComponent(slot.fileName, isDirectory: false)
    }

    static func load(slot: CampaignSlot, allowLegacyFallback: Bool = false) throws -> CampaignSaveEnvelope {
        var candidateURLs = [saveURL(for: slot)]
        if allowLegacyFallback && slot == .alpha {
            candidateURLs.append(legacySaveURL)
        }

        var lastMissingFileError: CocoaError?
        for candidateURL in candidateURLs {
            do {
                return try loadEnvelope(at: candidateURL)
            } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
                lastMissingFileError = error
            }
        }

        throw lastMissingFileError ?? CocoaError(.fileReadNoSuchFile)
    }

    static func preview(slot: CampaignSlot) -> CampaignSaveEnvelope? {
        try? load(slot: slot, allowLegacyFallback: true)
    }

    static func loadEnvelope(at url: URL) throws -> CampaignSaveEnvelope {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(CampaignSaveEnvelope.self, from: data)
    }

    static func save(_ envelope: CampaignSaveEnvelope, slot: CampaignSlot) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(envelope)
        let directoryURL = supportDirectoryURL
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try data.write(to: saveURL(for: slot), options: .atomic)
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
    nonisolated(unsafe) private(set) static var missionScriptsByKey: [String: MissionScriptRecord] = [:]

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
            if let scriptDocument {
                missionScriptsByKey = Dictionary(uniqueKeysWithValues: scriptDocument.missions.map { ($0.mission, $0) })
            } else {
                missionScriptsByKey = [:]
            }
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
                        item.supportsLaser ?? false,
                        item.supportsLight ?? false,
                        item.supportsUnderbarrel ?? false,
                        item.opticMounted ?? false,
                        item.laserMounted ?? false,
                        item.lightMounted ?? false,
                        item.underbarrelMounted ?? false
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

    static func missionScript(for missionType: MissionType) -> MissionScriptRecord? {
        missionScriptsByKey[missionKey(for: missionType)]
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
    private var firstPersonPresentation = true
    private var campaignProgress = CampaignProgress()
    private var activeCampaignSlot: CampaignSlot = .alpha
    private var campaignSlotArchives: [CampaignSlot: CampaignSaveEnvelope] = [:]
    private var saveStatus = "No campaign save stored."
    private var lastSavedAt: Date?
    private var missionResolutionRecorded = false

    init() {
        _ = GameContentBootstrap.loadIntoEngine
        game_init(&state)
        reloadCampaignSlotArchives()
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
        saveCampaign(to: activeCampaignSlot)
    }

    func saveCampaign(to slot: CampaignSlot) {
        recordMissionResolutionIfNeeded()

        do {
            let savedAt = Date()
            let envelope = CampaignSaveEnvelope(
                version: CampaignStore.version,
                savedAt: savedAt,
                slot: slot.rawValue,
                mapExpanded: mapExpanded,
                mission: GameContentBootstrap.missionKey(for: state.missionType),
                campaign: campaignProgress,
                stateSize: MemoryLayout<GameState>.size,
                stateBlob: encodedStateBlob()
            )
            try CampaignStore.save(envelope, slot: slot)
            activeCampaignSlot = slot
            lastSavedAt = savedAt
            saveStatus = "\(slot.title) archived."
            campaignSlotArchives[slot] = envelope
        } catch {
            saveStatus = "Save failed: \(error.localizedDescription)"
        }

        refreshHUD(force: true)
    }

    @discardableResult
    func loadCampaign() -> Bool {
        loadCampaign(from: activeCampaignSlot)
    }

    @discardableResult
    func loadCampaign(from slot: CampaignSlot) -> Bool {
        loadCampaign(slot: slot, startup: false, allowLegacyFallback: slot == .alpha)
    }

    func setCampaignSlot(_ slot: CampaignSlot) {
        activeCampaignSlot = slot
        if let archive = campaignSlotArchives[slot] {
            lastSavedAt = archive.savedAt
            saveStatus = "\(slot.title) selected. \(displayName(forMissionKey: archive.mission)) archived."
        } else {
            lastSavedAt = nil
            saveStatus = "\(slot.title) selected. No archive stored yet."
        }
        refreshHUD(force: true)
    }

    func toggleMap() {
        mapExpanded.toggle()
        refreshHUD(force: true)
    }

    func togglePresentation() {
        firstPersonPresentation.toggle()
        refreshHUD(force: true)
    }

    func cycleFireteamOrder() {
        game_cycle_fireteam_order(&state)
        refreshHUD(force: true)
    }

    func setFireteamOrder(_ order: FireteamOrderChoice) {
        game_set_fireteam_order(&state, order.cValue)
        refreshHUD(force: true)
    }

    func isFirstPersonPresentation() -> Bool {
        firstPersonPresentation
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
        loadCampaign(slot: activeCampaignSlot, startup: startup, allowLegacyFallback: activeCampaignSlot == .alpha)
    }

    private func loadCampaign(slot: CampaignSlot,
                              startup: Bool,
                              allowLegacyFallback: Bool) -> Bool {
        do {
            let envelope = try CampaignStore.load(slot: slot, allowLegacyFallback: allowLegacyFallback)

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

            activeCampaignSlot = slot
            campaignProgress = envelope.campaign
            mapExpanded = envelope.mapExpanded
            lastSavedAt = envelope.savedAt
            missionResolutionRecorded = state.victory || state.missionFailed
            hudAccumulator = 0
            campaignSlotArchives[slot] = envelope
            saveStatus = startup
                ? "\(slot.title) resumed."
                : "\(slot.title) loaded."
            reloadCampaignSlotArchives()
            refreshHUD(force: true)
            return true
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            if !startup {
                activeCampaignSlot = slot
            }
            lastSavedAt = campaignSlotArchives[slot]?.savedAt
            saveStatus = startup
                ? "No campaign archive detected."
                : "No archive found in \(slot.title)."
        } catch {
            saveStatus = startup
                ? "Campaign resume failed: \(error.localizedDescription)"
                : "Load failed: \(error.localizedDescription)"
        }

        reloadCampaignSlotArchives()
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
        let score = withUnsafePointer(to: &state) { missionScore(for: $0) }
        stats.attempts += 1
        stats.intelRecovered = stats.intelRecovered || state.radioIntelUnlocked
        let presentation = withUnsafePointer(to: &state) { missionPresentation(for: $0) }

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
            if score.total >= stats.bestScore {
                stats.bestScore = score.total
                stats.bestGrade = score.grade
            }
            campaignProgress.lastResult = "\(score.grade) \(score.total) | " + (
                presentation?.campaignResult
                    ?? "\(displayName(for: state.missionType)) cleared in \(missionTime)s."
            )
        } else {
            if score.total >= stats.bestScore {
                stats.bestScore = score.total
                stats.bestGrade = score.grade
            }
            campaignProgress.lastResult = "\(score.grade) \(score.total) | " + (
                presentation?.campaignResult
                    ?? "\(displayName(for: state.missionType)) ended with an operator loss."
            )
        }

        campaignProgress.missionStats[missionKey] = stats
        missionResolutionRecorded = true
    }

    private func reloadCampaignSlotArchives() {
        var refreshedArchives: [CampaignSlot: CampaignSaveEnvelope] = [:]
        for slot in CampaignSlot.allCases {
            if let archive = CampaignStore.preview(slot: slot) {
                refreshedArchives[slot] = archive
            }
        }
        campaignSlotArchives = refreshedArchives
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

    private func displayName(forMissionKey missionKey: String) -> String {
        GameContentBootstrap.missionType(for: missionKey).map(displayName(for:)) ?? "Operation"
    }

    private func missionTempoTargets(for missionType: MissionType) -> (ideal: Int, steady: Int, late: Int) {
        switch missionType {
        case MissionType_CacheRaid:
            return (ideal: 210, steady: 330, late: 520)
        case MissionType_HostageRecovery:
            return (ideal: 240, steady: 380, late: 560)
        case MissionType_ReconExfil:
            return (ideal: 280, steady: 430, late: 620)
        case MissionType_ConvoyAmbush:
            return (ideal: 220, steady: 350, late: 540)
        default:
            return (ideal: 240, steady: 360, late: 540)
        }
    }

    private func missionGrade(for totalScore: Int) -> String {
        switch totalScore {
        case 92...:
            return "S"
        case 84...:
            return "A"
        case 74...:
            return "B"
        case 64...:
            return "C"
        case 50...:
            return "D"
        default:
            return "E"
        }
    }

    private func descriptor(forStealth score: Int) -> String {
        switch score {
        case 21...:
            return "Low signature"
        case 15...:
            return "Managed contact"
        case 9...:
            return "Compromised"
        default:
            return "Loud assault"
        }
    }

    private func descriptor(forTempo score: Int) -> String {
        switch score {
        case 21...:
            return "Ahead of tempo"
        case 15...:
            return "On pace"
        case 9...:
            return "Delayed"
        default:
            return "Stalled route"
        }
    }

    private func descriptor(forCasualties score: Int) -> String {
        switch score {
        case 21...:
            return "Unit intact"
        case 15...:
            return "Manageable attrition"
        case 9...:
            return "Heavy hits taken"
        default:
            return "Combat ineffective"
        }
    }

    private func descriptor(forMateriel score: Int) -> String {
        switch score {
        case 21...:
            return "Strong recovery"
        case 15...:
            return "Useful haul"
        case 9...:
            return "Partial recovery"
        default:
            return "Thin pull"
        }
    }

    private func missionScoreRows(from score: MissionScoreSnapshot) -> [MissionScoreRow] {
        [
            MissionScoreRow(id: 0, label: "Stealth \(score.stealth)/25", detail: descriptor(forStealth: score.stealth)),
            MissionScoreRow(id: 1, label: "Tempo \(score.tempo)/25", detail: descriptor(forTempo: score.tempo)),
            MissionScoreRow(id: 2, label: "Casualties \(score.casualties)/25", detail: descriptor(forCasualties: score.casualties)),
            MissionScoreRow(id: 3, label: "Materiel \(score.materiel)/25", detail: descriptor(forMateriel: score.materiel))
        ]
    }

    private func missionScoreSummary(for score: MissionScoreSnapshot, victory: Bool) -> String {
        if victory {
            if score.total >= 84 {
                return "Objective secured with strong command discipline and a clean enough exfil."
            }
            if score.total >= 70 {
                return "Package came out, but the route bled time or exposure before extraction."
            }
            return "Mission succeeded, though the squad paid in tempo, noise, or casualties."
        }

        if score.materiel >= 14 {
            return "Some mission value came back, but the operation broke before a clean finish."
        }
        return "The operation collapsed before the team could turn the contact into a controlled exfil."
    }

    private func missionScore(for statePointer: UnsafePointer<GameState>) -> MissionScoreSnapshot {
        let objectiveCount = Int(game_mission_objective_count(statePointer))
        let objectiveTarget = max(1, Int(game_mission_objective_target(statePointer)))
        let lootCount = Int(statePointer.pointee.collectedItemCount)
        let playerShots = Int(statePointer.pointee.playerShotsFired)
        let friendlyShots = Int(statePointer.pointee.friendlyShotsFired)
        let loudReports = Int(statePointer.pointee.loudReportsTriggered)
        let alertEvents = Int(statePointer.pointee.enemyAlertEvents)
        let searchEvents = Int(statePointer.pointee.enemySearchEvents)
        let engagementEvents = Int(statePointer.pointee.enemyEngagementEvents)
        let kills = Int(statePointer.pointee.kills)
        let missionTime = Int(statePointer.pointee.missionTime.rounded())
        let tempoTargets = missionTempoTargets(for: statePointer.pointee.missionType)

        var teammateDownCount = 0
        var teammateWoundedCount = 0
        let teammateCount = Int(game_teammate_count(statePointer))
        for index in 0..<teammateCount {
            guard let teammate = game_teammate_at(statePointer, index)?.pointee else {
                continue
            }
            if teammate.downed {
                teammateDownCount += 1
            } else if teammate.health < 60 || teammate.bleedingRate > 0.2 {
                teammateWoundedCount += 1
            }
        }

        let reportPenalty = min(12, Int((Foundation.sqrt(Double(max(loudReports, 0))) * 4.0).rounded(.down)))
        let playerShotPenalty = min(6, Int((Foundation.sqrt(Double(max(playerShots, 0))) * 1.9).rounded(.down)))
        let contactPressure = max(0, alertEvents + searchEvents * 2 + engagementEvents * 3)
        let alertPenalty = min(8, Int((Foundation.sqrt(Double(contactPressure)) * 1.7).rounded(.down)))
        let killPenalty = min(5, max(0, kills - objectiveCount))
        var stealth = max(0, 25 - reportPenalty - playerShotPenalty - alertPenalty - killPenalty)
        if statePointer.pointee.victory && loudReports == 0 && engagementEvents == 0 {
            stealth = min(25, stealth + 2)
        }
        if friendlyShots <= 6 {
            stealth = min(25, stealth + 1)
        }
        if searchEvents == 0 && engagementEvents == 0 {
            stealth = min(25, stealth + 1)
        }

        let tempo: Int
        if missionTime <= tempoTargets.ideal {
            tempo = 25
        } else if missionTime <= tempoTargets.steady {
            let progress = Double(missionTime - tempoTargets.ideal) / Double(max(1, tempoTargets.steady - tempoTargets.ideal))
            tempo = max(0, 25 - Int((progress * 8.0).rounded()))
        } else if missionTime <= tempoTargets.late {
            let progress = Double(missionTime - tempoTargets.steady) / Double(max(1, tempoTargets.late - tempoTargets.steady))
            tempo = max(0, 17 - Int((progress * 10.0).rounded()))
        } else {
            let overrun = Double(missionTime - tempoTargets.late) / Double(max(tempoTargets.late, 1))
            tempo = max(0, 7 - Int((overrun * 12.0).rounded()))
        }

        let casualties: Int
        if statePointer.pointee.missionFailed {
            casualties = 0
        } else {
            let playerPenalty = Int(((100 - max(0, Int(statePointer.pointee.player.health.rounded()))) / 10))
            let casualtyPenalty = teammateDownCount * 7 + teammateWoundedCount * 2 + playerPenalty
            casualties = max(0, 25 - casualtyPenalty)
        }

        let objectiveRatio = Double(objectiveCount) / Double(objectiveTarget)
        var materiel = Int((objectiveRatio * 12.0).rounded())
        materiel += min(6, lootCount)
        materiel += statePointer.pointee.radioIntelUnlocked ? 3 : 0
        materiel += statePointer.pointee.victory ? 4 : (game_mission_ready_for_extract(statePointer) ? 2 : 0)
        materiel = min(25, max(0, materiel))

        let total = max(0, min(100, stealth + tempo + casualties + materiel))
        let grade = missionGrade(for: total)
        return MissionScoreSnapshot(
            total: total,
            grade: grade,
            summary: missionScoreSummary(
                for: MissionScoreSnapshot(
                    total: total,
                    grade: grade,
                    summary: "",
                    stealth: stealth,
                    tempo: tempo,
                    casualties: casualties,
                    materiel: materiel
                ),
                victory: statePointer.pointee.victory
            ),
            stealth: stealth,
            tempo: tempo,
            casualties: casualties,
            materiel: materiel
        )
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
        return "Slot \(activeCampaignSlot.title) | Campaign \(completedCount)/\(totalMissions) ops cleared | Intel nets copied \(intelCount) | \(campaignProgress.lastResult)"
    }

    private func topScoreSummary(for campaign: CampaignProgress) -> String {
        let rankedStats = campaign.missionStats.values.filter { $0.bestScore > 0 }
        guard let bestStat = rankedStats.max(by: { $0.bestScore < $1.bestScore }) else {
            return "Top score pending"
        }
        return "Top \(bestStat.bestGrade) \(bestStat.bestScore)"
    }

    private func saveStatusLine() -> String {
        if let lastSavedAt {
            return "\(saveStatus) | Active slot \(activeCampaignSlot.title) | Last archive \(timestampString(from: lastSavedAt))"
        }
        return "\(saveStatus) | Active slot \(activeCampaignSlot.title)"
    }

    private func campaignSlotSummaries() -> [CampaignSlotSummary] {
        CampaignSlot.allCases.map { slot in
            if let archive = campaignSlotArchives[slot] {
                let completedCount = archive.campaign.completedMissions.count
                let missionName = displayName(forMissionKey: archive.mission)
                let savedAt = timestampString(from: archive.savedAt)
                let detail = "\(completedCount)/4 ops | \(missionName) | \(topScoreSummary(for: archive.campaign)) | \(savedAt)"
                return CampaignSlotSummary(
                    id: slot,
                    title: slot.title,
                    detail: detail,
                    isActive: slot == activeCampaignSlot,
                    hasArchive: true
                )
            }

            return CampaignSlotSummary(
                id: slot,
                title: slot.title,
                detail: slot == activeCampaignSlot ? "Active slot | no archive yet" : "Empty slot",
                isActive: slot == activeCampaignSlot,
                hasArchive: false
            )
        }
    }

    private func missionContext(for statePointer: UnsafePointer<GameState>) -> MissionScriptEvaluationContext {
        let objectiveCount = Int(game_mission_objective_count(statePointer))
        let objectiveTarget = Int(game_mission_objective_target(statePointer))
        let extractionReady = game_mission_ready_for_extract(statePointer)
        let radioIntelUnlocked = game_radio_intel_unlocked(statePointer)
        let kills = Int(statePointer.pointee.kills)
        let loot = Int(statePointer.pointee.collectedItemCount)
        return MissionScriptEvaluationContext(
            objectiveCount: objectiveCount,
            objectiveTarget: objectiveTarget,
            extractionReady: extractionReady,
            radioIntelUnlocked: radioIntelUnlocked,
            victory: statePointer.pointee.victory,
            failed: statePointer.pointee.missionFailed,
            kills: kills,
            loot: loot,
            intelRecovered: radioIntelUnlocked
        )
    }

    private func missionPresentation(for statePointer: UnsafePointer<GameState>) -> MissionPresentationSnapshot? {
        guard let script = GameContentBootstrap.missionScript(for: statePointer.pointee.missionType) else {
            return nil
        }

        let context = missionContext(for: statePointer)
        let phase = script.phases?.last(where: { ($0.condition ?? MissionScriptConditionRecord()).matches(context) })
        let branch = script.branches?.first(where: { ($0.condition ?? MissionScriptConditionRecord()).matches(context) })

        return MissionPresentationSnapshot(
            missionBrief: phase?.brief ?? script.brief,
            missionPhase: phase.map { "Phase \($0.title)" },
            missionBranch: branch.map { "Branch \($0.title) | \($0.summary)" },
            objective: branch?.objective ?? phase?.objective,
            event: branch?.event ?? phase?.event,
            radioReport: phase?.radio,
            intelStatus: phase?.intelStatus,
            routeSummary: branch?.routeSummary ?? phase?.routeSummary,
            interactionHint: phase?.interactionHint,
            campaignResult: branch?.campaignResult ?? branch?.summary
        )
    }

    private func presentationStatusLine() -> String {
        if firstPersonPresentation {
            return "View FPV active | P tactical overhead"
        }
        return "View tactical overhead | P first-person"
    }

    private func normalizedAimVector(_ aim: SIMD2<Float>) -> SIMD2<Float> {
        if simd_length_squared(aim) > 0.0001 {
            return simd_normalize(aim)
        }
        return SIMD2<Float>(0, 1)
    }

    private func firstPersonFocusHint(for statePointer: UnsafePointer<GameState>,
                                      playerPosition: SIMD2<Float>,
                                      aim: SIMD2<Float>) -> String? {
        let forward = normalizedAimVector(aim)
        let right = SIMD2<Float>(forward.y, -forward.x)
        var bestScore = Float.greatestFiniteMagnitude
        var bestHint: String?

        let interactableCount = Int(game_interactable_count(statePointer))
        for index in 0..<interactableCount {
            guard let interactable = game_interactable_at(statePointer, index)?.pointee, interactable.active else {
                continue
            }

            let position = SIMD2<Float>(interactable.position.x, interactable.position.y)
            let offset = position - playerPosition
            let distance = simd_length(offset)
            guard distance <= 150, distance > 0.001 else {
                continue
            }

            let forwardDepth = simd_dot(offset, forward)
            let lateral = abs(simd_dot(offset, right))
            guard forwardDepth > 0.001 else {
                continue
            }

            let corridor = lateral / max(forwardDepth, 1)
            let facing = simd_dot(simd_normalize(offset), forward)
            if facing < 0.1 || corridor > 0.92 {
                continue
            }

            let score = forwardDepth + lateral * 1.45 + max(0, corridor - 0.18) * 96
            if score >= bestScore {
                continue
            }

            let label = string(fromTuple: interactable.name)
            let range = Int(distance.rounded())
            switch interactable.kind {
            case InteractableKind_Door:
                bestHint = "Focus F: toggle \(label) \(range)m"
            case InteractableKind_SupplyCrate:
                bestHint = "Focus F: resupply \(range)m"
            case InteractableKind_DeadDrop:
                bestHint = "Focus F: recover \(label) \(range)m"
            case InteractableKind_Radio:
                bestHint = "Focus F: copy intel \(range)m"
            case InteractableKind_EmplacedWeapon:
                bestHint = "Focus F: fire \(label) \(range)m"
            default:
                break
            }
            bestScore = score
        }

        let worldItemCount = Int(game_world_item_count(statePointer))
        for index in 0..<worldItemCount {
            guard let item = game_world_item_at(statePointer, index)?.pointee, item.active else {
                continue
            }

            let position = SIMD2<Float>(item.position.x, item.position.y)
            let offset = position - playerPosition
            let distance = simd_length(offset)
            guard distance <= 130, distance > 0.001 else {
                continue
            }

            let forwardDepth = simd_dot(offset, forward)
            let lateral = abs(simd_dot(offset, right))
            guard forwardDepth > 0.001 else {
                continue
            }

            let corridor = lateral / max(forwardDepth, 1)
            let facing = simd_dot(simd_normalize(offset), forward)
            if facing < 0.08 || corridor > 0.88 {
                continue
            }

            let score = forwardDepth + lateral * 1.28 + max(0, corridor - 0.18) * 88
            if score >= bestScore {
                continue
            }

            bestScore = score
            bestHint = "Focus F: recover \(string(fromTuple: item.name)) \(Int(distance.rounded()))m"
        }

        return bestHint
    }

    private func presentationAssistLine(for statePointer: UnsafePointer<GameState>,
                                        playerPosition: SIMD2<Float>,
                                        aim: SIMD2<Float>,
                                        selectedIndex: Int) -> String {
        guard firstPersonPresentation else {
            return "Overwatch view keeps the route and intel board in frame."
        }

        var cues: [String] = []

        if selectedIndex >= 0, let selectedItem = game_inventory_item_at(statePointer, selectedIndex) {
            let item = selectedItem.pointee
            if item.kind == ItemKind_Gun {
                cues.append(item.opticMounted ? "optic aligned" : "front sight aligned")
                if item.laserMounted {
                    cues.append("laser active")
                }
                if item.lightMounted {
                    cues.append("light wash")
                }
                if item.underbarrelMounted {
                    cues.append("grip settled")
                }
            } else if item.weaponClass == WeaponClass_Knife {
                cues.append("blade centered")
            } else if item.kind == ItemKind_Medkit {
                cues.append("medical kit in hand")
            } else {
                cues.append("support gear readied")
            }
        } else {
            cues.append("hands free")
        }

        if let focusHint = firstPersonFocusHint(for: statePointer, playerPosition: playerPosition, aim: aim) {
            cues.append(focusHint)
        } else {
            cues.append("scan doors, crates, and field gear with F")
        }

        return cues.joined(separator: " | ")
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

    private func attachmentSummary(for item: InventoryItem) -> String {
        var attachments: [String] = []

        if item.opticMounted {
            attachments.append("optic")
        }
        if item.suppressed {
            attachments.append("sup")
        }
        if item.laserMounted {
            attachments.append("laser")
        }
        if item.lightMounted {
            attachments.append("light")
        }
        if item.underbarrelMounted {
            attachments.append("grip")
        }

        return attachments.isEmpty ? "bare" : attachments.joined(separator: ", ")
    }

    private func reportDescriptor(for item: InventoryItem) -> String {
        var signature: Float

        switch item.weaponClass {
        case WeaponClass_Pistol:
            signature = 0.95
        case WeaponClass_Carbine:
            signature = 1.45
        case WeaponClass_Rifle:
            signature = 1.72
        default:
            signature = 0.8
        }

        signature += min(max((item.muzzleVelocity - 640) / 520, 0), 0.58)
        if item.fireMode == FireMode_Auto {
            signature += 0.18
        } else if item.fireMode == FireMode_Burst {
            signature += 0.1
        }
        if item.suppressed {
            signature *= 0.48
        }

        switch signature {
        case ..<0.55:
            return "hushed"
        case ..<0.95:
            return "managed"
        case ..<1.45:
            return "sharp"
        default:
            return "thunder"
        }
    }

    private func penetrationDescriptor(for item: InventoryItem) -> String {
        var power = item.muzzleVelocity * 0.92 + item.damage * 5.5

        if item.weaponClass == WeaponClass_Pistol {
            power *= 0.72
        }
        if item.suppressed {
            power *= 0.96
        }

        switch power {
        case ..<520:
            return "light cover"
        case ..<780:
            return "doors"
        case ..<980:
            return "low walls"
        default:
            return "vehicle skin"
        }
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
            let missionPresentation = missionPresentation(for: statePointer)
            let missionBrief = missionPresentation?.missionBrief ?? string(from: game_mission_brief(statePointer))
            let stance = string(from: game_player_stance_name(statePointer))
            let fireMode = string(from: game_selected_fire_mode_name(statePointer))
            let lean = game_player_lean(statePointer)
            let radioIntelUnlocked = game_radio_intel_unlocked(statePointer)
            let player = statePointer.pointee.player
            let playerPosition = SIMD2<Float>(player.position.x, player.position.y)
            let aimVector = SIMD2<Float>(player.aim.x, player.aim.y)
            let worldHalfSize = SIMD2<Float>(game_world_half_width(), game_world_half_height())

            var ammoLine = "Close assault weapon ready"
            var signatureLine = "Report idle | Pen none | bare"
            if selectedIndex >= 0, let selectedItem = game_inventory_item_at(statePointer, selectedIndex) {
                if selectedItem.pointee.kind == ItemKind_Gun {
                    let reserve = game_player_total_ammo(statePointer, selectedItem.pointee.ammoType)
                    let chamberText = selectedItem.pointee.roundChambered ? 1 : 0
                    let attachments = attachmentSummary(for: selectedItem.pointee)
                    ammoLine = "\(selectedItem.pointee.roundsInMagazine)+\(chamberText) loaded | \(reserve) reserve | \(fireMode) | \(attachments)"
                    signatureLine = "Report \(reportDescriptor(for: selectedItem.pointee)) | Pen \(penetrationDescriptor(for: selectedItem.pointee))"
                } else if selectedItem.pointee.weaponClass == WeaponClass_Knife {
                    ammoLine = "Knife readied for close contact"
                    signatureLine = "Report silent | Pen none | blade"
                } else if selectedItem.pointee.kind == ItemKind_Medkit {
                    let selectedItemName = string(from: game_inventory_item_name(statePointer, selectedIndex))
                    if selectedItemName.lowercased().contains("splint") {
                        ammoLine = "\(selectedItemName) x\(selectedItem.pointee.quantity) | Press H to stabilize fractures"
                    } else {
                        ammoLine = "\(selectedItemName) x\(selectedItem.pointee.quantity) | Press H to treat"
                    }
                    signatureLine = "Medical gear readied"
                } else if selectedItem.pointee.quantity > 0 {
                    ammoLine = "\(selectedItem.pointee.quantity)x support item stowed"
                    signatureLine = "Support item readied"
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
                    label += " | \(attachmentSummary(for: item.pointee))"
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
            let defaultIntelStatus = radioIntelUnlocked
                ? "Radio intel live. Hostiles and route updates are on the tactical map."
                : "Radio intel dark. Discover sectors locally or tap a relay for hostile traffic."
            let intelStatus = missionPresentation?.intelStatus ?? defaultIntelStatus
            let radioReport = missionPresentation?.radioReport ?? string(from: game_radio_report(statePointer))
            let baseInteractionHint = interactionHint(for: statePointer, playerPosition: playerPosition)
            let mapTiles = buildMapTiles(from: statePointer)
            let mapMarkers = buildMapMarkers(from: statePointer, playerPosition: playerPosition, radioIntelUnlocked: radioIntelUnlocked)
            let routeSegments = buildRouteSegments(from: statePointer)
            let enemyContact = enemyContactSnapshot(from: statePointer, worldHalfSize: worldHalfSize)
            let enemyActivity = enemyActivitySummary(for: enemyContact, radioIntelUnlocked: radioIntelUnlocked)
            let routeSummary = missionPresentation?.routeSummary ?? routeSummary(from: statePointer, worldHalfSize: worldHalfSize)
            let campaignStatus = campaignStatusLine()
            let saveStatus = saveStatusLine()
            let campaignSlots = campaignSlotSummaries()
            let presentationLine = presentationStatusLine()
            let presentationAssist = presentationAssistLine(
                for: statePointer,
                playerPosition: playerPosition,
                aim: aimVector,
                selectedIndex: selectedIndex
            )
            let fireteamOrder = FireteamOrderChoice(cValue: game_fireteam_order(statePointer))
            let teammateCount = Int(game_teammate_count(statePointer))
            var fireteamMembers: [FireteamMemberRow] = []
            fireteamMembers.reserveCapacity(teammateCount)
            var fireteamUpCount = 0
            var fireteamEngagedCount = 0

            for index in 0..<teammateCount {
                guard let teammate = game_teammate_at(statePointer, index)?.pointee else {
                    continue
                }

                let name = string(fromTuple: teammate.callsign)
                let status: String
                if teammate.downed {
                    status = "Down"
                } else if teammate.health < 42 || teammate.bleedingRate > 0.2 {
                    status = "Wounded"
                } else if teammate.suppression > 34 {
                    status = "Pinned"
                } else if teammate.fireCooldown > 0.45 {
                    status = "Engaging"
                } else if simd_length(SIMD2<Float>(teammate.velocity.x, teammate.velocity.y)) > 18 {
                    status = fireteamOrder == .assault ? "Pushing" : "Moving"
                } else {
                    status = "Ready"
                }

                if !teammate.downed {
                    fireteamUpCount += 1
                }
                if status == "Engaging" || status == "Pushing" {
                    fireteamEngagedCount += 1
                }

                fireteamMembers.append(
                    FireteamMemberRow(
                        id: index,
                        name: name,
                        detail: teammate.downed
                            ? "Down | Await relief"
                            : "\(status) | \(Int(teammate.health.rounded())) hp | Supp \(Int(teammate.suppression.rounded()))%",
                        isDowned: teammate.downed
                    )
                )
            }

            let fireteamStatus = "Order \(fireteamOrder.title) | \(fireteamUpCount)/\(teammateCount) up | \(fireteamEngagedCount) engaging"
            let missionScore = missionScore(for: statePointer)
            let scoreHeadline = "\(missionScore.grade) | \(missionScore.total)/100"
            let scoreSummary = missionScore.summary
            let scoreRows = missionScoreRows(from: missionScore)
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
            let scriptHintSuffix = missionPresentation?.interactionHint.map { " \($0)" } ?? ""
            let interactionHint = baseInteractionHint + treatmentHint + scriptHintSuffix

            hud = HUDSnapshot(
                missionName: missionName,
                missionBrief: missionBrief,
                missionPhase: missionPresentation?.missionPhase ?? "Phase Live operation",
                missionBranch: missionPresentation?.missionBranch ?? "Branch pending | Mission outcome will archive once the operation resolves.",
                objective: missionPresentation?.objective ?? objective,
                event: missionPresentation?.event ?? string(from: game_last_event(statePointer)),
                weapon: selectedName,
                ammo: ammoLine,
                signature: signatureLine,
                presentation: presentationLine,
                presentationAssist: presentationAssist,
                posture: "\(stance)\(leanText)",
                fireteamOrder: fireteamOrder,
                fireteamStatus: fireteamStatus,
                fireteamMembers: fireteamMembers,
                enemyActivity: enemyActivity,
                scoreHeadline: scoreHeadline,
                scoreSummary: scoreSummary,
                scoreRows: scoreRows,
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
                campaignSlots: campaignSlots,
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

        let teammateCount = Int(game_teammate_count(statePointer))
        for index in 0..<teammateCount {
            guard let teammate = game_teammate_at(statePointer, index)?.pointee else {
                continue
            }

            appendMarker(
                position: SIMD2<Float>(teammate.position.x, teammate.position.y),
                kind: .friendly,
                label: string(fromTuple: teammate.callsign),
                prominent: !teammate.downed
            )
        }

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

                let presentation = enemyMarkerPresentation(for: enemy)

                appendMarker(
                    position: SIMD2<Float>(enemy.position.x, enemy.position.y),
                    kind: .enemy,
                    label: presentation.label,
                    prominent: presentation.prominent
                )
            }
        }

        return markers
    }

    private func enemyMarkerPresentation(for enemy: Enemy) -> (label: String, prominent: Bool) {
        switch enemy.awarenessState {
        case EnemyAwarenessState_Engaged:
            return ("Contact", true)
        case EnemyAwarenessState_Search:
            return ("Search", true)
        case EnemyAwarenessState_Fallback:
            return ("Fallback", true)
        case EnemyAwarenessState_Alert:
            return ("Alert", false)
        case EnemyAwarenessState_Patrol:
            return ("Hostile", false)
        default:
            return ("Hostile", false)
        }
    }

    private func enemyContactSnapshot(from statePointer: UnsafePointer<GameState>,
                                      worldHalfSize: SIMD2<Float>) -> EnemyContactSnapshot {
        let enemyCount = Int(game_enemy_count(statePointer))
        var engaged = 0
        var search = 0
        var alert = 0
        var fallback = 0
        var focusPosition: SIMD2<Float>?
        var focusPriority = -1

        for index in 0..<enemyCount {
            guard let enemy = game_enemy_at(statePointer, index)?.pointee else {
                continue
            }

            let position = SIMD2<Float>(enemy.position.x, enemy.position.y)
            switch enemy.awarenessState {
            case EnemyAwarenessState_Engaged:
                engaged += 1
                if focusPriority < 3 {
                    focusPriority = 3
                    focusPosition = position
                }
            case EnemyAwarenessState_Search:
                search += 1
                if focusPriority < 2 {
                    focusPriority = 2
                    focusPosition = position
                }
            case EnemyAwarenessState_Fallback:
                fallback += 1
                if focusPriority < 2 {
                    focusPriority = 2
                    focusPosition = position
                }
            case EnemyAwarenessState_Alert:
                alert += 1
                if focusPriority < 1 {
                    focusPriority = 1
                    focusPosition = position
                }
            case EnemyAwarenessState_Patrol:
                if focusPriority < 0 {
                    focusPriority = 0
                    focusPosition = position
                }
            default:
                break
            }
        }

        return EnemyContactSnapshot(
            engaged: engaged,
            search: search,
            alert: alert,
            fallback: fallback,
            focusGrid: focusPosition.map { gridReference(for: $0, worldHalfSize: worldHalfSize) }
        )
    }

    private func enemyActivitySummary(for snapshot: EnemyContactSnapshot, radioIntelUnlocked: Bool) -> String {
        if !radioIntelUnlocked {
            return "Enemy net unavailable. Recover a relay to track hostile alert and search movement."
        }

        let focusSuffix = snapshot.focusGrid.map { " | Focus \($0)" } ?? ""
        if snapshot.engaged > 0 {
            var parts = ["\(snapshot.engaged) engaging"]
            if snapshot.search > 0 {
                parts.append("\(snapshot.search) searching")
            }
            if snapshot.fallback > 0 {
                parts.append("\(snapshot.fallback) falling back")
            }
            return "Enemy net: " + parts.joined(separator: " | ") + focusSuffix
        }
        if snapshot.search > 0 {
            var parts = ["\(snapshot.search) searching"]
            if snapshot.alert > 0 {
                parts.append("\(snapshot.alert) alerted")
            }
            if snapshot.fallback > 0 {
                parts.append("\(snapshot.fallback) breaking")
            }
            return "Enemy net: " + parts.joined(separator: " | ") + focusSuffix
        }
        if snapshot.alert > 0 {
            return "Enemy net: \(snapshot.alert) alerted" + focusSuffix
        }
        if snapshot.fallback > 0 {
            return "Enemy net: \(snapshot.fallback) breaking contact" + focusSuffix
        }
        return "Enemy net: patrol traffic only."
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
        let snapshot = enemyContactSnapshot(from: statePointer, worldHalfSize: worldHalfSize)
        if game_radio_intel_unlocked(statePointer), let focusGrid = snapshot.focusGrid {
            if snapshot.engaged > 0 {
                return objectiveReady
                    ? "Extraction route contested near \(focusGrid)"
                    : "Command route crosses active contact at \(focusGrid)"
            }
            if snapshot.search > 0 {
                return objectiveReady
                    ? "Extraction route brushes a search line at \(focusGrid)"
                    : "Command route skirts a search sector near \(focusGrid)"
            }
        }
        return objectiveReady ? "Command route to extraction at \(destinationGrid)" : "Command route to search sector \(destinationGrid)"
    }

    private func interactionHint(for statePointer: UnsafePointer<GameState>, playerPosition: SIMD2<Float>) -> String {
        var bestDistance = Float.greatestFiniteMagnitude
        var hint = "Recover field gear with F and tap T to cycle fireteam orders."

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
                hint = "Use F to toggle \(label). T cycles fireteam orders."
            case InteractableKind_SupplyCrate:
                hint = "Use F to resupply from \(label). T cycles fireteam orders."
            case InteractableKind_DeadDrop:
                hint = "Use F to recover \(label). T cycles fireteam orders."
            case InteractableKind_Radio:
                hint = "Use F to copy \(label) intel. T cycles fireteam orders."
            case InteractableKind_EmplacedWeapon:
                hint = "Use F to fire \(label). T cycles fireteam orders."
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
            hint = "Use F to recover \(string(fromTuple: item.name)). T cycles fireteam orders."
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
