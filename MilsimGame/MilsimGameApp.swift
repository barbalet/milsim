import AppKit
import SwiftUI

@main
struct MilsimGameApp: App {
    @StateObject private var viewModel = GameViewModel()

    var body: some Scene {
        Window("MilsimGame", id: AppWindowID.game) {
            GameView(viewModel: viewModel)
                .frame(minWidth: 1100, minHeight: 700)
                .managedMilsimWindow(identifier: AppWindowID.game)
        }
        .defaultSize(width: 1420, height: 900)
        .windowResizability(.automatic)
        .commands {
            MilsimCommands(viewModel: viewModel)
        }

        Window(HUDPanelWindowID.mission.title, id: HUDPanelWindowID.mission.rawValue) {
            MissionPanelView(viewModel: viewModel)
                .frame(minWidth: 380, minHeight: 250)
                .managedMilsimWindow(identifier: HUDPanelWindowID.mission.rawValue, isHUDPanel: true)
        }
        .defaultSize(width: 460, height: 300)
        .windowResizability(.automatic)

        Window(HUDPanelWindowID.operatorStatus.title, id: HUDPanelWindowID.operatorStatus.rawValue) {
            OperatorPanelView(viewModel: viewModel)
                .frame(minWidth: 390, minHeight: 320)
                .managedMilsimWindow(identifier: HUDPanelWindowID.operatorStatus.rawValue, isHUDPanel: true)
        }
        .defaultSize(width: 480, height: 430)
        .windowResizability(.automatic)

        Window(HUDPanelWindowID.tacticalMap.title, id: HUDPanelWindowID.tacticalMap.rawValue) {
            TacticalMapPanelView(viewModel: viewModel)
                .frame(minWidth: 420, minHeight: 360)
                .managedMilsimWindow(identifier: HUDPanelWindowID.tacticalMap.rawValue, isHUDPanel: true)
        }
        .defaultSize(width: 520, height: 470)
        .windowResizability(.automatic)

        Window(HUDPanelWindowID.controls.title, id: HUDPanelWindowID.controls.rawValue) {
            ControlsPanelView()
                .frame(minWidth: 300, minHeight: 220)
                .managedMilsimWindow(identifier: HUDPanelWindowID.controls.rawValue, isHUDPanel: true)
        }
        .defaultSize(width: 360, height: 290)
        .windowResizability(.automatic)

        Window(HUDPanelWindowID.loadout.title, id: HUDPanelWindowID.loadout.rawValue) {
            LoadoutPanelView(viewModel: viewModel)
                .frame(minWidth: 360, minHeight: 320)
                .managedMilsimWindow(identifier: HUDPanelWindowID.loadout.rawValue, isHUDPanel: true)
        }
        .defaultSize(width: 460, height: 440)
        .windowResizability(.automatic)
    }
}

private struct MilsimCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    let viewModel: GameViewModel

    var body: some Commands {
        CommandMenu("Milsim") {
            Button("Toggle Full Screen") {
                WindowCoordinator.toggleGameFullScreen()
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

            Button("Toggle Presentation Mode") {
                viewModel.togglePresentation()
            }
            .keyboardShortcut("p", modifiers: [])
        }

        CommandMenu("Panels") {
            Button("Game Window") {
                WindowCoordinator.showGameWindow(using: openWindow)
            }

            Button("Show All Panels") {
                WindowCoordinator.showAllPanels(using: openWindow)
            }

            Button(HUDPanelWindowID.mission.title) {
                openWindow(id: HUDPanelWindowID.mission.rawValue)
            }

            Button(HUDPanelWindowID.operatorStatus.title) {
                openWindow(id: HUDPanelWindowID.operatorStatus.rawValue)
            }

            Button(HUDPanelWindowID.tacticalMap.title) {
                openWindow(id: HUDPanelWindowID.tacticalMap.rawValue)
            }

            Button(HUDPanelWindowID.controls.title) {
                openWindow(id: HUDPanelWindowID.controls.rawValue)
            }

            Button(HUDPanelWindowID.loadout.title) {
                openWindow(id: HUDPanelWindowID.loadout.rawValue)
            }
        }
    }
}
