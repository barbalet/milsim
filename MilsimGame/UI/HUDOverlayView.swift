import AppKit
import SwiftUI

enum AppWindowID {
    static let game = "milsim.window.game"
}

enum HUDPanelWindowID: String, CaseIterable {
    case mission = "milsim.window.hud.mission"
    case operatorStatus = "milsim.window.hud.operator"
    case tacticalMap = "milsim.window.hud.map"
    case controls = "milsim.window.hud.controls"
    case loadout = "milsim.window.hud.loadout"

    var title: String {
        switch self {
        case .mission:
            return "Mission"
        case .operatorStatus:
            return "Operator"
        case .tacticalMap:
            return "Tactical Map"
        case .controls:
            return "Controls"
        case .loadout:
            return "Loadout"
        }
    }
}

@MainActor
enum WindowCoordinator {
    static func showAllPanels(using openWindow: OpenWindowAction) {
        HUDPanelWindowID.allCases.forEach { panelID in
            openWindow(id: panelID.rawValue)
        }

        DispatchQueue.main.async {
            focusGameWindow()
        }
    }

    static func toggleGameFullScreen() {
        gameWindow()?.toggleFullScreen(nil)
    }

    static func showGameWindow(using openWindow: OpenWindowAction) {
        openWindow(id: AppWindowID.game)

        DispatchQueue.main.async {
            focusGameWindow()
        }
    }

    static func focusGameWindow() {
        guard let window = gameWindow() else {
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    static func gameWindow() -> NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue == AppWindowID.game }
            ?? NSApp.windows.first { $0.title == "MilsimGame" }
    }
}

struct MissionPanelView: View {
    @ObservedObject var viewModel: GameViewModel

    var body: some View {
        let hud = viewModel.hud

        if hud.victory || hud.failed {
            HUDTextWindowChrome(text: missionPanelText(for: hud)) {
                HStack(spacing: 10) {
                    Button("Restart") {
                        viewModel.reset()
                    }
                    Button("Next Op") {
                        viewModel.nextMission()
                    }
                }
                .buttonStyle(HUDButtonStyle())
                .padding(.top, 4)
            }
        } else {
            HUDTextWindowChrome(text: missionPanelText(for: hud))
        }
    }
}

struct OperatorPanelView: View {
    @ObservedObject var viewModel: GameViewModel

    var body: some View {
        HUDTextWindowChrome(text: operatorPanelText(for: viewModel.hud))
    }
}

struct TacticalMapPanelView: View {
    @ObservedObject var viewModel: GameViewModel

    var body: some View {
        let hud = viewModel.hud

        HUDPanelChrome(title: "Tactical Map", scrolls: false) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Grid \(hud.gridReference)")
                        .foregroundStyle(HUDPalette.amber)
                    Text(hud.compass)
                        .foregroundStyle(HUDPalette.blue.opacity(0.9))
                    Spacer(minLength: 12)
                    Button(hud.mapExpanded ? "Collapse Map" : "Expand Map") {
                        viewModel.toggleMap()
                    }
                    .buttonStyle(HUDButtonStyle())
                }

                Text(hud.intelStatus)
                    .foregroundStyle(HUDPalette.sand.opacity(0.86))
                Text(hud.routeSummary)
                    .foregroundStyle(HUDPalette.blue.opacity(0.92))
                Text(hud.radioReport)
                    .foregroundStyle(HUDPalette.green.opacity(0.92))
                Text(hud.enemyActivity)
                    .foregroundStyle(HUDPalette.alert.opacity(0.9))
                Text(hud.fireteamStatus)
                    .foregroundStyle(HUDPalette.amber)

                HStack(spacing: 8) {
                    ForEach(FireteamOrderChoice.allCases) { order in
                        Button(order.title) {
                            viewModel.setFireteamOrder(order)
                        }
                        .buttonStyle(HUDButtonStyle(highlighted: hud.fireteamOrder == order))
                    }
                }

                if !hud.fireteamMembers.isEmpty {
                    ForEach(hud.fireteamMembers) { member in
                        Text("\(member.name) | \(member.detail)")
                            .foregroundStyle(member.isDowned ? HUDPalette.alert.opacity(0.94) : HUDPalette.sand.opacity(0.82))
                    }
                }

                if hud.mapExpanded {
                    TacticalMapView(hud: hud)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .frame(minHeight: 260)
                } else {
                    Text("Map collapsed. Press `M` or use the button above to reopen it.")
                        .foregroundStyle(HUDPalette.sand.opacity(0.82))
                        .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
                }

                Text(hud.interactionHint)
                    .foregroundStyle(HUDPalette.sand.opacity(0.88))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

struct ControlsPanelView: View {
    var body: some View {
        HUDTextWindowChrome(text: controlsPanelText)
    }
}

struct LoadoutPanelView: View {
    @ObservedObject var viewModel: GameViewModel

