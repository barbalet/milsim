import AppKit
import SwiftUI

@main
struct MilsimGameApp: App {
    @StateObject private var viewModel = GameViewModel()

    var body: some Scene {
        WindowGroup {
            GameView(viewModel: viewModel)
                .frame(minWidth: 1100, minHeight: 700)
        }
        .windowResizability(.automatic)
        .commands {
            CommandMenu("Milsim") {
                Button("Toggle Full Screen") {
                    NSApp.keyWindow?.toggleFullScreen(nil)
                }
                .keyboardShortcut("f", modifiers: [.command, .control])

                Button("Restart Scenario") {
                    viewModel.reset()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])

                Button("Save Campaign") {
                    viewModel.saveCampaign()
                }
                .keyboardShortcut("s", modifiers: [.command])

                Button("Load Campaign") {
                    _ = viewModel.loadCampaign()
                }
                .keyboardShortcut("l", modifiers: [.command])

                Button("Next Operation") {
                    viewModel.nextMission()
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                Button("Toggle Tactical Map") {
                    viewModel.toggleMap()
                }
                .keyboardShortcut("m", modifiers: [])
            }
        }
    }
}
