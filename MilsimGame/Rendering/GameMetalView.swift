import MetalKit
import SwiftUI
import simd

fileprivate enum InputAction: Hashable {
    case collect
    case reload
    case cycleNext
    case cyclePrevious
    case primary
    case secondary
    case melee
    case toggleFireMode
    case crouch
    case prone
    case vault
}

final class InputController {
    private var heldKeys: Set<UInt16> = []
    private var queuedActions: Set<InputAction> = []
    private var isMouseFiring = false
    private var isKeyboardFiring = false
    private var mouseLocation = CGPoint.zero
    private var lastAim = SIMD2<Float>(1, 0)

    func reset() {
        heldKeys.removeAll()
        queuedActions.removeAll()
        isMouseFiring = false
        isKeyboardFiring = false
        mouseLocation = .zero
        lastAim = SIMD2<Float>(1, 0)
    }

    func handleKeyDown(_ keyCode: UInt16) {
        heldKeys.insert(keyCode)

        switch keyCode {
        case 3:
            queuedActions.insert(.collect)
        case 15:
            queuedActions.insert(.reload)
        case 48:
            queuedActions.insert(.cycleNext)
        case 11:
            queuedActions.insert(.toggleFireMode)
        case 8:
            queuedActions.insert(.crouch)
        case 6:
            queuedActions.insert(.prone)
        case 9:
            queuedActions.insert(.vault)
        case 18:
            queuedActions.insert(.primary)
        case 19:
            queuedActions.insert(.secondary)
        case 20:
            queuedActions.insert(.melee)
        case 49:
            isKeyboardFiring = true
        default:
            break
        }
    }

    func handleKeyUp(_ keyCode: UInt16) {
        heldKeys.remove(keyCode)
        if keyCode == 49 {
            isKeyboardFiring = false
        }
    }

    func updateMouseLocation(_ point: CGPoint) {
        mouseLocation = point
    }

    func setMouseFiring(_ firing: Bool) {
        isMouseFiring = firing
    }

    fileprivate func queueAction(_ action: InputAction) {
        queuedActions.insert(action)
    }

    func makeInput(viewSize: CGSize, worldViewport: SIMD2<Float>) -> InputState {
        var input = InputState()
        game_reset_input(&input)

        if heldKeys.contains(13) || heldKeys.contains(126) {
            input.moveY += 1
        }
        if heldKeys.contains(1) || heldKeys.contains(125) {
            input.moveY -= 1
        }
        if heldKeys.contains(0) || heldKeys.contains(123) {
            input.moveX -= 1
        }
        if heldKeys.contains(2) || heldKeys.contains(124) {
            input.moveX += 1
        }

        if heldKeys.contains(12) {
            input.lean -= 1
        }
        if heldKeys.contains(14) {
            input.lean += 1
        }

        input.wantsSprint = heldKeys.contains(56) || heldKeys.contains(60)
        input.wantsFire = isMouseFiring || isKeyboardFiring

        let safeWidth = max(Float(viewSize.width), 1)
        let safeHeight = max(Float(viewSize.height), 1)
        let center = SIMD2<Float>(safeWidth * 0.5, safeHeight * 0.5)
        let mouse = SIMD2<Float>(Float(mouseLocation.x), Float(mouseLocation.y))
        let unitsPerPoint = SIMD2<Float>(worldViewport.x / safeWidth, worldViewport.y / safeHeight)
        var aimVector = (mouse - center) * unitsPerPoint

        if simd_length_squared(aimVector) < 4 {
            aimVector = lastAim * 120
        } else {
            lastAim = simd_normalize(aimVector)
        }

        input.aimX = aimVector.x
        input.aimY = aimVector.y
        input.wantsCollect = queuedActions.remove(.collect) != nil
        input.wantsReload = queuedActions.remove(.reload) != nil
        input.wantsCycleNext = queuedActions.remove(.cycleNext) != nil
        input.wantsCyclePrevious = queuedActions.remove(.cyclePrevious) != nil
        input.wantsPrimary = queuedActions.remove(.primary) != nil
        input.wantsSecondary = queuedActions.remove(.secondary) != nil
        input.wantsMelee = queuedActions.remove(.melee) != nil
        input.wantsToggleFireMode = queuedActions.remove(.toggleFireMode) != nil
        input.wantsCrouchToggle = queuedActions.remove(.crouch) != nil
        input.wantsProneToggle = queuedActions.remove(.prone) != nil
        input.wantsVault = queuedActions.remove(.vault) != nil

        return input
    }
}

final class TrackingMetalView: MTKView {
    private let inputController: InputController
    private let onToggleMap: () -> Void
    private var mouseTrackingArea: NSTrackingArea?

    init(device: MTLDevice, inputController: InputController, onToggleMap: @escaping () -> Void) {
        self.inputController = inputController
        self.onToggleMap = onToggleMap
        super.init(frame: .zero, device: device)

        colorPixelFormat = .bgra8Unorm
        clearColor = MTLClearColor(red: 0.02, green: 0.05, blue: 0.04, alpha: 1.0)
        preferredFramesPerSecond = 60
        framebufferOnly = false
        enableSetNeedsDisplay = false
        isPaused = false
        wantsLayer = true
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
        window?.makeFirstResponder(self)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let mouseTrackingArea {
            removeTrackingArea(mouseTrackingArea)
        }

        let newTrackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(newTrackingArea)
        mouseTrackingArea = newTrackingArea
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 46 {
            onToggleMap()
            return
        }
        inputController.handleKeyDown(event.keyCode)
    }

    override func keyUp(with event: NSEvent) {
        inputController.handleKeyUp(event.keyCode)
    }

    override func mouseMoved(with event: NSEvent) {
        inputController.updateMouseLocation(convert(event.locationInWindow, from: nil))
    }

    override func mouseDragged(with event: NSEvent) {
        inputController.updateMouseLocation(convert(event.locationInWindow, from: nil))
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        inputController.updateMouseLocation(convert(event.locationInWindow, from: nil))
        inputController.setMouseFiring(true)
    }

    override func mouseUp(with event: NSEvent) {
        inputController.setMouseFiring(false)
    }

    override func rightMouseDown(with event: NSEvent) {
        inputController.queueAction(.collect)
    }

    override func scrollWheel(with event: NSEvent) {
        if event.scrollingDeltaY < 0 {
            inputController.queueAction(.cycleNext)
        } else if event.scrollingDeltaY > 0 {
            inputController.queueAction(.cyclePrevious)
        }
    }
}

struct MetalGameView: NSViewRepresentable {
    @ObservedObject var viewModel: GameViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    func makeNSView(context: Context) -> TrackingMetalView {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is required to run MilsimGame.")
        }

        let view = TrackingMetalView(
            device: device,
            inputController: context.coordinator.inputController,
            onToggleMap: context.coordinator.viewModel.toggleMap
        )
        context.coordinator.renderer = GameRenderer(view: view, viewModel: viewModel, inputController: context.coordinator.inputController)
        view.delegate = context.coordinator.renderer
        return view
    }

    func updateNSView(_ nsView: TrackingMetalView, context: Context) {
        context.coordinator.renderer?.viewModel = viewModel
    }

    final class Coordinator {
        let inputController = InputController()
        let viewModel: GameViewModel
        var renderer: GameRenderer?

        init(viewModel: GameViewModel) {
            self.viewModel = viewModel
        }
    }
}
