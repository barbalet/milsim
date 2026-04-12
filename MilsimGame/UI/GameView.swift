import SwiftUI

struct GameView: View {
    @ObservedObject var viewModel: GameViewModel
    @Environment(\.openWindow) private var openWindow
    @State private var openedCompanionWindows = false

    var body: some View {
        MetalGameView(viewModel: viewModel)
        .background(Color.black)
        .ignoresSafeArea()
        .onAppear {
            guard !openedCompanionWindows else {
                return
            }
            openedCompanionWindows = true
            WindowCoordinator.showAllPanels(using: openWindow)
        }
    }
}
