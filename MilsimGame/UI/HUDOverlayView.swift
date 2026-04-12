import SwiftUI

private enum HUDPalette {
    static let sand = Color(red: 0.93, green: 0.87, blue: 0.69)
    static let amber = Color(red: 0.95, green: 0.73, blue: 0.25)
    static let ink = Color(red: 0.06, green: 0.08, blue: 0.08)
    static let olive = Color(red: 0.18, green: 0.26, blue: 0.19)
    static let alert = Color(red: 0.82, green: 0.23, blue: 0.18)
}

struct HUDOverlayView: View {
    let hud: HUDSnapshot
    let onRestart: () -> Void
    let onToggleFullScreen: () -> Void

    var body: some View {
        ZStack {
            VStack(spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    hudCard(title: "Mission") {
                        Text(hud.objective)
                            .foregroundStyle(HUDPalette.sand)
                        Text(hud.event)
                            .foregroundStyle(HUDPalette.amber)
                    }
                    .frame(maxWidth: 500, alignment: .leading)

                    Spacer(minLength: 16)

                    hudCard(title: "Operator") {
                        Text(hud.weapon)
                            .font(.system(size: 19, weight: .bold, design: .monospaced))
                            .foregroundStyle(HUDPalette.sand)
                        Text(hud.ammo)
                            .foregroundStyle(HUDPalette.sand.opacity(0.92))
                        Text("\(hud.health) | \(hud.stamina)")
                            .foregroundStyle(HUDPalette.amber)
                        Text(hud.mission)
                            .foregroundStyle(HUDPalette.sand.opacity(0.8))
                    }
                    .frame(maxWidth: 420, alignment: .leading)
                }

                Spacer()

                HStack(alignment: .bottom, spacing: 16) {
                    hudCard(title: "Controls") {
                        Text("WASD move")
                        Text("Shift sprint")
                        Text("Mouse aim")
                        Text("Left Mouse / Space fire")
                        Text("E collect   R reload")
                        Text("Q / Tab cycle   1 2 3 select")
                    }
                    .frame(width: 250, alignment: .leading)

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
                            Button("Toggle Full Screen", action: onToggleFullScreen)
                        }
                        .buttonStyle(HUDButtonStyle())
                        .padding(.top, 8)
                    }
                    .frame(maxWidth: 430, alignment: .leading)
                }
            }

            if hud.victory || hud.failed {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()

                hudCard(title: hud.victory ? "Extraction Complete" : "Mission Failed") {
                    Text(hud.victory ? "The raid package made it to the extraction point." : "The operator was lost during the exercise.")
                        .foregroundStyle(HUDPalette.sand)
                    Text(hud.event)
                        .foregroundStyle(hud.victory ? HUDPalette.amber : HUDPalette.alert)

                    HStack(spacing: 12) {
                        Button("Restart", action: onRestart)
                        Button("Toggle Full Screen", action: onToggleFullScreen)
                    }
                    .buttonStyle(HUDButtonStyle())
                    .padding(.top, 6)
                }
                .frame(width: 420)
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
                .fill(HUDPalette.ink.opacity(0.78))
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