    var body: some View {
        let hud = viewModel.hud

        HUDTextWindowChrome(text: loadoutPanelText(for: hud)) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(hud.campaignSlots) { slot in
                    HStack(spacing: 10) {
                        Button(slot.isActive ? "Selected" : "Use \(slot.title)") {
                            viewModel.setCampaignSlot(slot.id)
                        }
                        .disabled(slot.isActive)

                        Button("Save \(slot.title)") {
                            viewModel.saveCampaign(to: slot.id)
                        }

                        Button("Load \(slot.title)") {
                            _ = viewModel.loadCampaign(from: slot.id)
                        }
                        .disabled(!slot.hasArchive)
                    }
                    .buttonStyle(HUDButtonStyle())
                }

                HStack(spacing: 10) {
                    Button("Save Active") {
                        viewModel.saveCampaign()
                    }
                    Button("Load Active") {
                        _ = viewModel.loadCampaign()
                    }
                }
                .buttonStyle(HUDButtonStyle())

                HStack(spacing: 10) {
                    Button("Restart") {
                        viewModel.reset()
                    }
                    Button("Next Op") {
                        viewModel.nextMission()
                    }
                    Button("View Mode") {
                        viewModel.togglePresentation()
                    }
                    Button("Full Screen") {
                        WindowCoordinator.toggleGameFullScreen()
                    }
                }
                .buttonStyle(HUDButtonStyle())
            }
        }
    }
}

private struct WindowConfigurator: NSViewRepresentable {
    let identifier: String
    let isHUDPanel: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            applyConfiguration(to: view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            applyConfiguration(to: nsView.window)
        }
    }

    private func applyConfiguration(to window: NSWindow?) {
        guard let window else {
            return
        }

        window.identifier = NSUserInterfaceItemIdentifier(identifier)
        window.tabbingMode = .disallowed

        if isHUDPanel {
            window.level = .floating
            window.collectionBehavior.insert(.moveToActiveSpace)
            window.collectionBehavior.insert(.fullScreenAuxiliary)
        } else {
            window.level = .normal
        }
    }
}

extension View {
    func managedMilsimWindow(identifier: String, isHUDPanel: Bool = false) -> some View {
        background(WindowConfigurator(identifier: identifier, isHUDPanel: isHUDPanel))
    }
}

private enum HUDPalette {
    static let sand = Color(red: 0.93, green: 0.87, blue: 0.69)
    static let amber = Color(red: 0.95, green: 0.73, blue: 0.25)
    static let ink = Color(red: 0.06, green: 0.08, blue: 0.08)
    static let olive = Color(red: 0.18, green: 0.26, blue: 0.19)
    static let slate = Color(red: 0.14, green: 0.2, blue: 0.22)
    static let alert = Color(red: 0.82, green: 0.23, blue: 0.18)
    static let blue = Color(red: 0.29, green: 0.66, blue: 0.95)
    static let green = Color(red: 0.33, green: 0.79, blue: 0.46)
}

private struct HUDPanelChrome<Content: View>: View {
    let title: String
    var scrolls = true
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            HUDPalette.ink.opacity(0.98)
                .ignoresSafeArea()

            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [HUDPalette.ink.opacity(0.82), HUDPalette.slate.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(HUDPalette.olive.opacity(0.95), lineWidth: 1.25)
                )
                .shadow(color: .black.opacity(0.3), radius: 18, x: 0, y: 10)
                .padding(10)

            if scrolls {
                ScrollView {
                    panelBody
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(28)
                }
            } else {
                panelBody
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(28)
            }
        }
        .font(.system(size: 14, weight: .medium, design: .monospaced))
    }

    @ViewBuilder
    private var panelBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .black, design: .monospaced))
                .kerning(1.8)
                .foregroundStyle(HUDPalette.amber)

            content()
        }
    }
}

private struct HUDTextWindowChrome<Footer: View>: View {
    let text: String
    let showsFooter: Bool
    let footer: Footer

    init(text: String) where Footer == EmptyView {
        self.text = text
        self.showsFooter = false
        self.footer = EmptyView()
    }

    init(text: String, @ViewBuilder footer: () -> Footer) {
        self.text = text
        self.showsFooter = true
        self.footer = footer()
    }

    var body: some View {
        VStack(spacing: 0) {
            SelectableTextWindow(text: text)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if showsFooter {
                Divider()

                footer
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .windowBackgroundColor))
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct SelectableTextWindow: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView(frame: .zero)
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor

        let textView = NSTextView(frame: .zero)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.usesFindPanel = true
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textColor = .textColor
        textView.textContainerInset = NSSize(width: 18, height: 18)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.string = text

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else {
            return
        }

        if textView.selectedRange().length > 0 {
            return
        }

        if textView.string != text {
            textView.string = text
        }
    }
}

