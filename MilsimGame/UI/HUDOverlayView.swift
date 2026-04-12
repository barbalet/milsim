import SwiftUI

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

struct HUDOverlayView: View {
    let hud: HUDSnapshot
    let onRestart: () -> Void
    let onNextMission: () -> Void
    let onSaveCampaign: () -> Void
    let onLoadCampaign: () -> Void
    let onToggleFullScreen: () -> Void
    let onToggleMap: () -> Void
    let onTogglePresentation: () -> Void

    var body: some View {
        ZStack {
            VStack(spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    hudCard(title: "Mission") {
                        Text(hud.missionName)
                            .font(.system(size: 21, weight: .black, design: .monospaced))
                            .foregroundStyle(HUDPalette.sand)
                        Text(hud.missionBrief)
                            .foregroundStyle(HUDPalette.sand.opacity(0.9))
                        Text(hud.objective)
                            .foregroundStyle(HUDPalette.amber)
                        Text(hud.event)
                            .foregroundStyle(HUDPalette.sand.opacity(0.82))
                    }
                    .frame(maxWidth: 560, alignment: .leading)

                    Spacer(minLength: 16)

                    hudCard(title: "Operator") {
                        Text(hud.weapon)
                            .font(.system(size: 19, weight: .bold, design: .monospaced))
                            .foregroundStyle(HUDPalette.sand)
                        Text(hud.ammo)
                            .foregroundStyle(HUDPalette.sand.opacity(0.95))
                        Text(hud.signature)
                            .foregroundStyle(HUDPalette.blue.opacity(0.88))
                        Text(hud.presentation)
                            .foregroundStyle(HUDPalette.green.opacity(0.88))
                        Text(hud.presentationAssist)
                            .foregroundStyle(HUDPalette.sand.opacity(0.86))
                        Text(hud.posture)
                            .foregroundStyle(HUDPalette.amber)
                        Text(hud.health)
                            .foregroundStyle(HUDPalette.sand)
                        Text(hud.stamina)
                            .foregroundStyle(HUDPalette.sand)
                        Text(hud.wounds)
                            .foregroundStyle(HUDPalette.alert.opacity(0.92))
                        Text(hud.medical)
                            .foregroundStyle(HUDPalette.green.opacity(0.92))
                        Text("\(hud.compass) | Grid \(hud.gridReference)")
                            .foregroundStyle(HUDPalette.blue.opacity(0.92))
                        Text(hud.mission)
                            .foregroundStyle(HUDPalette.sand.opacity(0.8))
                    }
                    .frame(maxWidth: 450, alignment: .leading)
                }

                Spacer()

                HStack(alignment: .bottom, spacing: 16) {
                    hudCard(title: "Tactical Map") {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Grid \(hud.gridReference)")
                                .foregroundStyle(HUDPalette.amber)
                            Text(hud.compass)
                                .foregroundStyle(HUDPalette.blue.opacity(0.9))
                            Spacer(minLength: 12)
                            Button(hud.mapExpanded ? "Collapse Map" : "Expand Map", action: onToggleMap)
                                .buttonStyle(HUDButtonStyle())
                        }

                        Text(hud.intelStatus)
                            .foregroundStyle(HUDPalette.sand.opacity(0.86))
                        Text(hud.routeSummary)
                            .foregroundStyle(HUDPalette.blue.opacity(0.92))
                        Text(hud.radioReport)
                            .foregroundStyle(HUDPalette.green.opacity(0.92))

                        if hud.mapExpanded {
                            TacticalMapView(hud: hud)
                                .frame(width: 340, height: 230)
                        }

                        Text(hud.interactionHint)
                            .foregroundStyle(HUDPalette.sand.opacity(0.88))
                    }
                    .frame(width: hud.mapExpanded ? 380 : 320, alignment: .leading)

                    hudCard(title: "Controls") {
                        Text("WASD move   Shift sprint")
                        Text("Mouse aim   Left Mouse / Space fire")
                        Text("F or Right Mouse use / recover")
                        Text("R reload   B fire mode   V vault")
                        Text("H treat wounds / use gauze or splint")
                        Text("C crouch   Z prone   Q/E lean")
                        Text("Tab or wheel cycle   1 2 3 select")
                        Text("P presentation mode   M tactical map")
                        Text("Ctrl+Cmd+F full screen")
                        Text("Cmd+S save campaign   Cmd+L load campaign")
                    }
                    .frame(width: 300, alignment: .leading)

                    Spacer(minLength: 16)

                    hudCard(title: "Loadout") {
                        if hud.inventory.isEmpty {
                            Text("No equipment recovered")
                                .foregroundStyle(HUDPalette.sand.opacity(0.85))
                        } else {
                            ForEach(hud.inventory) { row in
                                Text(row.label)
                                    .font(.system(size: 13, weight: row.isSelected ? .bold : .regular, design: .monospaced))
                                    .foregroundStyle(row.isSelected ? HUDPalette.amber : HUDPalette.sand)
                            }
                        }

                        Text(hud.campaignStatus)
                            .foregroundStyle(HUDPalette.blue.opacity(0.92))
                            .padding(.top, 6)
                        Text(hud.saveStatus)
                            .foregroundStyle(HUDPalette.green.opacity(0.9))

                        HStack(spacing: 10) {
                            Button("Save", action: onSaveCampaign)
                            Button("Load", action: onLoadCampaign)
                        }
                        .buttonStyle(HUDButtonStyle())
                        .padding(.top, 8)

                        HStack(spacing: 10) {
                            Button("Restart", action: onRestart)
                            Button("Next Op", action: onNextMission)
                            Button("View Mode", action: onTogglePresentation)
                            Button("Full Screen", action: onToggleFullScreen)
                        }
                        .buttonStyle(HUDButtonStyle())
                    }
                    .frame(maxWidth: 500, alignment: .leading)
                }
            }

            if hud.victory || hud.failed {
                Color.black.opacity(0.48)
                    .ignoresSafeArea()

                hudCard(title: hud.victory ? "Operation Complete" : "Mission Failed") {
                    Text(hud.victory ? "The objective package made it to extraction." : "The operator was lost before exfiltration.")
                        .foregroundStyle(HUDPalette.sand)
                    Text(hud.event)
                        .foregroundStyle(hud.victory ? HUDPalette.amber : HUDPalette.alert)

                    HStack(spacing: 12) {
                        Button("Restart", action: onRestart)
                        Button("Next Op", action: onNextMission)
                    }
                    .buttonStyle(HUDButtonStyle())
                    .padding(.top, 6)
                }
                .frame(width: 440)
            }
        }
        .font(.system(size: 14, weight: .medium, design: .monospaced))
    }

    @ViewBuilder
    private func hudCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .black, design: .monospaced))
                .kerning(1.8)
                .foregroundStyle(HUDPalette.amber)

            content()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [HUDPalette.ink.opacity(0.82), HUDPalette.slate.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(HUDPalette.olive.opacity(0.95), lineWidth: 1.25)
        )
        .shadow(color: .black.opacity(0.3), radius: 18, x: 0, y: 10)
    }
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
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(HUDPalette.olive.opacity(configuration.isPressed ? 0.95 : 0.8))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(HUDPalette.amber.opacity(0.7), lineWidth: 1)
            )
            .foregroundStyle(HUDPalette.sand)
    }
}
