import SwiftUI

private enum HUDPalette {
    static let sand = Color(red: 0.93, green: 0.87, blue: 0.69)
    static let amber = Color(red: 0.95, green: 0.73, blue: 0.25)
    static let ink = Color(red: 0.06, green: 0.08, blue: 0.08)
    static let olive = Color(red: 0.18, green: 0.26, blue: 0.19)
    static let slate = Color(red: 0.14, green: 0.2, blue: 0.22)
    static let alert = Color(red: 0.82, green: 0.23, blue: 0.18)
}

struct HUDOverlayView: View {
    let hud: HUDSnapshot
    let onRestart: () -> Void
    let onNextMission: () -> Void
    let onToggleFullScreen: () -> Void

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
                        Text(hud.posture)
                            .foregroundStyle(HUDPalette.amber)
                        Text("\(hud.health) | \(hud.stamina)")
                            .foregroundStyle(HUDPalette.sand)
                        Text(hud.mission)
                            .foregroundStyle(HUDPalette.sand.opacity(0.8))
                    }
                    .frame(maxWidth: 430, alignment: .leading)
                }

                Spacer()

                HStack(alignment: .bottom, spacing: 16) {
                    hudCard(title: "Controls") {
                        Text("WASD move   Shift sprint")
                        Text("Mouse aim   Left Mouse / Space fire")
                        Text("F or Right Mouse collect")
                        Text("R reload   B fire mode   V vault")
                        Text("C crouch   Z prone   Q/E lean")
                        Text("Tab or wheel cycle   1 2 3 select")
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

                        HStack(spacing: 10) {
                            Button("Restart", action: onRestart)
                            Button("Next Op", action: onNextMission)
                            Button("Full Screen", action: onToggleFullScreen)
                        }
                        .buttonStyle(HUDButtonStyle())
                        .padding(.top, 8)
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