private let controlsPanelText = """
Controls

WASD move   Shift sprint
Mouse aim   Left Mouse / Space fire
F or Right Mouse use / recover
R reload   B fire mode   V vault
H treat wounds / use gauze or splint
T cycle fireteam order
C crouch   Z prone   Q/E lean
Tab or wheel cycle   1 2 3 select
P presentation mode   M tactical map
Ctrl+Cmd+F full screen
Cmd+S save campaign   Cmd+L load campaign
"""

private func missionPanelText(for hud: HUDSnapshot) -> String {
    var lines: [String] = []
    append(line: hud.missionName, to: &lines)
    append(blankLineTo: &lines)
    append(line: hud.missionBrief, to: &lines)
    append(blankLineTo: &lines)
    append(line: hud.missionPhase, to: &lines)
    append(line: hud.missionBranch, to: &lines)
    append(line: hud.objective, to: &lines)
    append(line: hud.enemyActivity, to: &lines)
    append(line: hud.event, to: &lines)

    if hud.victory || hud.failed {
        append(blankLineTo: &lines)
        append(line: hud.victory ? "Operation complete." : "Mission failed.", to: &lines)
        append(line: hud.scoreHeadline, to: &lines)
        append(line: hud.scoreSummary, to: &lines)

        for row in hud.scoreRows {
            append(line: "\(row.label) | \(row.detail)", to: &lines)
        }
    }

    return lines.joined(separator: "\n")
}

private func operatorPanelText(for hud: HUDSnapshot) -> String {
    var lines: [String] = []
    append(line: hud.weapon, to: &lines)
    append(line: hud.ammo, to: &lines)
    append(line: hud.signature, to: &lines)
    append(line: hud.presentation, to: &lines)
    append(line: hud.presentationAssist, to: &lines)
    append(line: hud.posture, to: &lines)
    append(blankLineTo: &lines)
    append(line: hud.fireteamStatus, to: &lines)
    append(line: hud.enemyActivity, to: &lines)

    for member in hud.fireteamMembers {
        append(line: "\(member.name) | \(member.detail)", to: &lines)
    }

    append(blankLineTo: &lines)
    append(line: hud.health, to: &lines)
    append(line: hud.stamina, to: &lines)
    append(line: hud.wounds, to: &lines)
    append(line: hud.medical, to: &lines)
    append(line: "\(hud.compass) | Grid \(hud.gridReference)", to: &lines)
    append(line: hud.mission, to: &lines)
    return lines.joined(separator: "\n")
}

private func loadoutPanelText(for hud: HUDSnapshot) -> String {
    var lines: [String] = []
    append(line: "Loadout", to: &lines)
    append(blankLineTo: &lines)

    if hud.inventory.isEmpty {
        append(line: "No equipment recovered", to: &lines)
    } else {
        append(line: "Recovered Equipment", to: &lines)
        for row in hud.inventory {
            let marker = row.isSelected ? ">" : "-"
            append(line: "\(marker) \(row.label)", to: &lines)
        }
    }

    append(blankLineTo: &lines)
    append(line: hud.campaignStatus, to: &lines)
    append(line: hud.saveStatus, to: &lines)
    append(blankLineTo: &lines)
    append(line: "Campaign Slots", to: &lines)

    for slot in hud.campaignSlots {
        let status = slot.isActive ? "ACTIVE" : (slot.hasArchive ? "ARCHIVED" : "EMPTY")
        append(line: "\(slot.title) | \(status)", to: &lines)
        append(line: slot.detail, to: &lines)
        append(blankLineTo: &lines)
    }

    return lines.joined(separator: "\n")
}

private func append(line: String, to lines: inout [String]) {
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        return
    }
    lines.append(trimmed)
}

private func append(blankLineTo lines: inout [String]) {
    guard let last = lines.last, !last.isEmpty else {
        return
    }
    lines.append("")
}

private struct TacticalMapView: View {
    let hud: HUDSnapshot

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(HUDPalette.ink.opacity(0.72))

                ForEach(hud.mapTiles) { tile in
                    Rectangle()
                        .fill(tileColor(tile).opacity(tile.conceals ? 0.95 : 0.82))
                        .frame(
                            width: proxy.size.width * CGFloat(tile.size.x / (hud.worldHalfSize.x * 2)),
                            height: proxy.size.height * CGFloat(tile.size.y / (hud.worldHalfSize.y * 2))
                        )
                        .position(mapPoint(for: tile.position, in: proxy.size))
                }

                gridOverlay(in: proxy.size)
                    .stroke(HUDPalette.sand.opacity(0.12), lineWidth: 1)

