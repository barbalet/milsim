import AppKit
import SwiftUI

struct GameView: View {
    @ObservedObject var viewModel: GameViewModel

    var body: some View {
        ZStack {
            MetalGameView(viewModel: viewModel)

            HUDOverlayView(
                hud: viewModel.hud,
                onRestart: { viewModel.reset() },
                onToggleFullScreen: { NSApp.keyWindow?.toggleFullScreen(nil) }
            )
            .padding(22)
        }
        .background(Color.black)
        .ignoresSafeArea()
    }
}