                routeOverlay(in: proxy.size)
                    .stroke(
                        LinearGradient(
                            colors: [HUDPalette.amber.opacity(0.95), HUDPalette.blue.opacity(0.95)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round, dash: [7, 4])
                    )

                ForEach(hud.mapMarkers) { marker in
                    VStack(spacing: 3) {
                        markerGlyph(for: marker)
                        if marker.prominent {
                            Text(shortLabel(marker.label))
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(HUDPalette.sand)
                                .lineLimit(1)
                        }
                    }
                    .position(mapPoint(for: marker.position, in: proxy.size))
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(HUDPalette.olive.opacity(0.92), lineWidth: 1.1)
            )
        }
    }

    private func routeOverlay(in size: CGSize) -> Path {
        var path = Path()

        for segment in hud.routeSegments {
            path.move(to: mapPoint(for: segment.start, in: size))
            path.addLine(to: mapPoint(for: segment.end, in: size))
        }

        return path
    }

    private func mapPoint(for position: SIMD2<Float>, in size: CGSize) -> CGPoint {
        let x = CGFloat((position.x + hud.worldHalfSize.x) / (hud.worldHalfSize.x * 2)) * size.width
        let y = (1 - CGFloat((position.y + hud.worldHalfSize.y) / (hud.worldHalfSize.y * 2))) * size.height
        return CGPoint(x: x, y: y)
    }

    private func gridOverlay(in size: CGSize) -> Path {
        var path = Path()
        let columns = 14
        let rows = 10

        for column in 1..<columns {
            let x = size.width * CGFloat(column) / CGFloat(columns)
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))
        }

        for row in 1..<rows {
            let y = size.height * CGFloat(row) / CGFloat(rows)
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
        }

        return path
    }

    @ViewBuilder
    private func markerGlyph(for marker: TacticalMapMarker) -> some View {
        switch marker.kind {
        case .player:
            Circle()
                .fill(HUDPalette.blue)
                .frame(width: 12, height: 12)
                .overlay(Circle().stroke(HUDPalette.sand, lineWidth: 1))
        case .friendly:
            Circle()
                .fill(HUDPalette.green)
                .frame(width: 10, height: 10)
                .overlay(Circle().stroke(HUDPalette.blue.opacity(0.9), lineWidth: 1))
        case .objective:
            Circle()
                .stroke(HUDPalette.amber, lineWidth: 2)
                .frame(width: 14, height: 14)
                .overlay(Circle().fill(HUDPalette.amber.opacity(0.35)).frame(width: 6, height: 6))
        case .extraction:
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(HUDPalette.green)
                .frame(width: 12, height: 12)
                .rotationEffect(.degrees(45))
        case .door:
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(HUDPalette.sand.opacity(0.7))
                .frame(width: 10, height: 4)
        case .supply:
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(HUDPalette.blue.opacity(0.92))
                .frame(width: 10, height: 10)
        case .deadDrop:
            Circle()
                .fill(HUDPalette.amber.opacity(0.82))
                .frame(width: 10, height: 10)
        case .radio:
            Circle()
                .stroke(HUDPalette.green, lineWidth: 2)
                .frame(width: 14, height: 14)
                .overlay(Rectangle().fill(HUDPalette.green).frame(width: 2, height: 12))
        case .emplaced:
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(HUDPalette.alert.opacity(0.92))
                .frame(width: 14, height: 6)
        case .enemy:
            Circle()
                .fill(HUDPalette.alert)
                .frame(width: 9, height: 9)
                .overlay(Circle().stroke(HUDPalette.sand.opacity(0.6), lineWidth: 0.8))
        }
    }

    private func tileColor(_ tile: TacticalMapTile) -> Color {
        switch tile.material {
        case .grass:
            return Color(red: 0.23, green: 0.33, blue: 0.22)
        case .road:
            return Color(red: 0.31, green: 0.31, blue: 0.29)
        case .mud:
            return Color(red: 0.37, green: 0.25, blue: 0.18)
        case .rock:
            return Color(red: 0.45, green: 0.41, blue: 0.34)
        case .compound:
            return Color(red: 0.52, green: 0.47, blue: 0.38)
        case .forest:
            return Color(red: 0.16, green: 0.39, blue: 0.2)
        }
    }

    private func shortLabel(_ label: String) -> String {
        if label.count <= 12 {
            return label
        }
        return String(label.prefix(12))
    }
}

private struct HUDButtonStyle: ButtonStyle {
    var highlighted = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        highlighted
                            ? HUDPalette.amber.opacity(configuration.isPressed ? 0.82 : 0.7)
                            : HUDPalette.olive.opacity(configuration.isPressed ? 0.95 : 0.8)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke((highlighted ? HUDPalette.sand : HUDPalette.amber).opacity(0.78), lineWidth: 1)
            )
            .foregroundStyle(highlighted ? HUDPalette.ink : HUDPalette.sand)
    }
}
