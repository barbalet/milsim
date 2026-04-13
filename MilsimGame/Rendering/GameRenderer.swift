import MetalKit
import QuartzCore
import simd

private enum RenderShape: UInt32 {
    case rectangle = 0
    case circle = 1
    case ring = 2
}

private struct RenderInstance {
    var position: SIMD2<Float>
    var size: SIMD2<Float>
    var color: SIMD4<Float>
    var rotation: Float
    var shape: UInt32
    var padding: SIMD2<Float> = .zero
}

private struct RenderUniforms {
    var camera: SIMD2<Float>
    var worldViewport: SIMD2<Float>
}

private struct PerspectiveLayer {
    var depth: Float
    var instances: [RenderInstance]
}

private struct PerspectiveProjection {
    var position: SIMD2<Float>
    var size: SIMD2<Float>
    var depth: Float
    var footY: Float
}

private struct FocusOverlay {
    var position: SIMD2<Float>
    var size: SIMD2<Float>
    var footY: Float
    var color: SIMD4<Float>
    var score: Float
}

private struct OcclusionField {
    private static let binCount = 54
    private static let viewMin: Float = -1.25
    private static let viewMax: Float = 1.25

    private var depths = Array(repeating: Float.greatestFiniteMagnitude, count: binCount)
    private var strengths = Array(repeating: Float.zero, count: binCount)

    mutating func register(center: Float, width: Float, depth: Float, strength: Float) {
        guard let range = indexRange(center: center, width: width) else {
            return
        }

        for index in range {
            if depth < depths[index] {
                depths[index] = depth
            }
            strengths[index] = max(strengths[index], strength)
        }
    }

    func visibility(center: Float, width: Float, depth: Float, softness: Float = 26) -> Float {
        guard let range = indexRange(center: center, width: width) else {
            return 1.0
        }

        var blockedAmount: Float = 0
        var sampleCount: Float = 0

        for index in range {
            let blockerDepth = depths[index]
            if !blockerDepth.isFinite || blockerDepth + softness >= depth {
                continue
            }

            let blockerStrength = strengths[index]
            let depthInfluence = min(max((depth - blockerDepth - softness) / 150.0, 0.18), 1.0)
            blockedAmount += blockerStrength * depthInfluence
            sampleCount += 1
        }

        guard sampleCount > 0 else {
            return 1.0
        }

        let occlusion = min(0.92, blockedAmount / sampleCount)
        return max(0.08, 1.0 - occlusion)
    }

    func nearestDepth(around center: Float, fallback: Float) -> Float {
        guard let range = indexRange(center: center, width: 0.16) else {
            return fallback
        }

        var nearest = fallback
        for index in range where strengths[index] > 0.18 {
            nearest = min(nearest, depths[index])
        }
        return nearest
    }

    private func indexRange(center: Float, width: Float) -> ClosedRange<Int>? {
        let halfWidth = max(0.02, width * 0.5)
        let minX = max(Self.viewMin, center - halfWidth)
        let maxX = min(Self.viewMax, center + halfWidth)
        guard maxX >= minX else {
            return nil
        }

        let span = Self.viewMax - Self.viewMin
        let lower = Int(floor(((minX - Self.viewMin) / span) * Float(Self.binCount - 1)))
        let upper = Int(ceil(((maxX - Self.viewMin) / span) * Float(Self.binCount - 1)))
        let clampedLower = max(0, min(Self.binCount - 1, lower))
        let clampedUpper = max(clampedLower, min(Self.binCount - 1, upper))
        return clampedLower...clampedUpper
    }
}

private struct World3DVertex {
    var position: SIMD3<Float>
    var normal: SIMD3<Float>
}

private struct World3DInstance {
    var position: SIMD3<Float>
    var yaw: Float
    var size: SIMD3<Float>
    var lighting: Float
    var color: SIMD4<Float>
}

private struct World3DUniforms {
    var viewProjectionMatrix: simd_float4x4
    var cameraPosition: SIMD3<Float>
    var fogStart: Float
    var lightDirection: SIMD3<Float>
    var fogEnd: Float
    var fogColor: SIMD4<Float>
    var sunColor: SIMD4<Float>
    var ambientColor: SIMD4<Float>
    var shadowColor: SIMD4<Float>
    var hazeColor: SIMD4<Float>
}

private struct FirstPersonCameraRig {
    var position: SIMD3<Float>
    var forward: SIMD3<Float>
    var right: SIMD3<Float>
    var up: SIMD3<Float>
    var horizon: Float
    var sway: Float
    var cameraOffset: Float
}

private struct FirstPersonWorldScene {
    var camera: FirstPersonCameraRig
    var worldUniforms: World3DUniforms
    var backdropInstances: [RenderInstance]
    var worldInstances: [World3DInstance]
    var overlayInstances: [RenderInstance]
}

private struct FirstPersonAimSolution {
    var screenPosition: SIMD2<Float>
    var worldPoint: SIMD3<Float>
    var distanceGameUnits: Float
    var distanceWorldUnits: Float
}

private struct FirstPersonFocusCue {
    var screenPosition: SIMD2<Float>
    var size: SIMD2<Float>
    var color: SIMD4<Float>
    var distanceGameUnits: Float
}

private struct FirstPersonFocusCandidate {
    var worldCenter: SIMD3<Float>
    var worldWidth: Float
    var worldHeight: Float
    var distanceGameUnits: Float
    var alignmentScore: Float
    var color: SIMD4<Float>
}

private struct TrackedProjectileState {
    var position: SIMD2<Float>
    var velocity: SIMD2<Float>
    var ttl: Float
    var fromPlayer: Bool
    var softenedByVegetation: Bool
}

private struct SelectedItemPresentationState {
    var index: Int
    var kind: ItemKind
    var weaponClass: WeaponClass
    var roundsInMagazine: Int
    var roundChambered: Bool
}

private enum WorldTransientEffectStyle {
    case muzzleFlash
    case impactDust
    case impactStone
    case impactMetal
    case impactMud
    case impactLeaf
}

private struct WorldTransientEffect {
    var worldPosition: SIMD3<Float>
    var velocity: SIMD3<Float>
    var elapsed: Float
    var duration: Float
    var baseSize: Float
    var color: SIMD4<Float>
    var style: WorldTransientEffectStyle
}

private struct ImpactEffectDescriptor {
    var style: WorldTransientEffectStyle
    var color: SIMD4<Float>
    var baseSize: Float
    var duration: Float
    var heightOffset: Float
    var secondaryStyle: WorldTransientEffectStyle?
    var secondaryColor: SIMD4<Float>?
    var secondarySizeScale: Float = 0.72
    var secondaryDurationScale: Float = 0.8
}

private enum FirstPerson3DConfig {
    static let horizontalScale: Float = 1.0 / 90.0
    static let terrainHeightScale: Float = 0.05
    static let terrainFloor: Float = -2.6
    static let nearPlane: Float = 0.05
    static let farPlane: Float = 44.0
    static let verticalFovDegrees: Float = 68.0
}

final class GameRenderer: NSObject, MTKViewDelegate {
    weak var viewModel: GameViewModel?

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private let firstPersonPipelineState: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState
    private let overlayDepthState: MTLDepthStencilState
    private let quadVertexBuffer: MTLBuffer
    private let cubeVertexBuffer: MTLBuffer
    private let instanceBuffer: MTLBuffer
    private let worldInstanceBuffer: MTLBuffer
    private let uniformsBuffer: MTLBuffer
    private let worldUniformsBuffer: MTLBuffer
    private let inputController: InputController

    private var lastFrameTime: CFTimeInterval?
    private let maxInstances = 1400
    private let maxWorldInstances = 2400
    private let cubeVertexCount = 36
    private var previousPlayerFireCooldown: Float = 0
    private var previousEnemyFireCooldowns: [Float] = []
    private var previousProjectileStates: [TrackedProjectileState] = []
    private var transientWorldEffects: [WorldTransientEffect] = []
    private var muzzleFlashIntensity: Float = 0
    private var viewmodelKick: Float = 0
    private var viewmodelKickVelocity: Float = 0
    private var viewmodelDrift: Float = 0
    private var viewmodelDriftVelocity: Float = 0
    private var viewmodelRoll: Float = 0
    private var viewmodelRollVelocity: Float = 0
    private var viewmodelSwapTransition: Float = 0
    private var viewmodelReloadTransition: Float = 0
    private var viewmodelMeleeTransition: Float = 0
    private var recoilDirection: Float = 1.0
    private var lastSelectedItemPresentationState: SelectedItemPresentationState?

    @MainActor
    init(view: MTKView, viewModel: GameViewModel, inputController: InputController) {
        self.device = view.device!
        self.viewModel = viewModel
        self.inputController = inputController

        guard let commandQueue = self.device.makeCommandQueue() else {
            fatalError("Unable to create a Metal command queue.")
        }
        self.commandQueue = commandQueue

        let library: MTLLibrary
        do {
            library = try self.device.makeDefaultLibrary(bundle: .main)
        } catch {
            fatalError("Unable to load the default Metal library: \(error.localizedDescription)")
        }

        guard
            let vertexFunction = library.makeFunction(name: "instancedVertex"),
            let fragmentFunction = library.makeFunction(name: "instancedFragment"),
            let firstPersonVertexFunction = library.makeFunction(name: "firstPersonWorldVertex"),
            let firstPersonFragmentFunction = library.makeFunction(name: "firstPersonWorldFragment")
        else {
            fatalError("Unable to load Metal shader functions.")
        }

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.label = "MilsimGamePipeline"
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        pipelineDescriptor.depthAttachmentPixelFormat = view.depthStencilPixelFormat
        pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
        pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        let firstPersonPipelineDescriptor = MTLRenderPipelineDescriptor()
        firstPersonPipelineDescriptor.label = "MilsimGameFirstPersonPipeline"
        firstPersonPipelineDescriptor.vertexFunction = firstPersonVertexFunction
        firstPersonPipelineDescriptor.fragmentFunction = firstPersonFragmentFunction
        firstPersonPipelineDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        firstPersonPipelineDescriptor.depthAttachmentPixelFormat = view.depthStencilPixelFormat
        firstPersonPipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
        firstPersonPipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        firstPersonPipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        firstPersonPipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        firstPersonPipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        do {
            pipelineState = try self.device.makeRenderPipelineState(descriptor: pipelineDescriptor)
            firstPersonPipelineState = try self.device.makeRenderPipelineState(descriptor: firstPersonPipelineDescriptor)
        } catch {
            fatalError("Unable to create the Metal pipeline: \(error.localizedDescription)")
        }

        let quadVertices: [SIMD2<Float>] = [
            SIMD2<Float>(-0.5, -0.5),
            SIMD2<Float>(0.5, -0.5),
            SIMD2<Float>(-0.5, 0.5),
            SIMD2<Float>(0.5, -0.5),
            SIMD2<Float>(0.5, 0.5),
            SIMD2<Float>(-0.5, 0.5)
        ]
        let cubeVertices = Self.makeCubeVertices()

        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.depthCompareFunction = .less
        depthDescriptor.isDepthWriteEnabled = true

        let overlayDepthDescriptor = MTLDepthStencilDescriptor()
        overlayDepthDescriptor.depthCompareFunction = .always
        overlayDepthDescriptor.isDepthWriteEnabled = false

        guard
            let quadVertexBuffer = self.device.makeBuffer(bytes: quadVertices, length: MemoryLayout<SIMD2<Float>>.stride * quadVertices.count),
            let cubeVertexBuffer = self.device.makeBuffer(bytes: cubeVertices, length: MemoryLayout<World3DVertex>.stride * cubeVertices.count),
            let instanceBuffer = self.device.makeBuffer(length: MemoryLayout<RenderInstance>.stride * maxInstances),
            let worldInstanceBuffer = self.device.makeBuffer(length: MemoryLayout<World3DInstance>.stride * maxWorldInstances),
            let uniformsBuffer = self.device.makeBuffer(length: MemoryLayout<RenderUniforms>.stride),
            let worldUniformsBuffer = self.device.makeBuffer(length: MemoryLayout<World3DUniforms>.stride),
            let depthState = self.device.makeDepthStencilState(descriptor: depthDescriptor),
            let overlayDepthState = self.device.makeDepthStencilState(descriptor: overlayDepthDescriptor)
        else {
            fatalError("Unable to allocate Metal buffers.")
        }

        self.quadVertexBuffer = quadVertexBuffer
        self.cubeVertexBuffer = cubeVertexBuffer
        self.instanceBuffer = instanceBuffer
        self.worldInstanceBuffer = worldInstanceBuffer
        self.uniformsBuffer = uniformsBuffer
        self.worldUniformsBuffer = worldUniformsBuffer
        self.depthState = depthState
        self.overlayDepthState = overlayDepthState

        super.init()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard
            let viewModel,
            let renderPassDescriptor = view.currentRenderPassDescriptor,
            let drawable = view.currentDrawable
        else {
            return
        }

        let now = CACurrentMediaTime()
        let deltaTime: Float
        if let lastFrameTime {
            deltaTime = Float(max(1.0 / 240.0, min(now - lastFrameTime, 1.0 / 20.0)))
        } else {
            deltaTime = 1.0 / 60.0
        }
        lastFrameTime = now

        let logicalViewport = SIMD2<Float>(
            max(Float(view.bounds.width), 1),
            max(Float(view.bounds.height), 1)
        )
        let simulationViewport = logicalViewport * 1.08

        let input = inputController.makeInput(viewSize: view.bounds.size, worldViewport: simulationViewport)
        viewModel.step(input: input, dt: deltaTime)
        let firstPersonPresentation = viewModel.isFirstPersonPresentation()
        if !firstPersonPresentation {
            resetFirstPersonPresentationState()
        }
        let camera = firstPersonPresentation ? .zero : viewModel.currentPlayerPosition()
        let renderViewport = firstPersonPresentation ? SIMD2<Float>(2, 2) : simulationViewport

        var uniforms = RenderUniforms(camera: camera, worldViewport: renderViewport)
        memcpy(uniformsBuffer.contents(), &uniforms, MemoryLayout<RenderUniforms>.stride)

        let firstPersonScene = firstPersonPresentation
            ? buildFirstPersonWorldScene(viewModel: viewModel, drawableSize: view.drawableSize, dt: deltaTime)
            : nil
        let instances = firstPersonScene?.overlayInstances
            ?? buildTopDownInstances(viewModel: viewModel, camera: camera, worldViewport: renderViewport)

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }

        if let firstPersonScene {
            encodeOverlayInstances(firstPersonScene.backdropInstances, into: encoder)
            encodeFirstPersonWorld(firstPersonScene, into: encoder)
        }
        encodeOverlayInstances(instances, into: encoder)
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func resetFirstPersonPresentationState() {
        previousPlayerFireCooldown = 0
        previousEnemyFireCooldowns.removeAll(keepingCapacity: true)
        previousProjectileStates.removeAll(keepingCapacity: true)
        transientWorldEffects.removeAll(keepingCapacity: true)
        muzzleFlashIntensity = 0
        viewmodelKick = 0
        viewmodelKickVelocity = 0
        viewmodelDrift = 0
        viewmodelDriftVelocity = 0
        viewmodelRoll = 0
        viewmodelRollVelocity = 0
        viewmodelSwapTransition = 0
        viewmodelReloadTransition = 0
        viewmodelMeleeTransition = 0
        lastSelectedItemPresentationState = nil
    }

    private func encodeFirstPersonWorld(_ scene: FirstPersonWorldScene,
                                        into encoder: MTLRenderCommandEncoder) {
        let worldCount = min(scene.worldInstances.count, maxWorldInstances)
        guard worldCount > 0 else {
            return
        }

        let compactInstances = Array(scene.worldInstances.prefix(worldCount))
        compactInstances.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                return
            }
            memcpy(worldInstanceBuffer.contents(), baseAddress, rawBuffer.count)
        }

        var uniforms = scene.worldUniforms
        memcpy(worldUniformsBuffer.contents(), &uniforms, MemoryLayout<World3DUniforms>.stride)

        encoder.setRenderPipelineState(firstPersonPipelineState)
        encoder.setDepthStencilState(depthState)
        encoder.setVertexBuffer(cubeVertexBuffer, offset: 0, index: 0)
        encoder.setVertexBuffer(worldInstanceBuffer, offset: 0, index: 1)
        encoder.setVertexBuffer(worldUniformsBuffer, offset: 0, index: 2)
        encoder.setFragmentBuffer(worldUniformsBuffer, offset: 0, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: cubeVertexCount, instanceCount: worldCount)
    }

    private func encodeOverlayInstances(_ instances: [RenderInstance], into encoder: MTLRenderCommandEncoder) {
        let instanceCount = min(instances.count, maxInstances)
        guard instanceCount > 0 else {
            return
        }

        let compactInstances = Array(instances.prefix(instanceCount))
        compactInstances.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                return
            }
            memcpy(instanceBuffer.contents(), baseAddress, rawBuffer.count)
        }

        encoder.setRenderPipelineState(pipelineState)
        encoder.setDepthStencilState(overlayDepthState)
        encoder.setVertexBuffer(quadVertexBuffer, offset: 0, index: 0)
        encoder.setVertexBuffer(instanceBuffer, offset: 0, index: 1)
        encoder.setVertexBuffer(uniformsBuffer, offset: 0, index: 2)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: instanceCount)
    }

    private func buildFirstPersonWorldScene(viewModel: GameViewModel, drawableSize: CGSize, dt: Float) -> FirstPersonWorldScene {
        var camera = FirstPersonCameraRig(
            position: SIMD3<Float>(0, 1.6, 0),
            forward: SIMD3<Float>(0, 0, 1),
            right: SIMD3<Float>(1, 0, 0),
            up: SIMD3<Float>(0, 1, 0),
            horizon: -0.18,
            sway: 0,
            cameraOffset: 0
        )
        var worldUniforms = makeWorldUniforms(camera: camera, drawableSize: drawableSize)
        var worldInstances: [World3DInstance] = []
        worldInstances.reserveCapacity(720)
        var backdropInstances: [RenderInstance] = []
        backdropInstances.reserveCapacity(240)
        var overlayInstances: [RenderInstance] = []
        overlayInstances.reserveCapacity(120)

        viewModel.withState { statePointer in
            let player = statePointer.pointee.player
            let playerPosition = SIMD2<Float>(player.position.x, player.position.y)
            let aim2D = normalizedAim(for: player)

            camera = buildFirstPersonCameraRig(
                statePointer: statePointer,
                player: player,
                playerPosition: playerPosition,
                forward2D: aim2D
            )
            worldUniforms = makeWorldUniforms(camera: camera, drawableSize: drawableSize)
            updateFirstPersonPresentationState(statePointer: statePointer, dt: dt)

            addFirstPersonBackdrop(
                to: &backdropInstances,
                statePointer: statePointer,
                playerPosition: playerPosition,
                horizon: camera.horizon,
                sway: camera.sway
            )
            addFirstPersonTerrainSkylineBackdrop(
                to: &backdropInstances,
                statePointer: statePointer,
                camera: camera,
                uniforms: worldUniforms
            )

            addFirstPersonTerrainWorld(to: &worldInstances, statePointer: statePointer)
            addFirstPersonStructuresWorld(to: &worldInstances, statePointer: statePointer)
            addFirstPersonInteractablesWorld(to: &worldInstances, statePointer: statePointer)
            addFirstPersonItemsWorld(to: &worldInstances, statePointer: statePointer)
            addFirstPersonEnemiesWorld(to: &worldInstances, statePointer: statePointer, playerPosition: playerPosition)
            addFirstPersonProjectilesWorld(to: &worldInstances, statePointer: statePointer)
            addFirstPersonHorizonBackdrop(
                to: &backdropInstances,
                worldInstances: worldInstances,
                camera: camera,
                uniforms: worldUniforms
            )

            let selectedIndex = Int(game_selected_inventory_index(statePointer))
            let selectedItem = selectedIndex >= 0 ? game_inventory_item_at(statePointer, selectedIndex)?.pointee : nil
            let aimSolution = solveFirstPersonAim(
                camera: camera,
                uniforms: worldUniforms,
                worldInstances: worldInstances
            )
                ?? makeFallbackAimSolution(camera: camera, uniforms: worldUniforms)
            if let focusCue = solveFirstPersonFocusCue(
                statePointer: statePointer,
                camera: camera,
                uniforms: worldUniforms,
                playerPosition: playerPosition,
                forward2D: aim2D,
                aimScreenPosition: aimSolution.screenPosition
            ) {
                addDepthAwareFocusCue(to: &overlayInstances, cue: focusCue)
            }
            addTransientWorldEffects(to: &overlayInstances, camera: camera, uniforms: worldUniforms)

            addFirstPersonReticle(
                to: &overlayInstances,
                player: player,
                selectedItem: selectedItem,
                aimPosition: aimSolution.screenPosition
            )
            addWeaponViewModel(
                to: &overlayInstances,
                statePointer: statePointer,
                sway: camera.sway,
                aimPosition: aimSolution.screenPosition,
                horizon: camera.horizon,
                targetDepth: aimSolution.distanceGameUnits
            )
        }

        return FirstPersonWorldScene(
            camera: camera,
            worldUniforms: worldUniforms,
            backdropInstances: backdropInstances,
            worldInstances: worldInstances,
            overlayInstances: overlayInstances
        )
    }

    private func buildTopDownInstances(viewModel: GameViewModel, camera: SIMD2<Float>, worldViewport: SIMD2<Float>) -> [RenderInstance] {
        var instances: [RenderInstance] = []
        instances.reserveCapacity(900)

        addTerrainBackdrop(to: &instances, camera: camera, worldViewport: worldViewport)

        viewModel.withState { statePointer in
            let terrainTileCount = Int(game_terrain_tile_count(statePointer))
            for index in 0..<terrainTileCount {
                guard let tile = game_terrain_tile_at(statePointer, index)?.pointee else {
                    continue
                }

                let position = SIMD2<Float>(tile.position.x, tile.position.y)
                let size = SIMD2<Float>(tile.size.x - 4, tile.size.y - 4)
                let tint = min(max(tile.height / 48.0, -0.18), 0.18)
                var color = terrainColor(tile.material)
                color.x = min(max(color.x + tint, 0), 1)
                color.y = min(max(color.y + tint, 0), 1)
                color.z = min(max(color.z + tint, 0), 1)

                instances.append(makeInstance(position: position, size: size, color: color, rotation: 0, shape: .rectangle))
                if tile.conceals {
                    instances.append(
                        makeInstance(
                            position: position,
                            size: size * SIMD2<Float>(0.42, 0.42),
                            color: SIMD4<Float>(0.1, 0.2, 0.12, 0.18),
                            rotation: 0,
                            shape: .circle
                        )
                    )
                }
            }

            let structureCount = Int(game_structure_count(statePointer))
            for index in 0..<structureCount {
                guard let structure = game_structure_at(statePointer, index)?.pointee else {
                    continue
                }

                let position = SIMD2<Float>(structure.position.x, structure.position.y)
                let size = SIMD2<Float>(structure.size.x, structure.size.y)
                let rotation = structure.rotation

                switch structure.kind {
                case StructureKind_Ridge:
                    instances.append(makeInstance(position: position, size: size, color: SIMD4<Float>(0.2, 0.23, 0.16, 0.95), rotation: rotation, shape: .rectangle))
                    instances.append(makeInstance(position: position, size: size * SIMD2<Float>(0.92, 0.86), color: SIMD4<Float>(0.34, 0.28, 0.18, 0.35), rotation: rotation, shape: .rectangle))
                case StructureKind_Road:
                    instances.append(makeInstance(position: position, size: size, color: SIMD4<Float>(0.23, 0.24, 0.22, 0.92), rotation: rotation, shape: .rectangle))
                    instances.append(makeInstance(position: position, size: size * SIMD2<Float>(0.98, 0.18), color: SIMD4<Float>(0.74, 0.72, 0.48, 0.3), rotation: rotation, shape: .rectangle))
                case StructureKind_TreeCluster:
                    instances.append(makeInstance(position: position, size: size, color: SIMD4<Float>(0.14, 0.35, 0.18, 0.55), rotation: 0, shape: .circle))
                    instances.append(makeInstance(position: position + SIMD2<Float>(-28, 18), size: size * 0.42, color: SIMD4<Float>(0.12, 0.28, 0.14, 0.7), rotation: 0, shape: .circle))
                    instances.append(makeInstance(position: position + SIMD2<Float>(32, -20), size: size * 0.34, color: SIMD4<Float>(0.18, 0.4, 0.2, 0.62), rotation: 0, shape: .circle))
                case StructureKind_Building:
                    instances.append(makeInstance(position: position, size: size, color: SIMD4<Float>(0.46, 0.44, 0.39, 0.94), rotation: rotation, shape: .rectangle))
                    instances.append(makeInstance(position: position, size: size * SIMD2<Float>(0.82, 0.72), color: SIMD4<Float>(0.2, 0.22, 0.21, 0.78), rotation: rotation, shape: .rectangle))
                case StructureKind_LowWall:
                    instances.append(makeInstance(position: position, size: size, color: SIMD4<Float>(0.66, 0.63, 0.52, 0.95), rotation: rotation, shape: .rectangle))
                case StructureKind_Tower:
                    instances.append(makeInstance(position: position, size: size, color: SIMD4<Float>(0.54, 0.51, 0.4, 0.94), rotation: 0, shape: .rectangle))
                    instances.append(makeInstance(position: position, size: size * 0.58, color: SIMD4<Float>(0.2, 0.18, 0.16, 0.84), rotation: 0, shape: .rectangle))
                case StructureKind_Convoy:
                    instances.append(makeInstance(position: position, size: size, color: SIMD4<Float>(0.28, 0.31, 0.27, 0.95), rotation: 0, shape: .rectangle))
                    instances.append(makeInstance(position: position, size: size * SIMD2<Float>(0.7, 0.52), color: SIMD4<Float>(0.14, 0.15, 0.14, 0.88), rotation: 0, shape: .rectangle))
                case StructureKind_Door:
                    instances.append(makeInstance(position: position, size: size, color: SIMD4<Float>(0.78, 0.72, 0.56, 0.55), rotation: rotation, shape: .rectangle))
                default:
                    break
                }
            }

            let interactableCount = Int(game_interactable_count(statePointer))
            for index in 0..<interactableCount {
                guard let interactable = game_interactable_at(statePointer, index)?.pointee else {
                    continue
                }

                let position = SIMD2<Float>(interactable.position.x, interactable.position.y)
                let size = SIMD2<Float>(interactable.size.x, interactable.size.y)
                let color = interactableColor(kind: interactable.kind, toggled: interactable.toggled, singleUse: interactable.singleUse)

                switch interactable.kind {
                case InteractableKind_Door:
                    instances.append(makeInstance(position: position, size: size, color: color, rotation: interactable.rotation, shape: .rectangle))
                case InteractableKind_SupplyCrate:
                    instances.append(makeInstance(position: position, size: size, color: color, rotation: 0, shape: .rectangle))
                    instances.append(makeInstance(position: position, size: size * SIMD2<Float>(0.24, 0.7), color: SIMD4<Float>(0.92, 0.93, 0.95, 0.85), rotation: 0, shape: .rectangle))
                case InteractableKind_DeadDrop:
                    instances.append(makeInstance(position: position, size: size, color: color, rotation: 0, shape: .circle))
                    instances.append(makeInstance(position: position, size: size * 0.48, color: SIMD4<Float>(0.16, 0.16, 0.16, 0.44), rotation: 0, shape: .circle))
                case InteractableKind_Radio:
                    instances.append(makeInstance(position: position, size: size, color: color, rotation: 0, shape: .circle))
                    instances.append(makeInstance(position: position + SIMD2<Float>(0, 16), size: SIMD2<Float>(6, 26), color: SIMD4<Float>(0.9, 0.95, 0.92, 0.84), rotation: 0, shape: .rectangle))
                case InteractableKind_EmplacedWeapon:
                    instances.append(makeInstance(position: position, size: size, color: color, rotation: 0.08, shape: .rectangle))
                    instances.append(makeInstance(position: position + SIMD2<Float>(10, 0), size: SIMD2<Float>(size.x * 0.6, 6), color: SIMD4<Float>(0.18, 0.18, 0.18, 0.85), rotation: 0.08, shape: .rectangle))
                default:
                    break
                }
            }

            let extraction = statePointer.pointee.extractionZone
            let extractionColor = statePointer.pointee.victory
                ? SIMD4<Float>(0.42, 0.82, 0.48, 0.62)
                : (game_mission_ready_for_extract(statePointer)
                    ? SIMD4<Float>(0.98, 0.83, 0.22, 0.66)
                    : SIMD4<Float>(0.82, 0.73, 0.3, 0.36))
            instances.append(
                makeInstance(
                    position: SIMD2<Float>(extraction.x, extraction.y),
                    size: SIMD2<Float>(repeating: statePointer.pointee.extractionRadius * 2),
                    color: extractionColor,
                    rotation: 0,
                    shape: .ring
                )
            )

            let itemCount = Int(game_world_item_count(statePointer))
            for index in 0..<itemCount {
                guard let item = game_world_item_at(statePointer, index)?.pointee else {
                    continue
                }

                let position = SIMD2<Float>(item.position.x, item.position.y)
                switch item.kind {
                case ItemKind_BulletBox:
                    instances.append(makeInstance(position: position, size: SIMD2<Float>(22, 18), color: ammoColor(item.ammoType), rotation: 0, shape: .rectangle))
                case ItemKind_Magazine:
                    instances.append(makeInstance(position: position, size: SIMD2<Float>(16, 28), color: SIMD4<Float>(0.93, 0.53, 0.18, 1), rotation: 0.08, shape: .rectangle))
                case ItemKind_Gun:
                    instances.append(makeInstance(position: position, size: SIMD2<Float>(38, 14), color: SIMD4<Float>(0.36, 0.82, 0.86, 1), rotation: 0.28, shape: .rectangle))
                case ItemKind_Blade:
                    instances.append(makeInstance(position: position, size: SIMD2<Float>(14, 40), color: SIMD4<Float>(0.85, 0.86, 0.9, 1), rotation: 0.52, shape: .rectangle))
                case ItemKind_Attachment:
                    instances.append(makeInstance(position: position, size: SIMD2<Float>(24, 18), color: SIMD4<Float>(0.28, 0.82, 0.52, 1), rotation: 0.1, shape: .rectangle))
                case ItemKind_Medkit:
                    instances.append(makeInstance(position: position, size: SIMD2<Float>(24, 24), color: SIMD4<Float>(0.92, 0.24, 0.18, 1), rotation: 0, shape: .rectangle))
                case ItemKind_Objective:
                    instances.append(makeInstance(position: position, size: SIMD2<Float>(30, 30), color: SIMD4<Float>(0.92, 0.8, 0.2, 0.92), rotation: 0, shape: .ring))
                    instances.append(makeInstance(position: position, size: SIMD2<Float>(18, 18), color: SIMD4<Float>(0.96, 0.9, 0.36, 1), rotation: 0, shape: .circle))
                default:
                    break
                }
            }

            let enemyCount = Int(game_enemy_count(statePointer))
            for index in 0..<enemyCount {
                guard let enemy = game_enemy_at(statePointer, index)?.pointee else {
                    continue
                }

                let position = SIMD2<Float>(enemy.position.x, enemy.position.y)
                let healthFactor = max(0.25, enemy.health / 100)
                let flash: Float = enemy.hitTimer > 0 ? 0.24 : 0.0
                instances.append(makeInstance(position: position, size: SIMD2<Float>(34, 34), color: SIMD4<Float>(0.72 + flash, 0.18 + (0.3 * healthFactor), 0.15, 0.96), rotation: 0, shape: .circle))
                instances.append(makeInstance(position: position + SIMD2<Float>(0, -28), size: SIMD2<Float>(42 * healthFactor, 5), color: SIMD4<Float>(0.95, 0.78, 0.2, 0.8), rotation: 0, shape: .rectangle))
            }

            let projectileCount = Int(game_projectile_count(statePointer))
            for index in 0..<projectileCount {
                guard let projectile = game_projectile_at(statePointer, index)?.pointee else {
                    continue
                }

                let velocity = SIMD2<Float>(projectile.velocity.x, projectile.velocity.y)
                let rotation = atan2f(velocity.y, velocity.x)
                let color = projectile.fromPlayer
                    ? SIMD4<Float>(0.96, 0.87, 0.3, 1)
                    : SIMD4<Float>(0.95, 0.34, 0.2, 1)
                instances.append(
                    makeInstance(
                        position: SIMD2<Float>(projectile.position.x, projectile.position.y),
                        size: SIMD2<Float>(14, 3),
                        color: color,
                        rotation: rotation,
                        shape: .rectangle
                    )
                )
            }

            let player = statePointer.pointee.player
            let playerPosition = SIMD2<Float>(player.position.x, player.position.y)
            let aim = simd_normalize(SIMD2<Float>(player.aim.x, player.aim.y))
            let leanOffset = SIMD2<Float>(-aim.y, aim.x) * player.lean * 10
            let aimRotation = atan2f(aim.y, aim.x)
            let bodySize: SIMD2<Float>
            switch player.stance {
            case Stance_Crouch:
                bodySize = SIMD2<Float>(24, 24)
            case Stance_Prone:
                bodySize = SIMD2<Float>(18, 18)
            default:
                bodySize = SIMD2<Float>(30, 30)
            }
            let flash: Float = player.hitTimer > 0 ? 0.2 : 0.0
            let playerColor = statePointer.pointee.missionFailed
                ? SIMD4<Float>(0.52, 0.19, 0.18, 0.85)
                : SIMD4<Float>(0.26 + flash, 0.56 + flash * 0.2, 0.9, 0.98)

            instances.append(makeInstance(position: playerPosition, size: SIMD2<Float>(40, 40), color: SIMD4<Float>(0.11, 0.17, 0.2, 0.45), rotation: 0, shape: .ring))
            instances.append(makeInstance(position: playerPosition + leanOffset, size: bodySize, color: playerColor, rotation: 0, shape: .circle))
            instances.append(makeInstance(position: playerPosition + leanOffset + (aim * 24), size: SIMD2<Float>(34, 8), color: SIMD4<Float>(0.96, 0.87, 0.76, 0.95), rotation: aimRotation, shape: .rectangle))
            instances.append(makeInstance(position: playerPosition + (aim * 90), size: SIMD2<Float>(120, 2), color: SIMD4<Float>(0.3, 0.7, 0.96, 0.22), rotation: aimRotation, shape: .rectangle))
        }

        return instances
    }

    private func buildFirstPersonCameraRig(statePointer: UnsafePointer<GameState>,
                                           player: Player,
                                           playerPosition: SIMD2<Float>,
                                           forward2D: SIMD2<Float>) -> FirstPersonCameraRig {
        let speed = simd_length(SIMD2<Float>(player.velocity.x, player.velocity.y))
        let bobAmplitude = min(0.045, speed * 0.0009) * stanceBobMultiplier(player.stance)
        let swayPhase = statePointer.pointee.missionTime * (speed > 5 ? 10.5 : 6.0)
        let sway = sinf(swayPhase) * bobAmplitude
        let cameraOffset = player.lean * 0.09 + sway * 0.35
        let verticalBob = cosf(swayPhase * 0.55) * bobAmplitude * 0.26
        let groundElevation = terrainElevation(at: playerPosition, statePointer: statePointer)

        var forward = SIMD3<Float>(forward2D.x, cameraPitch(for: player.stance) - min(0.08, player.fireCooldown * 0.34), forward2D.y)
        forward = simd_normalize(forward)
        let worldUp = SIMD3<Float>(0, 1, 0)
        let right = simd_normalize(simd_cross(worldUp, forward))
        let up = simd_normalize(simd_cross(forward, right))

        let worldXZ = renderWorldPosition(playerPosition)
        let cameraPosition = SIMD3<Float>(worldXZ.x, groundElevation + cameraEyeHeight(for: player.stance) + verticalBob, worldXZ.y)
            + right * (cameraOffset * 0.28)
        let horizon = baseHorizon(for: player.stance) + verticalBob * 0.28

        return FirstPersonCameraRig(
            position: cameraPosition,
            forward: forward,
            right: right,
            up: up,
            horizon: horizon,
            sway: sway,
            cameraOffset: cameraOffset
        )
    }

    private func addFirstPersonTerrainWorld(to instances: inout [World3DInstance],
                                            statePointer: UnsafePointer<GameState>) {
        let terrainTileCount = Int(game_terrain_tile_count(statePointer))
        for index in 0..<terrainTileCount {
            guard let tile = game_terrain_tile_at(statePointer, index)?.pointee else {
                continue
            }

            let topY = tile.height * FirstPerson3DConfig.terrainHeightScale
            let height = max(0.12, topY - FirstPerson3DConfig.terrainFloor)
            let positionXZ = renderWorldPosition(SIMD2<Float>(tile.position.x, tile.position.y))
            var color = terrainColor(tile.material)
            let tint = min(max(tile.height / 60.0, -0.12), 0.16)
            color.x = min(max(color.x + tint, 0), 1)
            color.y = min(max(color.y + tint, 0), 1)
            color.z = min(max(color.z + tint * 0.7, 0), 1)
            color.w = 1.0
            let footprintX = max(0.08, tile.size.x * FirstPerson3DConfig.horizontalScale)
            let footprintZ = max(0.08, tile.size.y * FirstPerson3DConfig.horizontalScale)
            let variation = terrainVariationSeed(position: SIMD2<Float>(tile.position.x, tile.position.y))

            appendWorldBox(
                to: &instances,
                position: SIMD3<Float>(positionXZ.x, FirstPerson3DConfig.terrainFloor + height * 0.5, positionXZ.y),
                size: SIMD3<Float>(
                    footprintX,
                    height,
                    footprintZ
                ),
                color: color,
                lighting: tile.conceals ? 0.96 : 1.0
            )

            switch tile.material {
            case TerrainMaterial_Road:
                appendWorldBox(
                    to: &instances,
                    position: SIMD3<Float>(positionXZ.x, topY + 0.012, positionXZ.y),
                    size: SIMD3<Float>(max(0.06, footprintX * 0.18), 0.02, max(0.08, footprintZ * 0.98)),
                    color: SIMD4<Float>(0.76, 0.74, 0.54, 0.92),
                    lighting: 0.88
                )
                appendWorldBox(
                    to: &instances,
                    position: SIMD3<Float>(positionXZ.x - footprintX * 0.36, topY + 0.008, positionXZ.y),
                    size: SIMD3<Float>(max(0.04, footprintX * 0.14), 0.016, max(0.08, footprintZ * 0.94)),
                    color: SIMD4<Float>(0.14, 0.15, 0.15, 0.94),
                    lighting: 0.82
                )
                appendWorldBox(
                    to: &instances,
                    position: SIMD3<Float>(positionXZ.x + footprintX * 0.36, topY + 0.008, positionXZ.y),
                    size: SIMD3<Float>(max(0.04, footprintX * 0.14), 0.016, max(0.08, footprintZ * 0.94)),
                    color: SIMD4<Float>(0.14, 0.15, 0.15, 0.94),
                    lighting: 0.82
                )
            case TerrainMaterial_Compound:
                appendWorldBox(
                    to: &instances,
                    position: SIMD3<Float>(positionXZ.x, topY + 0.028, positionXZ.y),
                    size: SIMD3<Float>(footprintX * 0.92, 0.05, footprintZ * 0.92),
                    color: terrainAccentColor(tile.material, variation: variation, height: tile.height),
                    lighting: 0.9
                )
                appendWorldBox(
                    to: &instances,
                    position: SIMD3<Float>(positionXZ.x, topY + 0.058, positionXZ.y - footprintZ * 0.32),
                    size: SIMD3<Float>(footprintX * 0.8, 0.028, max(0.04, footprintZ * 0.08)),
                    color: SIMD4<Float>(0.62, 0.58, 0.46, 0.88),
                    lighting: 0.84
                )
            case TerrainMaterial_Rock:
                let outcropHeight = 0.18 + variation * 0.2
                appendWorldBox(
                    to: &instances,
                    position: SIMD3<Float>(positionXZ.x - footprintX * (0.14 + variation * 0.08), topY + outcropHeight * 0.5, positionXZ.y + footprintZ * 0.1),
                    size: SIMD3<Float>(max(0.12, footprintX * 0.34), outcropHeight, max(0.12, footprintZ * 0.3)),
                    color: terrainAccentColor(tile.material, variation: variation, height: tile.height),
                    lighting: 0.92
                )
                appendWorldBox(
                    to: &instances,
                    position: SIMD3<Float>(positionXZ.x + footprintX * (0.18 - variation * 0.1), topY + outcropHeight * 0.36, positionXZ.y - footprintZ * 0.16),
                    size: SIMD3<Float>(max(0.08, footprintX * 0.2), outcropHeight * 0.72, max(0.08, footprintZ * 0.18)),
                    color: SIMD4<Float>(0.34, 0.31, 0.25, 0.96),
                    lighting: 0.88
                )
            case TerrainMaterial_Mud:
                appendWorldBox(
                    to: &instances,
                    position: SIMD3<Float>(positionXZ.x, topY + 0.012, positionXZ.y),
                    size: SIMD3<Float>(footprintX * 0.78, 0.018, footprintZ * 0.74),
                    color: SIMD4<Float>(0.22, 0.14, 0.12, 0.94),
                    lighting: 0.78
                )
                appendWorldBox(
                    to: &instances,
                    position: SIMD3<Float>(positionXZ.x + footprintX * 0.16, topY + 0.038, positionXZ.y - footprintZ * 0.18),
                    size: SIMD3<Float>(footprintX * 0.28, 0.05, footprintZ * 0.24),
                    color: terrainAccentColor(tile.material, variation: variation, height: tile.height),
                    lighting: 0.84
                )
            case TerrainMaterial_Forest:
                appendWorldBox(
                    to: &instances,
                    position: SIMD3<Float>(positionXZ.x - footprintX * 0.18, topY + 0.1, positionXZ.y + footprintZ * 0.12),
                    size: SIMD3<Float>(max(0.12, footprintX * 0.24), 0.18, max(0.12, footprintZ * 0.22)),
                    color: terrainAccentColor(tile.material, variation: variation, height: tile.height),
                    lighting: 0.86
                )
                appendWorldBox(
                    to: &instances,
                    position: SIMD3<Float>(positionXZ.x + footprintX * 0.2, topY + 0.07, positionXZ.y - footprintZ * 0.16),
                    size: SIMD3<Float>(max(0.1, footprintX * 0.18), 0.12, max(0.1, footprintZ * 0.18)),
                    color: SIMD4<Float>(0.14, 0.22, 0.12, 0.98),
                    lighting: 0.8
                )
            default:
                appendWorldBox(
                    to: &instances,
                    position: SIMD3<Float>(positionXZ.x, topY + 0.014, positionXZ.y),
                    size: SIMD3<Float>(footprintX * 0.82, 0.02, footprintZ * 0.78),
                    color: terrainAccentColor(tile.material, variation: variation, height: tile.height),
                    lighting: 0.86
                )
                appendWorldBox(
                    to: &instances,
                    position: SIMD3<Float>(positionXZ.x - footprintX * 0.16, topY + 0.07, positionXZ.y + footprintZ * 0.1),
                    size: SIMD3<Float>(max(0.08, footprintX * 0.12), 0.12, max(0.08, footprintZ * 0.1)),
                    color: SIMD4<Float>(0.14, 0.24, 0.12, 0.94),
                    lighting: 0.8
                )
            }

            if tile.conceals && tile.material == TerrainMaterial_Forest {
                appendWorldBox(
                    to: &instances,
                    position: SIMD3<Float>(positionXZ.x, topY + 0.7, positionXZ.y),
                    size: SIMD3<Float>(
                        max(0.2, tile.size.x * FirstPerson3DConfig.horizontalScale * 0.84),
                        1.25,
                        max(0.2, tile.size.y * FirstPerson3DConfig.horizontalScale * 0.84)
                    ),
                    color: SIMD4<Float>(0.18, 0.33, 0.19, 0.96),
                    lighting: 0.92
                )
                appendWorldBox(
                    to: &instances,
                    position: SIMD3<Float>(positionXZ.x + footprintX * (0.12 - variation * 0.08), topY + 1.38, positionXZ.y - footprintZ * (0.1 + variation * 0.06)),
                    size: SIMD3<Float>(
                        max(0.18, footprintX * 0.5),
                        0.88,
                        max(0.18, footprintZ * 0.48)
                    ),
                    color: SIMD4<Float>(0.12, 0.28, 0.15, 0.94),
                    lighting: 0.86
                )
            }
        }
    }

    private func addFirstPersonStructuresWorld(to instances: inout [World3DInstance],
                                               statePointer: UnsafePointer<GameState>) {
        let structureCount = Int(game_structure_count(statePointer))
        for index in 0..<structureCount {
            guard let structure = game_structure_at(statePointer, index)?.pointee, structure.active else {
                continue
            }

            if structure.kind == StructureKind_Door {
                continue
            }

            let worldPosition = SIMD2<Float>(structure.position.x, structure.position.y)
            let ground = terrainElevation(at: worldPosition, statePointer: statePointer)
            let footprint = SIMD2<Float>(
                max(0.12, structure.size.x * FirstPerson3DConfig.horizontalScale),
                max(0.12, structure.size.y * FirstPerson3DConfig.horizontalScale)
            )
            let positionXZ = renderWorldPosition(worldPosition)
            let yaw = structure.rotation
            let palette = structurePalette(for: structure.kind)

            switch structure.kind {
            case StructureKind_Ridge:
                let height = max(1.1, max(footprint.x, footprint.y) * 0.82)
                appendWorldBox(
                    to: &instances,
                    position: SIMD3<Float>(positionXZ.x, ground + height * 0.5, positionXZ.y),
                    size: SIMD3<Float>(footprint.x * 1.08, height, footprint.y * 1.08),
                    color: palette.primary,
                    yaw: yaw,
                    lighting: 0.98
                )
                appendWorldBox(
                    to: &instances,
                    position: SIMD3<Float>(positionXZ.x, ground + height + 0.08, positionXZ.y),
                    size: SIMD3<Float>(footprint.x * 0.82, 0.16, footprint.y * 0.82),
                    color: palette.secondary,
                    yaw: yaw,
                    lighting: 0.92
                )
            case StructureKind_Road:
                appendWorldBox(
                    to: &instances,
                    position: SIMD3<Float>(positionXZ.x, ground + 0.018, positionXZ.y),
                    size: SIMD3<Float>(footprint.x * 1.02, 0.035, footprint.y * 1.02),
                    color: palette.primary,
                    yaw: yaw,
                    lighting: 0.92
                )
            case StructureKind_TreeCluster:
                let trunkHeight: Float = 1.45
                appendWorldBox(
                    to: &instances,
                    position: SIMD3<Float>(positionXZ.x, ground + trunkHeight * 0.5, positionXZ.y),
                    size: SIMD3<Float>(0.24, trunkHeight, 0.24),
                    color: palette.primary,
                    lighting: 0.9
                )
                appendWorldBox(
                    to: &instances,
                    position: SIMD3<Float>(positionXZ.x - footprint.x * 0.12, ground + 2.15, positionXZ.y),
                    size: SIMD3<Float>(max(1.0, footprint.x * 0.84), 1.55, max(1.0, footprint.y * 0.84)),
                    color: palette.secondary,
                    lighting: 0.9
                )
                appendWorldBox(
                    to: &instances,
                    position: SIMD3<Float>(positionXZ.x + footprint.x * 0.16, ground + 2.55, positionXZ.y + footprint.y * 0.1),
                    size: SIMD3<Float>(max(0.82, footprint.x * 0.58), 1.12, max(0.82, footprint.y * 0.58)),
                    color: palette.accent,
                    lighting: 0.88
                )
            case StructureKind_Building:
                let height = max(2.9, max(footprint.x, footprint.y) * 1.28)
                let shellSize = SIMD3<Float>(footprint.x * 0.92, height, footprint.y * 0.92)
                appendWorldBox(
                    to: &instances,
                    position: SIMD3<Float>(positionXZ.x, ground + height * 0.5, positionXZ.y),
                    size: shellSize,
                    color: palette.primary,
                    yaw: yaw
                )
                appendWorldBox(
                    to: &instances,
                    position: SIMD3<Float>(positionXZ.x, ground + height + 0.12, positionXZ.y),
                    size: SIMD3<Float>(footprint.x * 1.02, 0.18, footprint.y * 1.02),
                    color: palette.secondary,
                    yaw: yaw,
                    lighting: 0.94
                )
                appendWorldBox(
                    to: &instances,
                    position: SIMD3<Float>(positionXZ.x, ground + height * 0.52, positionXZ.y + shellSize.z * 0.46),
                    size: SIMD3<Float>(max(0.12, shellSize.x * 0.18), max(0.64, height * 0.44), 0.12),
                    color: palette.accent,
                    yaw: yaw,
                    lighting: 0.86
                )
                appendWorldBox(
                    to: &instances,
                    position: SIMD3<Float>(positionXZ.x - shellSize.x * 0.22, ground + height * 0.56, positionXZ.y + shellSize.z * 0.47),
                    size: SIMD3<Float>(max(0.18, shellSize.x * 0.16), max(0.24, height * 0.14), 0.08),
                    color: mixedColor(palette.accent, palette.secondary, amount: 0.16),
                    yaw: yaw,
                    lighting: 0.82
                )
                appendWorldBox(
                    to: &instances,
                    position: SIMD3<Float>(positionXZ.x + shellSize.x * 0.22, ground + height * 0.56, positionXZ.y + shellSize.z * 0.47),
                    size: SIMD3<Float>(max(0.18, shellSize.x * 0.16), max(0.24, height * 0.14), 0.08),
                    color: mixedColor(palette.accent, palette.secondary, amount: 0.16),
                    yaw: yaw,
                    lighting: 0.82
                )
                appendWorldBox(
                    to: &instances,
                    position: SIMD3<Float>(positionXZ.x - shellSize.x * 0.38, ground + 0.18, positionXZ.y + shellSize.z * 0.42),
                    size: SIMD3<Float>(max(0.22, shellSize.x * 0.18), 0.24, 0.22),
                    color: mixedColor(palette.primary, palette.secondary, amount: 0.18),
                    yaw: yaw
                )
                appendWorldBox(
                    to: &instances,
                    position: SIMD3<Float>(positionXZ.x + shellSize.x * 0.34, ground + height + 0.42, positionXZ.y - shellSize.z * 0.18),
                    size: SIMD3<Float>(max(0.18, shellSize.x * 0.16), 0.32, max(0.18, shellSize.z * 0.16)),
                    color: mixedColor(palette.accent, palette.secondary, amount: 0.08),
                    yaw: yaw,
                    lighting: 0.88
                )
            case StructureKind_LowWall:
                appendWorldBox(
                    to: &instances,
                    position: SIMD3<Float>(positionXZ.x, ground + 0.38, positionXZ.y),
                    size: SIMD3<Float>(footprint.x, 0.76, max(0.08, footprint.y)),
                    color: palette.primary,
                    yaw: yaw,
                    lighting: 0.98
                )
                appendWorldBox(
                    to: &instances,
                    position: SIMD3<Float>(positionXZ.x, ground + 0.78, positionXZ.y),
                    size: SIMD3<Float>(footprint.x * 0.94, 0.08, max(0.08, footprint.y * 0.82)),
                    color: palette.secondary,
                    yaw: yaw,
                    lighting: 0.92
                )
                appendWorldBox(
                    to: &instances,
                    position: SIMD3<Float>(positionXZ.x - footprint.x * 0.36, ground + 0.42, positionXZ.y),
                    size: SIMD3<Float>(0.12, 0.84, max(0.08, footprint.y * 0.78)),
                    color: palette.accent,
                    yaw: yaw,
                    lighting: 0.9
                )
                appendWorldBox(
                    to: &instances,
                    position: SIMD3<Float>(positionXZ.x + footprint.x * 0.36, ground + 0.42, positionXZ.y),
                    size: SIMD3<Float>(0.12, 0.84, max(0.08, footprint.y * 0.78)),
                    color: palette.accent,
                    yaw: yaw,
                    lighting: 0.9
                )
            case StructureKind_Tower:
                let shaftHeight: Float = max(3.4, max(footprint.x, footprint.y) * 1.6)
                let shaftWidth = max(0.28, footprint.x * 0.38)
                appendWorldBox(
                    to: &instances,
                    position: SIMD3<Float>(positionXZ.x, ground + shaftHeight * 0.5, positionXZ.y),
                    size: SIMD3<Float>(shaftWidth, shaftHeight, max(0.28, footprint.y * 0.38)),
                    color: palette.primary,
                    lighting: 0.94
                )
                appendWorldBox(
                    to: &instances,
                    position: SIMD3<Float>(positionXZ.x, ground + shaftHeight + 0.18, positionXZ.y),
                    size: SIMD3<Float>(max(0.8, footprint.x * 0.92), 0.24, max(0.8, footprint.y * 0.92)),
                    color: palette.secondary,
                    lighting: 0.9
                )
                appendWorldBox(
                    to: &instances,
                    position: SIMD3<Float>(positionXZ.x, ground + shaftHeight * 0.56, positionXZ.y),
                    size: SIMD3<Float>(max(0.86, footprint.x * 0.96), 0.12, 0.12),
                    color: palette.accent,
                    yaw: yaw + Float.pi * 0.25,
                    lighting: 0.84
                )
                for xSign in [-1.0 as Float, 1.0] {
                    for zSign in [-1.0 as Float, 1.0] {
                        appendWorldBox(
                            to: &instances,
                            position: SIMD3<Float>(positionXZ.x + xSign * footprint.x * 0.28, ground + shaftHeight * 0.46, positionXZ.y + zSign * footprint.y * 0.28),
                            size: SIMD3<Float>(0.08, shaftHeight * 0.88, 0.08),
                            color: mixedColor(palette.accent, palette.primary, amount: 0.12),
                            lighting: 0.86
                        )
                    }
                }
            case StructureKind_Convoy:
                let hullSize = SIMD3<Float>(max(0.36, footprint.x * 0.95), 1.02, max(0.22, footprint.y * 0.62))
                appendWorldBox(
                    to: &instances,
                    position: SIMD3<Float>(positionXZ.x, ground + 0.62, positionXZ.y),
                    size: hullSize,
                    color: palette.primary,
                    yaw: yaw,
                    lighting: 0.96
                )
                appendWorldBox(
                    to: &instances,
                    position: SIMD3<Float>(positionXZ.x - footprint.x * 0.14, ground + 1.12, positionXZ.y),
                    size: SIMD3<Float>(max(0.2, footprint.x * 0.36), 0.44, max(0.16, footprint.y * 0.52)),
                    color: palette.secondary,
                    yaw: yaw
                )
                appendWorldBox(
                    to: &instances,
                    position: SIMD3<Float>(positionXZ.x - hullSize.x * 0.06, ground + 1.08, positionXZ.y),
                    size: SIMD3<Float>(max(0.18, hullSize.x * 0.3), 0.12, max(0.14, hullSize.z * 0.56)),
                    color: palette.accent,
                    yaw: yaw
                )
                appendWorldBox(
                    to: &instances,
                    position: SIMD3<Float>(positionXZ.x + hullSize.x * 0.24, ground + 0.48, positionXZ.y),
                    size: SIMD3<Float>(max(0.16, hullSize.x * 0.18), 0.58, max(0.14, hullSize.z * 0.54)),
                    color: mixedColor(palette.secondary, palette.primary, amount: 0.18),
                    yaw: yaw
                )
                appendWorldBox(
                    to: &instances,
                    position: SIMD3<Float>(positionXZ.x - hullSize.x * 0.18, ground + 0.14, positionXZ.y + hullSize.z * 0.42),
                    size: SIMD3<Float>(max(0.12, hullSize.x * 0.18), 0.18, 0.12),
                    color: mixedColor(palette.secondary, SIMD4<Float>(0.08, 0.08, 0.08, 0.96), amount: 0.2),
                    yaw: yaw
                )
                appendWorldBox(
                    to: &instances,
                    position: SIMD3<Float>(positionXZ.x - hullSize.x * 0.18, ground + 0.14, positionXZ.y - hullSize.z * 0.42),
                    size: SIMD3<Float>(max(0.12, hullSize.x * 0.18), 0.18, 0.12),
                    color: mixedColor(palette.secondary, SIMD4<Float>(0.08, 0.08, 0.08, 0.96), amount: 0.2),
                    yaw: yaw
                )
                appendWorldBox(
                    to: &instances,
                    position: SIMD3<Float>(positionXZ.x + hullSize.x * 0.18, ground + 0.14, positionXZ.y + hullSize.z * 0.42),
                    size: SIMD3<Float>(max(0.12, hullSize.x * 0.18), 0.18, 0.12),
                    color: mixedColor(palette.secondary, SIMD4<Float>(0.08, 0.08, 0.08, 0.96), amount: 0.2),
                    yaw: yaw
                )
                appendWorldBox(
                    to: &instances,
                    position: SIMD3<Float>(positionXZ.x + hullSize.x * 0.18, ground + 0.14, positionXZ.y - hullSize.z * 0.42),
                    size: SIMD3<Float>(max(0.12, hullSize.x * 0.18), 0.18, 0.12),
                    color: mixedColor(palette.secondary, SIMD4<Float>(0.08, 0.08, 0.08, 0.96), amount: 0.2),
                    yaw: yaw
                )
                appendWorldBox(
                    to: &instances,
                    position: SIMD3<Float>(positionXZ.x + hullSize.x * 0.08, ground + 1.28, positionXZ.y),
                    size: SIMD3<Float>(max(0.16, hullSize.x * 0.54), 0.08, max(0.16, hullSize.z * 0.82)),
                    color: mixedColor(palette.primary, palette.secondary, amount: 0.1),
                    yaw: yaw,
                    lighting: 0.86
                )
            default:
                break
            }
        }
    }

    private func addFirstPersonInteractablesWorld(to instances: inout [World3DInstance],
                                                  statePointer: UnsafePointer<GameState>) {
        let interactableCount = Int(game_interactable_count(statePointer))
        for index in 0..<interactableCount {
            guard let interactable = game_interactable_at(statePointer, index)?.pointee, interactable.active else {
                continue
            }

            let worldPosition = SIMD2<Float>(interactable.position.x, interactable.position.y)
            let ground = terrainElevation(at: worldPosition, statePointer: statePointer)
            let positionXZ = renderWorldPosition(worldPosition)
            let width = max(0.12, interactable.size.x * FirstPerson3DConfig.horizontalScale)
            let depth = max(0.08, interactable.size.y * FirstPerson3DConfig.horizontalScale * 0.42)
            let palette = interactablePalette(kind: interactable.kind, toggled: interactable.toggled, singleUse: interactable.singleUse)

            switch interactable.kind {
            case InteractableKind_Door:
                let doorYaw = interactable.rotation + (interactable.toggled ? (Float.pi * 0.5) : 0)
                let doorWidth = interactable.toggled ? max(0.06, width * 0.14) : max(0.14, width * 0.72)
                appendWorldBox(
                    to: &instances,
                    position: SIMD3<Float>(positionXZ.x, ground + 0.9, positionXZ.y),
                    size: SIMD3<Float>(doorWidth, 1.8, max(0.06, depth)),
                    color: palette.primary,
                    yaw: doorYaw,
                    lighting: interactable.toggled ? 0.86 : 1.0
                )
            case InteractableKind_SupplyCrate:
                appendWorldBox(
                    to: &instances,
                    position: SIMD3<Float>(positionXZ.x, ground + 0.28, positionXZ.y),
                    size: SIMD3<Float>(width * 0.72, 0.56, depth * 1.4),
                    color: palette.primary
                )
                appendWorldBox(
                    to: &instances,
                    position: SIMD3<Float>(positionXZ.x, ground + 0.6, positionXZ.y),
                    size: SIMD3<Float>(width * 0.66, 0.08, depth * 1.28),
                    color: palette.secondary,
                    lighting: 0.88
                )
                appendWorldBox(
                    to: &instances,
                    position: SIMD3<Float>(positionXZ.x - width * 0.18, ground + 0.76, positionXZ.y),
                    size: SIMD3<Float>(width * 0.18, 0.12, depth * 0.34),
                    color: palette.accent,
                    lighting: 0.86
                )
                appendWorldBox(
                    to: &instances,
                    position: SIMD3<Float>(positionXZ.x, ground + 0.06, positionXZ.y),
                    size: SIMD3<Float>(width * 0.84, 0.06, depth * 1.5),
                    color: mixedColor(palette.accent, palette.primary, amount: 0.22),
                    lighting: 0.82
                )
            case InteractableKind_DeadDrop:
                appendWorldBox(
                    to: &instances,
                    position: SIMD3<Float>(positionXZ.x, ground + 0.1, positionXZ.y),
                    size: SIMD3<Float>(width * 0.6, 0.2, depth * 0.9),
                    color: palette.primary,
                    lighting: 0.9
                )
            case InteractableKind_Radio:
                appendWorldBox(
                    to: &instances,
                    position: SIMD3<Float>(positionXZ.x, ground + 0.42, positionXZ.y),
                    size: SIMD3<Float>(width * 0.4, 0.84, depth * 0.5),
                    color: palette.primary
                )
                appendWorldBox(
                    to: &instances,
                    position: SIMD3<Float>(positionXZ.x, ground + 1.06, positionXZ.y),
                    size: SIMD3<Float>(0.04, 0.46, 0.04),
                    color: palette.secondary,
                    lighting: 0.86
                )
                appendWorldBox(
                    to: &instances,
                    position: SIMD3<Float>(positionXZ.x, ground + 0.08, positionXZ.y),
                    size: SIMD3<Float>(width * 0.52, 0.08, depth * 0.84),
                    color: palette.accent,
                    lighting: 0.82
                )
                appendWorldBox(
                    to: &instances,
                    position: SIMD3<Float>(positionXZ.x - width * 0.12, ground + 0.42, positionXZ.y),
                    size: SIMD3<Float>(0.04, 0.56, 0.04),
                    color: palette.secondary,
                    lighting: 0.84
                )
                appendWorldBox(
                    to: &instances,
                    position: SIMD3<Float>(positionXZ.x + width * 0.12, ground + 0.42, positionXZ.y),
                    size: SIMD3<Float>(0.04, 0.56, 0.04),
                    color: palette.secondary,
                    lighting: 0.84
                )
            case InteractableKind_EmplacedWeapon:
                appendWorldBox(
                    to: &instances,
                    position: SIMD3<Float>(positionXZ.x, ground + 0.28, positionXZ.y),
                    size: SIMD3<Float>(width * 0.72, 0.18, depth * 0.75),
                    color: palette.primary
                )
                appendWorldBox(
                    to: &instances,
                    position: SIMD3<Float>(positionXZ.x + width * 0.22, ground + 0.42, positionXZ.y),
                    size: SIMD3<Float>(width * 0.44, 0.06, 0.42),
                    color: palette.secondary,
                    lighting: 0.9
                )
                appendWorldBox(
                    to: &instances,
                    position: SIMD3<Float>(positionXZ.x - width * 0.14, ground + 0.46, positionXZ.y),
                    size: SIMD3<Float>(width * 0.18, 0.26, depth * 0.96),
                    color: palette.accent,
                    lighting: 0.86
                )
                appendWorldBox(
                    to: &instances,
                    position: SIMD3<Float>(positionXZ.x - width * 0.08, ground + 0.18, positionXZ.y - depth * 0.28),
                    size: SIMD3<Float>(0.04, 0.36, 0.04),
                    color: palette.secondary,
                    lighting: 0.82
                )
                appendWorldBox(
                    to: &instances,
                    position: SIMD3<Float>(positionXZ.x - width * 0.08, ground + 0.18, positionXZ.y + depth * 0.28),
                    size: SIMD3<Float>(0.04, 0.36, 0.04),
                    color: palette.secondary,
                    lighting: 0.82
                )
            default:
                break
            }
        }
    }

    private func addFirstPersonItemsWorld(to instances: inout [World3DInstance],
                                          statePointer: UnsafePointer<GameState>) {
        let itemCount = Int(game_world_item_count(statePointer))
        for index in 0..<itemCount {
            guard let item = game_world_item_at(statePointer, index)?.pointee, item.active else {
                continue
            }

            let worldPosition = SIMD2<Float>(item.position.x, item.position.y)
            let ground = terrainElevation(at: worldPosition, statePointer: statePointer)
            let positionXZ = renderWorldPosition(worldPosition)
            let yaw = sinf(item.position.x * 0.014 + item.position.y * 0.01) * 0.8
            let pickupColor = fieldItemColor(item)

            switch item.kind {
            case ItemKind_BulletBox:
                appendWorldBox(to: &instances, position: SIMD3<Float>(positionXZ.x, ground + 0.08, positionXZ.y), size: SIMD3<Float>(0.2, 0.16, 0.12), color: pickupColor)
            case ItemKind_Magazine:
                appendWorldBox(to: &instances, position: SIMD3<Float>(positionXZ.x, ground + 0.14, positionXZ.y), size: SIMD3<Float>(0.08, 0.28, 0.12), color: pickupColor, yaw: yaw)
            case ItemKind_Gun:
                appendWorldBox(to: &instances, position: SIMD3<Float>(positionXZ.x, ground + 0.06, positionXZ.y), size: SIMD3<Float>(0.36, 0.08, 0.14), color: pickupColor, yaw: yaw)
            case ItemKind_Blade:
                appendWorldBox(to: &instances, position: SIMD3<Float>(positionXZ.x, ground + 0.2, positionXZ.y), size: SIMD3<Float>(0.04, 0.4, 0.08), color: pickupColor, yaw: yaw)
            case ItemKind_Attachment:
                appendWorldBox(to: &instances, position: SIMD3<Float>(positionXZ.x, ground + 0.08, positionXZ.y), size: SIMD3<Float>(0.16, 0.14, 0.12), color: pickupColor, yaw: yaw)
            case ItemKind_Medkit:
                appendWorldBox(to: &instances, position: SIMD3<Float>(positionXZ.x, ground + 0.1, positionXZ.y), size: SIMD3<Float>(0.18, 0.18, 0.18), color: pickupColor)
            case ItemKind_Objective:
                appendWorldBox(to: &instances, position: SIMD3<Float>(positionXZ.x, ground + 0.12, positionXZ.y), size: SIMD3<Float>(0.16, 0.24, 0.16), color: pickupColor)
                appendWorldBox(to: &instances, position: SIMD3<Float>(positionXZ.x, ground + 0.82, positionXZ.y), size: SIMD3<Float>(0.05, 1.05, 0.05), color: mixedColor(pickupColor, SIMD4<Float>(1.0, 0.94, 0.58, 0.94), amount: 0.42), lighting: 1.08)
            default:
                break
            }
        }
    }

    private func addFirstPersonEnemiesWorld(to instances: inout [World3DInstance],
                                            statePointer: UnsafePointer<GameState>,
                                            playerPosition: SIMD2<Float>) {
        let enemyCount = Int(game_enemy_count(statePointer))
        for index in 0..<enemyCount {
            guard let enemy = game_enemy_at(statePointer, index)?.pointee, enemy.active else {
                continue
            }

            let worldPosition = SIMD2<Float>(enemy.position.x, enemy.position.y)
            let ground = terrainElevation(at: worldPosition, statePointer: statePointer)
            let positionXZ = renderWorldPosition(worldPosition)
            let healthFactor = max(0.22, enemy.health / 100)
            let flash: Float = enemy.hitTimer > 0 ? 0.22 : 0.0
            let yaw = atan2f(playerPosition.x - enemy.position.x, playerPosition.y - enemy.position.y)
            let bodyColor = SIMD4<Float>(0.72 + flash, 0.2 + (0.28 * healthFactor), 0.15, 0.98)

            appendWorldBox(
                to: &instances,
                position: SIMD3<Float>(positionXZ.x, ground + 0.88, positionXZ.y),
                size: SIMD3<Float>(0.34, enemy.fallingBack ? 1.02 : 1.16, 0.22),
                color: bodyColor,
                yaw: yaw
            )
            appendWorldBox(
                to: &instances,
                position: SIMD3<Float>(positionXZ.x, ground + 1.62, positionXZ.y),
                size: SIMD3<Float>(0.22, 0.26, 0.22),
                color: bodyColor,
                yaw: yaw,
                lighting: 0.96
            )
            appendWorldBox(
                to: &instances,
                position: SIMD3<Float>(positionXZ.x + 0.08 * sinf(yaw), ground + 1.08, positionXZ.y + 0.08 * cosf(yaw)),
                size: SIMD3<Float>(0.08, 0.08, 0.34),
                color: SIMD4<Float>(0.16, 0.16, 0.16, 0.98),
                yaw: yaw
            )
        }
    }

    private func addFirstPersonProjectilesWorld(to instances: inout [World3DInstance],
                                                statePointer: UnsafePointer<GameState>) {
        let projectileCount = Int(game_projectile_count(statePointer))
        for index in 0..<projectileCount {
            guard let projectile = game_projectile_at(statePointer, index)?.pointee, projectile.active else {
                continue
            }

            let worldPosition = SIMD2<Float>(projectile.position.x, projectile.position.y)
            let ground = terrainElevation(at: worldPosition, statePointer: statePointer)
            let positionXZ = renderWorldPosition(worldPosition)
            let velocity = SIMD2<Float>(projectile.velocity.x, projectile.velocity.y)
            let yaw = atan2f(velocity.x, velocity.y)
            let speed = simd_length(velocity)
            let length = max(0.12, min(0.34, speed * 0.0007))
            let height: Float = projectile.fromPlayer ? 1.34 : 1.18
            let color = projectile.fromPlayer
                ? SIMD4<Float>(0.96, 0.87, 0.3, 0.98)
                : SIMD4<Float>(0.95, 0.34, 0.2, 0.98)

            appendWorldBox(
                to: &instances,
                position: SIMD3<Float>(positionXZ.x, ground + height, positionXZ.y),
                size: SIMD3<Float>(0.016, 0.016, length),
                color: color,
                yaw: yaw,
                lighting: 1.08
            )
        }
    }

    private func updateFirstPersonPresentationState(statePointer: UnsafePointer<GameState>, dt: Float) {
        muzzleFlashIntensity = max(0.0, muzzleFlashIntensity - dt * 11.5)
        viewmodelSwapTransition = max(0.0, viewmodelSwapTransition - dt * 3.1)
        viewmodelReloadTransition = max(0.0, viewmodelReloadTransition - dt * 2.0)
        viewmodelMeleeTransition = max(0.0, viewmodelMeleeTransition - dt * 2.4)
        stepViewmodelSpring(value: &viewmodelKick, velocity: &viewmodelKickVelocity, stiffness: 52.0, damping: 12.5, dt: dt)
        stepViewmodelSpring(value: &viewmodelDrift, velocity: &viewmodelDriftVelocity, stiffness: 38.0, damping: 10.0, dt: dt)
        stepViewmodelSpring(value: &viewmodelRoll, velocity: &viewmodelRollVelocity, stiffness: 34.0, damping: 9.0, dt: dt)

        for index in transientWorldEffects.indices {
            transientWorldEffects[index].elapsed += dt
            transientWorldEffects[index].worldPosition += transientWorldEffects[index].velocity * dt
            transientWorldEffects[index].velocity *= SIMD3<Float>(repeating: 0.92)
        }
        transientWorldEffects.removeAll { $0.elapsed >= $0.duration }

        let player = statePointer.pointee.player
        let previousCooldown = previousPlayerFireCooldown
        let playerShot = didWeaponFire(currentCooldown: player.fireCooldown, previousCooldown: previousCooldown)
        if playerShot {
            let recoilScale = currentSelectedRecoilScale(statePointer: statePointer)
            recoilDirection *= -1
            muzzleFlashIntensity = min(1.25, 0.62 + recoilScale * 1.15)
            viewmodelKickVelocity += 10.5 + recoilScale * 12.0
            viewmodelDriftVelocity += recoilDirection * (1.4 + recoilScale * 2.6)
            viewmodelRollVelocity += recoilDirection * (1.9 + recoilScale * 3.0)

            spawnWorldTransientEffect(
                worldPosition: playerMuzzleWorldPosition(statePointer: statePointer),
                velocity: SIMD3<Float>(repeating: 0),
                duration: currentSelectedWeaponSuppressed(statePointer: statePointer) ? 0.05 : 0.07,
                baseSize: currentSelectedWeaponSuppressed(statePointer: statePointer) ? 0.18 : 0.28,
                color: currentSelectedWeaponSuppressed(statePointer: statePointer)
                    ? SIMD4<Float>(0.9, 0.78, 0.34, 0.9)
                    : SIMD4<Float>(1.0, 0.78, 0.26, 0.98),
                style: .muzzleFlash
            )
        }

        let currentSelectedState = selectedItemPresentationState(statePointer: statePointer)
        if let currentSelectedState {
            if let lastSelectedItemPresentationState {
                if !sharesPresentationIdentity(currentSelectedState, lastSelectedItemPresentationState) {
                    viewmodelSwapTransition = 1.0
                    viewmodelReloadTransition *= 0.35
                    viewmodelMeleeTransition *= 0.25
                } else if currentSelectedState.kind == ItemKind_Gun {
                    let magazineGainedRounds = currentSelectedState.roundsInMagazine > lastSelectedItemPresentationState.roundsInMagazine
                    let chamberLoadedRound = currentSelectedState.roundChambered
                        && !lastSelectedItemPresentationState.roundChambered
                        && currentSelectedState.roundsInMagazine >= lastSelectedItemPresentationState.roundsInMagazine
                    if (magazineGainedRounds || chamberLoadedRound) && player.fireCooldown > previousCooldown + 0.16 {
                        viewmodelReloadTransition = 1.0
                        viewmodelKickVelocity += 3.4
                        viewmodelRollVelocity -= recoilDirection * 0.8
                    }
                } else if currentSelectedState.weaponClass == WeaponClass_Knife
                    && player.fireCooldown > previousCooldown + 0.18
                    && !playerShot {
                    recoilDirection *= -1
                    viewmodelMeleeTransition = 1.0
                    viewmodelKickVelocity += 4.2
                    viewmodelDriftVelocity += recoilDirection * 2.8
                    viewmodelRollVelocity += recoilDirection * 5.0
                }
            } else {
                viewmodelSwapTransition = 0.35
            }
        } else if lastSelectedItemPresentationState != nil {
            viewmodelSwapTransition = 1.0
        }

        lastSelectedItemPresentationState = currentSelectedState
        previousPlayerFireCooldown = player.fireCooldown

        let enemyCount = Int(game_enemy_count(statePointer))
        var currentEnemyCooldowns = Array(repeating: Float.zero, count: enemyCount)
        for index in 0..<enemyCount {
            guard let enemy = game_enemy_at(statePointer, index)?.pointee, enemy.active else {
                continue
            }

            currentEnemyCooldowns[index] = enemy.fireCooldown
            let previousCooldown = index < previousEnemyFireCooldowns.count ? previousEnemyFireCooldowns[index] : 0
            if didWeaponFire(currentCooldown: enemy.fireCooldown, previousCooldown: previousCooldown) {
                spawnWorldTransientEffect(
                    worldPosition: enemyMuzzleWorldPosition(enemy: enemy, statePointer: statePointer),
                    velocity: SIMD3<Float>(repeating: 0),
                    duration: 0.055,
                    baseSize: 0.2,
                    color: SIMD4<Float>(0.98, 0.72, 0.22, 0.92),
                    style: .muzzleFlash
                )
            }
        }
        previousEnemyFireCooldowns = currentEnemyCooldowns

        let currentProjectileStates = collectActiveProjectileStates(statePointer: statePointer)
        registerProjectileImpactEffects(
            previousStates: previousProjectileStates,
            currentStates: currentProjectileStates,
            statePointer: statePointer,
            dt: dt
        )
        previousProjectileStates = currentProjectileStates
    }

    private func didWeaponFire(currentCooldown: Float, previousCooldown: Float) -> Bool {
        currentCooldown > 0.04 && currentCooldown > previousCooldown + 0.02
    }

    private func collectActiveProjectileStates(statePointer: UnsafePointer<GameState>) -> [TrackedProjectileState] {
        let projectileCount = Int(game_projectile_count(statePointer))
        var projectiles: [TrackedProjectileState] = []
        projectiles.reserveCapacity(projectileCount)

        for index in 0..<projectileCount {
            guard let projectile = game_projectile_at(statePointer, index)?.pointee, projectile.active else {
                continue
            }

            projectiles.append(
                TrackedProjectileState(
                    position: SIMD2<Float>(projectile.position.x, projectile.position.y),
                    velocity: SIMD2<Float>(projectile.velocity.x, projectile.velocity.y),
                    ttl: projectile.ttl,
                    fromPlayer: projectile.fromPlayer,
                    softenedByVegetation: projectile.softenedByVegetation
                )
            )
        }

        return projectiles
    }

    private func registerProjectileImpactEffects(previousStates: [TrackedProjectileState],
                                                 currentStates: [TrackedProjectileState],
                                                 statePointer: UnsafePointer<GameState>,
                                                 dt: Float) {
        var matchedCurrent = Array(repeating: false, count: currentStates.count)

        for previousState in previousStates {
            var bestIndex: Int?
            var bestDistance = Float.greatestFiniteMagnitude
            let speed = simd_length(previousState.velocity)
            let threshold = max(22.0, speed * max(dt, 1.0 / 90.0) * 2.6 + 10.0)

            for (index, currentState) in currentStates.enumerated() {
                guard !matchedCurrent[index], currentState.fromPlayer == previousState.fromPlayer else {
                    continue
                }

                let distance = simd_length(currentState.position - previousState.position)
                if distance > threshold || distance >= bestDistance {
                    continue
                }

                bestDistance = distance
                bestIndex = index
            }

            if let bestIndex {
                matchedCurrent[bestIndex] = true
                continue
            }

            let velocityDirection = simd_length_squared(previousState.velocity) > 0.0001
                ? simd_normalize(previousState.velocity)
                : SIMD2<Float>(0, 1)
            let impactPosition = previousState.position + velocityDirection * min(24.0, max(8.0, speed * 0.02))
            let descriptor = impactDescriptor(
                at: impactPosition,
                softenedByVegetation: previousState.softenedByVegetation,
                statePointer: statePointer
            )
            let height = terrainElevation(at: impactPosition, statePointer: statePointer) + descriptor.heightOffset
            let renderPosition = renderWorldPosition(impactPosition)
            let upwardVelocity: Float
            switch descriptor.style {
            case .impactMetal:
                upwardVelocity = 0.04
            case .impactStone:
                upwardVelocity = 0.08
            case .impactMud:
                upwardVelocity = 0.14
            case .impactLeaf:
                upwardVelocity = 0.16
            default:
                upwardVelocity = 0.12
            }

            spawnWorldTransientEffect(
                worldPosition: SIMD3<Float>(renderPosition.x, height, renderPosition.y),
                velocity: SIMD3<Float>(0, upwardVelocity, 0),
                duration: descriptor.duration,
                baseSize: descriptor.baseSize,
                color: descriptor.color,
                style: descriptor.style
            )

            if let secondaryStyle = descriptor.secondaryStyle,
               let secondaryColor = descriptor.secondaryColor {
                spawnWorldTransientEffect(
                    worldPosition: SIMD3<Float>(renderPosition.x, height + 0.04, renderPosition.y),
                    velocity: SIMD3<Float>(0, max(0.03, upwardVelocity * 0.72), 0),
                    duration: descriptor.duration * descriptor.secondaryDurationScale,
                    baseSize: descriptor.baseSize * descriptor.secondarySizeScale,
                    color: secondaryColor,
                    style: secondaryStyle
                )
            }
        }
    }

    private func spawnWorldTransientEffect(worldPosition: SIMD3<Float>,
                                           velocity: SIMD3<Float>,
                                           duration: Float,
                                           baseSize: Float,
                                           color: SIMD4<Float>,
                                           style: WorldTransientEffectStyle) {
        transientWorldEffects.append(
            WorldTransientEffect(
                worldPosition: worldPosition,
                velocity: velocity,
                elapsed: 0,
                duration: duration,
                baseSize: baseSize,
                color: color,
                style: style
            )
        )
        if transientWorldEffects.count > 48 {
            transientWorldEffects.removeFirst(transientWorldEffects.count - 48)
        }
    }

    private func currentSelectedRecoilScale(statePointer: UnsafePointer<GameState>) -> Float {
        let selectedIndex = Int(game_selected_inventory_index(statePointer))
        guard selectedIndex >= 0, let selectedItem = game_inventory_item_at(statePointer, selectedIndex)?.pointee else {
            return 0.18
        }

        if selectedItem.kind != ItemKind_Gun {
            return selectedItem.weaponClass == WeaponClass_Knife ? 0.12 : 0.08
        }
        return min(max(selectedItem.recoil / 26.0, 0.18), 0.88)
    }

    private func currentSelectedWeaponSuppressed(statePointer: UnsafePointer<GameState>) -> Bool {
        let selectedIndex = Int(game_selected_inventory_index(statePointer))
        guard selectedIndex >= 0, let selectedItem = game_inventory_item_at(statePointer, selectedIndex)?.pointee else {
            return false
        }
        return selectedItem.kind == ItemKind_Gun && selectedItem.suppressed
    }

    private func selectedItemPresentationState(statePointer: UnsafePointer<GameState>) -> SelectedItemPresentationState? {
        let selectedIndex = Int(game_selected_inventory_index(statePointer))
        guard selectedIndex >= 0, let selectedItem = game_inventory_item_at(statePointer, selectedIndex)?.pointee else {
            return nil
        }

        return SelectedItemPresentationState(
            index: selectedIndex,
            kind: selectedItem.kind,
            weaponClass: selectedItem.weaponClass,
            roundsInMagazine: Int(selectedItem.roundsInMagazine),
            roundChambered: selectedItem.roundChambered
        )
    }

    private func sharesPresentationIdentity(_ lhs: SelectedItemPresentationState,
                                            _ rhs: SelectedItemPresentationState) -> Bool {
        lhs.index == rhs.index && lhs.kind == rhs.kind && lhs.weaponClass == rhs.weaponClass
    }

    private func stepViewmodelSpring(value: inout Float,
                                     velocity: inout Float,
                                     stiffness: Float,
                                     damping: Float,
                                     dt: Float) {
        velocity += (-value * stiffness - velocity * damping) * dt
        value += velocity * dt

        if abs(value) < 0.0006 && abs(velocity) < 0.0006 {
            value = 0
            velocity = 0
        }
    }

    private func playerMuzzleWorldPosition(statePointer: UnsafePointer<GameState>) -> SIMD3<Float> {
        let player = statePointer.pointee.player
        let playerPosition = SIMD2<Float>(player.position.x, player.position.y)
        let forward = normalizedAim(for: player)
        let muzzlePosition = playerPosition + forward * 30.0
        let ground = terrainElevation(at: playerPosition, statePointer: statePointer)
        let renderPosition = renderWorldPosition(muzzlePosition)

        return SIMD3<Float>(
            renderPosition.x,
            ground + cameraEyeHeight(for: player.stance) - 0.18,
            renderPosition.y
        )
    }

    private func enemyMuzzleWorldPosition(enemy: Enemy,
                                          statePointer: UnsafePointer<GameState>) -> SIMD3<Float> {
        let playerPosition = statePointer.pointee.player.position
        let toPlayer = SIMD2<Float>(playerPosition.x - enemy.position.x, playerPosition.y - enemy.position.y)
        let forward = simd_length_squared(toPlayer) > 0.0001 ? simd_normalize(toPlayer) : SIMD2<Float>(0, 1)
        let muzzlePosition = SIMD2<Float>(enemy.position.x, enemy.position.y) + forward * 20.0
        let ground = terrainElevation(at: SIMD2<Float>(enemy.position.x, enemy.position.y), statePointer: statePointer)
        let renderPosition = renderWorldPosition(muzzlePosition)

        return SIMD3<Float>(renderPosition.x, ground + 1.14, renderPosition.y)
    }

    private func addTransientWorldEffects(to instances: inout [RenderInstance],
                                          camera: FirstPersonCameraRig,
                                          uniforms: World3DUniforms) {
        for effect in transientWorldEffects {
            guard let center = projectWorldPointToOverlay(effect.worldPosition, uniforms: uniforms),
                  let projectedSize = projectedOverlaySize(
                    worldCenter: effect.worldPosition,
                    worldWidth: effect.baseSize,
                    worldHeight: effect.baseSize,
                    camera: camera,
                    uniforms: uniforms
                  ) else {
                continue
            }

            let progress = min(max(effect.elapsed / max(effect.duration, 0.001), 0.0), 1.0)
            let fade = 1.0 - progress
            let size = SIMD2<Float>(
                max(0.015, projectedSize.x * (1.0 + progress * 0.8)),
                max(0.015, projectedSize.y * (1.0 + progress * 0.8))
            )
            let alpha = effect.color.w * fade
            let color = SIMD4<Float>(effect.color.x, effect.color.y, effect.color.z, alpha)

            switch effect.style {
            case .muzzleFlash:
                instances.append(makeInstance(position: center, size: size * SIMD2<Float>(1.18, 0.78), color: color, rotation: 0, shape: .circle))
                instances.append(makeInstance(position: center, size: size * SIMD2<Float>(1.9, 0.2), color: SIMD4<Float>(effect.color.x, effect.color.y, effect.color.z, alpha * 0.58), rotation: 0, shape: .rectangle))
                instances.append(makeInstance(position: center, size: size * SIMD2<Float>(0.42, 0.42), color: SIMD4<Float>(1.0, 0.92, 0.78, alpha * 0.85), rotation: 0, shape: .circle))
            case .impactDust:
                instances.append(makeInstance(position: center, size: size * SIMD2<Float>(1.3, 1.3), color: SIMD4<Float>(effect.color.x, effect.color.y, effect.color.z, alpha * 0.52), rotation: 0, shape: .circle))
                instances.append(makeInstance(position: center, size: size * SIMD2<Float>(1.7, 1.7), color: SIMD4<Float>(effect.color.x, effect.color.y, effect.color.z, alpha * 0.4), rotation: 0, shape: .ring))
            case .impactStone:
                instances.append(makeInstance(position: center, size: size * SIMD2<Float>(1.18, 1.0), color: SIMD4<Float>(effect.color.x, effect.color.y, effect.color.z, alpha * 0.48), rotation: 0.1, shape: .circle))
                instances.append(makeInstance(position: center, size: size * SIMD2<Float>(1.42, 1.28), color: SIMD4<Float>(effect.color.x, effect.color.y, effect.color.z, alpha * 0.3), rotation: 0, shape: .ring))
                instances.append(makeInstance(position: center + SIMD2<Float>(size.x * 0.12, -size.y * 0.04), size: size * SIMD2<Float>(0.64, 0.12), color: SIMD4<Float>(0.92, 0.9, 0.82, alpha * 0.62), rotation: -0.26, shape: .rectangle))
            case .impactMetal:
                instances.append(makeInstance(position: center, size: size * SIMD2<Float>(1.2, 0.16), color: color, rotation: 0.2, shape: .rectangle))
                instances.append(makeInstance(position: center, size: size * SIMD2<Float>(1.0, 0.14), color: SIMD4<Float>(1.0, 0.92, 0.78, alpha * 0.85), rotation: -0.24, shape: .rectangle))
                instances.append(makeInstance(position: center, size: size * SIMD2<Float>(0.42, 0.42), color: SIMD4<Float>(1.0, 0.96, 0.82, alpha * 0.72), rotation: 0, shape: .circle))
            case .impactMud:
                instances.append(makeInstance(position: center, size: size * SIMD2<Float>(1.18, 0.92), color: SIMD4<Float>(effect.color.x, effect.color.y, effect.color.z, alpha * 0.56), rotation: 0.08, shape: .circle))
                instances.append(makeInstance(position: center + SIMD2<Float>(0, size.y * 0.08), size: size * SIMD2<Float>(1.56, 0.32), color: SIMD4<Float>(effect.color.x * 0.82, effect.color.y * 0.74, effect.color.z * 0.72, alpha * 0.42), rotation: 0, shape: .rectangle))
                instances.append(makeInstance(position: center, size: size * SIMD2<Float>(1.5, 1.1), color: SIMD4<Float>(effect.color.x, effect.color.y, effect.color.z, alpha * 0.26), rotation: 0, shape: .ring))
            case .impactLeaf:
                instances.append(makeInstance(position: center + SIMD2<Float>(-size.x * 0.12, -size.y * 0.06), size: size * SIMD2<Float>(1.1, 0.92), color: SIMD4<Float>(effect.color.x, effect.color.y, effect.color.z, alpha * 0.48), rotation: 0.12, shape: .circle))
                instances.append(makeInstance(position: center + SIMD2<Float>(size.x * 0.14, size.y * 0.04), size: size * SIMD2<Float>(0.84, 0.72), color: SIMD4<Float>(effect.color.x * 0.92, effect.color.y * 1.02, effect.color.z * 0.9, alpha * 0.42), rotation: -0.16, shape: .circle))
            }
        }
    }

    private func impactDescriptor(at position: SIMD2<Float>,
                                  softenedByVegetation: Bool,
                                  statePointer: UnsafePointer<GameState>) -> ImpactEffectDescriptor {
        if softenedByVegetation {
            return ImpactEffectDescriptor(
                style: .impactLeaf,
                color: SIMD4<Float>(0.38, 0.68, 0.34, 0.7),
                baseSize: 0.34,
                duration: 0.22,
                heightOffset: 0.46
            )
        }

        let structureCount = Int(game_structure_count(statePointer))
        for index in 0..<structureCount {
            guard let structure = game_structure_at(statePointer, index)?.pointee, structure.active else {
                continue
            }

            let halfWidth = structure.size.x * 0.5 + 18.0
            let halfHeight = structure.size.y * 0.5 + 18.0
            guard abs(position.x - structure.position.x) <= halfWidth,
                  abs(position.y - structure.position.y) <= halfHeight else {
                continue
            }

            switch structure.kind {
            case StructureKind_Building, StructureKind_Tower, StructureKind_Door:
                return ImpactEffectDescriptor(
                    style: .impactStone,
                    color: SIMD4<Float>(0.76, 0.72, 0.68, 0.74),
                    baseSize: 0.28,
                    duration: 0.2,
                    heightOffset: 0.32,
                    secondaryStyle: .impactMetal,
                    secondaryColor: SIMD4<Float>(0.98, 0.84, 0.48, 0.82)
                )
            case StructureKind_Convoy:
                return ImpactEffectDescriptor(
                    style: .impactMetal,
                    color: SIMD4<Float>(1.0, 0.74, 0.28, 0.9),
                    baseSize: 0.28,
                    duration: 0.18,
                    heightOffset: 0.5,
                    secondaryStyle: .impactDust,
                    secondaryColor: SIMD4<Float>(0.38, 0.34, 0.3, 0.46),
                    secondarySizeScale: 0.62,
                    secondaryDurationScale: 1.1
                )
            case StructureKind_LowWall, StructureKind_Road:
                return ImpactEffectDescriptor(
                    style: .impactStone,
                    color: SIMD4<Float>(0.72, 0.68, 0.58, 0.68),
                    baseSize: 0.32,
                    duration: 0.24,
                    heightOffset: 0.16,
                    secondaryStyle: .impactDust,
                    secondaryColor: SIMD4<Float>(0.62, 0.58, 0.5, 0.44)
                )
            case StructureKind_TreeCluster:
                return ImpactEffectDescriptor(
                    style: .impactLeaf,
                    color: SIMD4<Float>(0.36, 0.66, 0.32, 0.72),
                    baseSize: 0.34,
                    duration: 0.22,
                    heightOffset: 0.56
                )
            case StructureKind_Ridge:
                return ImpactEffectDescriptor(
                    style: .impactStone,
                    color: SIMD4<Float>(0.58, 0.46, 0.3, 0.7),
                    baseSize: 0.38,
                    duration: 0.28,
                    heightOffset: 0.24,
                    secondaryStyle: .impactDust,
                    secondaryColor: SIMD4<Float>(0.46, 0.34, 0.24, 0.46)
                )
            default:
                break
            }
        }

        if let material = terrainMaterial(at: position, statePointer: statePointer) {
            switch material {
            case TerrainMaterial_Road, TerrainMaterial_Compound:
                return ImpactEffectDescriptor(
                    style: .impactStone,
                    color: SIMD4<Float>(0.72, 0.68, 0.58, 0.68),
                    baseSize: 0.3,
                    duration: 0.24,
                    heightOffset: 0.12,
                    secondaryStyle: .impactDust,
                    secondaryColor: SIMD4<Float>(0.62, 0.59, 0.52, 0.42)
                )
            case TerrainMaterial_Rock:
                return ImpactEffectDescriptor(
                    style: .impactStone,
                    color: SIMD4<Float>(0.78, 0.74, 0.68, 0.72),
                    baseSize: 0.24,
                    duration: 0.18,
                    heightOffset: 0.18,
                    secondaryStyle: .impactMetal,
                    secondaryColor: SIMD4<Float>(0.94, 0.84, 0.52, 0.74),
                    secondarySizeScale: 0.52,
                    secondaryDurationScale: 0.72
                )
            case TerrainMaterial_Forest:
                return ImpactEffectDescriptor(
                    style: .impactLeaf,
                    color: SIMD4<Float>(0.34, 0.64, 0.3, 0.72),
                    baseSize: 0.34,
                    duration: 0.24,
                    heightOffset: 0.34
                )
            case TerrainMaterial_Mud:
                return ImpactEffectDescriptor(
                    style: .impactMud,
                    color: SIMD4<Float>(0.6, 0.38, 0.26, 0.74),
                    baseSize: 0.36,
                    duration: 0.28,
                    heightOffset: 0.16,
                    secondaryStyle: .impactDust,
                    secondaryColor: SIMD4<Float>(0.46, 0.32, 0.24, 0.44),
                    secondarySizeScale: 0.88,
                    secondaryDurationScale: 0.92
                )
            default:
                return ImpactEffectDescriptor(
                    style: .impactDust,
                    color: SIMD4<Float>(0.54, 0.62, 0.42, 0.64),
                    baseSize: 0.34,
                    duration: 0.28,
                    heightOffset: 0.14
                )
            }
        }

        return ImpactEffectDescriptor(
            style: .impactDust,
            color: SIMD4<Float>(0.54, 0.62, 0.42, 0.64),
            baseSize: 0.34,
            duration: 0.28,
            heightOffset: 0.14
        )
    }

    private func terrainMaterial(at worldPosition: SIMD2<Float>,
                                 statePointer: UnsafePointer<GameState>) -> TerrainMaterial? {
        let terrainTileCount = Int(game_terrain_tile_count(statePointer))
        for index in 0..<terrainTileCount {
            guard let tile = game_terrain_tile_at(statePointer, index)?.pointee, tile.active else {
                continue
            }

            let halfWidth = tile.size.x * 0.5
            let halfHeight = tile.size.y * 0.5
            if abs(worldPosition.x - tile.position.x) <= halfWidth && abs(worldPosition.y - tile.position.y) <= halfHeight {
                return tile.material
            }
        }

        return nil
    }

    private func addFirstPersonTerrainSkylineBackdrop(to instances: inout [RenderInstance],
                                                      statePointer: UnsafePointer<GameState>,
                                                      camera: FirstPersonCameraRig,
                                                      uniforms: World3DUniforms) {
        let terrainTileCount = Int(game_terrain_tile_count(statePointer))
        var silhouettes: [(depth: Float, instance: RenderInstance)] = []
        silhouettes.reserveCapacity(84)

        for index in 0..<terrainTileCount {
            guard let tile = game_terrain_tile_at(statePointer, index)?.pointee else {
                continue
            }

            let topY = tile.height * FirstPerson3DConfig.terrainHeightScale
            let positionXZ = renderWorldPosition(SIMD2<Float>(tile.position.x, tile.position.y))
            let distance = simd_distance(SIMD3<Float>(positionXZ.x, topY, positionXZ.y), camera.position)
            guard distance > 9.0, distance < 40.0 else {
                continue
            }

            let skylineHeight = topY + (tile.material == TerrainMaterial_Forest ? 1.2 : (tile.material == TerrainMaterial_Rock ? 0.62 : 0.22))
            let worldCenter = SIMD3<Float>(positionXZ.x, skylineHeight, positionXZ.y)
            guard let center = projectWorldPointToOverlay(worldCenter, uniforms: uniforms),
                  let size = projectedOverlaySize(
                    worldCenter: worldCenter,
                    worldWidth: max(0.08, tile.size.x * FirstPerson3DConfig.horizontalScale),
                    worldHeight: max(0.18, skylineHeight - FirstPerson3DConfig.terrainFloor),
                    camera: camera,
                    uniforms: uniforms
                  ) else {
                continue
            }
            guard abs(center.x) <= 1.3, size.x > 0.025 else {
                continue
            }

            let color = terrainSkylineColor(tile.material, distance: distance, height: tile.height)
            silhouettes.append(
                (
                    depth: distance,
                    instance: makeInstance(
                        position: SIMD2<Float>(center.x, min(camera.horizon + 0.44, center.y)),
                        size: SIMD2<Float>(size.x * (tile.material == TerrainMaterial_Forest ? 1.08 : 1.02), max(0.03, size.y * (tile.material == TerrainMaterial_Forest ? 0.9 : 0.82))),
                        color: color,
                        rotation: 0,
                        shape: tile.material == TerrainMaterial_Forest ? .circle : .rectangle
                    )
                )
            )
        }

        silhouettes.sort { $0.depth > $1.depth }
        for silhouette in silhouettes.prefix(90) {
            instances.append(silhouette.instance)
        }
    }

    private func addFirstPersonHorizonBackdrop(to instances: inout [RenderInstance],
                                               worldInstances: [World3DInstance],
                                               camera: FirstPersonCameraRig,
                                               uniforms: World3DUniforms) {
        var silhouettes: [(depth: Float, instance: RenderInstance)] = []
        silhouettes.reserveCapacity(72)

        for worldInstance in worldInstances {
            let distance = simd_distance(worldInstance.position, camera.position)
            guard distance > 8.0, distance < 34.0 else {
                continue
            }
            guard worldInstance.size.y > 0.42 || worldInstance.position.y > 1.0 else {
                continue
            }
            guard let center = projectWorldPointToOverlay(worldInstance.position, uniforms: uniforms),
                  let size = projectedOverlaySize(
                    worldCenter: worldInstance.position,
                    worldWidth: max(worldInstance.size.x, worldInstance.size.z),
                    worldHeight: worldInstance.size.y,
                    camera: camera,
                    uniforms: uniforms
                  ) else {
                continue
            }
            guard size.x > 0.03, size.y > 0.03 else {
                continue
            }
            guard abs(center.x) <= 1.28 else {
                continue
            }

            let fade = 1.0 - min(max((distance - 8.0) / 26.0, 0.0), 1.0)
            let alpha = max(0.05, 0.16 * fade)
            let position = SIMD2<Float>(center.x, min(camera.horizon + 0.38, center.y))
            let silhouetteColor = mixedColor(
                SIMD4<Float>(worldInstance.color.x * 0.28, worldInstance.color.y * 0.3, worldInstance.color.z * 0.28, alpha),
                SIMD4<Float>(0.28, 0.31, 0.28, alpha),
                amount: 0.34
            )
            silhouettes.append(
                (
                    depth: distance,
                    instance: makeInstance(
                        position: position,
                        size: SIMD2<Float>(size.x * 1.08, max(0.03, size.y * 0.88)),
                        color: silhouetteColor,
                        rotation: 0,
                        shape: .rectangle
                    )
                )
            )
        }

        silhouettes.sort { $0.depth > $1.depth }
        for silhouette in silhouettes.prefix(80) {
            instances.append(silhouette.instance)
        }
    }

    private func solveFirstPersonAim(camera: FirstPersonCameraRig,
                                     uniforms: World3DUniforms,
                                     worldInstances: [World3DInstance]) -> FirstPersonAimSolution? {
        let origin = camera.position
        let direction = simd_normalize(camera.forward)
        var nearestDistance = FirstPerson3DConfig.farPlane * 0.92

        for worldInstance in worldInstances {
            guard let hitDistance = intersectRayWithWorldBox(origin: origin, direction: direction, instance: worldInstance) else {
                continue
            }
            guard hitDistance > FirstPerson3DConfig.nearPlane, hitDistance < nearestDistance else {
                continue
            }
            nearestDistance = hitDistance
        }

        let worldPoint = origin + direction * nearestDistance
        guard let screenPosition = projectWorldPointToOverlay(worldPoint, uniforms: uniforms) else {
            return nil
        }

        return FirstPersonAimSolution(
            screenPosition: screenPosition,
            worldPoint: worldPoint,
            distanceGameUnits: nearestDistance / FirstPerson3DConfig.horizontalScale,
            distanceWorldUnits: nearestDistance
        )
    }

    private func makeFallbackAimSolution(camera: FirstPersonCameraRig,
                                         uniforms: World3DUniforms) -> FirstPersonAimSolution {
        let distanceWorldUnits = FirstPerson3DConfig.farPlane * 0.7
        let worldPoint = camera.position + simd_normalize(camera.forward) * distanceWorldUnits
        return FirstPersonAimSolution(
            screenPosition: projectWorldPointToOverlay(worldPoint, uniforms: uniforms) ?? .zero,
            worldPoint: worldPoint,
            distanceGameUnits: distanceWorldUnits / FirstPerson3DConfig.horizontalScale,
            distanceWorldUnits: distanceWorldUnits
        )
    }

    private func solveFirstPersonFocusCue(statePointer: UnsafePointer<GameState>,
                                          camera: FirstPersonCameraRig,
                                          uniforms: World3DUniforms,
                                          playerPosition: SIMD2<Float>,
                                          forward2D: SIMD2<Float>,
                                          aimScreenPosition: SIMD2<Float>) -> FirstPersonFocusCue? {
        let right2D = SIMD2<Float>(forward2D.y, -forward2D.x)
        var bestScore = Float.greatestFiniteMagnitude
        var bestCue: FirstPersonFocusCue?

        func consider(candidate: FirstPersonFocusCandidate) {
            guard let screenPosition = projectWorldPointToOverlay(candidate.worldCenter, uniforms: uniforms),
                  let projectedSize = projectedOverlaySize(
                    worldCenter: candidate.worldCenter,
                    worldWidth: candidate.worldWidth,
                    worldHeight: candidate.worldHeight,
                    camera: camera,
                    uniforms: uniforms
                  ) else {
                return
            }
            guard projectedSize.x > 0.02, projectedSize.y > 0.02 else {
                return
            }
            guard abs(screenPosition.x) <= 1.1, abs(screenPosition.y) <= 0.96 else {
                return
            }

            let screenError = simd_length(screenPosition - aimScreenPosition)
            let score = candidate.distanceGameUnits
                + screenError * 180.0
                + max(0.0, 0.62 - candidate.alignmentScore) * 120.0
            if score >= bestScore {
                return
            }

            bestScore = score
            bestCue = FirstPersonFocusCue(
                screenPosition: screenPosition,
                size: SIMD2<Float>(
                    min(0.44, max(0.08, projectedSize.x * 1.18)),
                    min(0.44, max(0.08, projectedSize.y * 1.14))
                ),
                color: candidate.color,
                distanceGameUnits: candidate.distanceGameUnits
            )
        }

        let interactableCount = Int(game_interactable_count(statePointer))
        for index in 0..<interactableCount {
            guard let interactable = game_interactable_at(statePointer, index)?.pointee, interactable.active else {
                continue
            }

            let position = SIMD2<Float>(interactable.position.x, interactable.position.y)
            let offset = position - playerPosition
            let distance = simd_length(offset)
            guard distance > 3.0, distance <= 170.0 else {
                continue
            }

            let alignment = simd_dot(simd_normalize(offset), forward2D)
            let lateral = abs(simd_dot(offset, right2D))
            guard alignment > 0.1, lateral <= max(48.0, distance * 0.72) else {
                continue
            }

            let ground = terrainElevation(at: position, statePointer: statePointer)
            let worldPosition = renderWorldPosition(position)
            let baseColor = interactableColor(kind: interactable.kind, toggled: interactable.toggled, singleUse: interactable.singleUse)
            let width = max(0.12, interactable.size.x * FirstPerson3DConfig.horizontalScale)
            let depth = max(0.08, interactable.size.y * FirstPerson3DConfig.horizontalScale * 0.42)

            switch interactable.kind {
            case InteractableKind_Door:
                let doorWidth = interactable.toggled ? max(0.06, width * 0.14) : max(0.14, width * 0.72)
                consider(
                    candidate: FirstPersonFocusCandidate(
                        worldCenter: SIMD3<Float>(worldPosition.x, ground + 0.9, worldPosition.y),
                        worldWidth: doorWidth,
                        worldHeight: 1.8,
                        distanceGameUnits: distance,
                        alignmentScore: alignment,
                        color: baseColor
                    )
                )
            case InteractableKind_SupplyCrate:
                consider(
                    candidate: FirstPersonFocusCandidate(
                        worldCenter: SIMD3<Float>(worldPosition.x, ground + 0.32, worldPosition.y),
                        worldWidth: width * 0.72,
                        worldHeight: 0.6,
                        distanceGameUnits: distance,
                        alignmentScore: alignment,
                        color: baseColor
                    )
                )
            case InteractableKind_DeadDrop:
                consider(
                    candidate: FirstPersonFocusCandidate(
                        worldCenter: SIMD3<Float>(worldPosition.x, ground + 0.12, worldPosition.y),
                        worldWidth: width * 0.6,
                        worldHeight: 0.24,
                        distanceGameUnits: distance,
                        alignmentScore: alignment,
                        color: baseColor
                    )
                )
            case InteractableKind_Radio:
                consider(
                    candidate: FirstPersonFocusCandidate(
                        worldCenter: SIMD3<Float>(worldPosition.x, ground + 0.58, worldPosition.y),
                        worldWidth: max(width * 0.4, depth * 1.2),
                        worldHeight: 1.08,
                        distanceGameUnits: distance,
                        alignmentScore: alignment,
                        color: baseColor
                    )
                )
            case InteractableKind_EmplacedWeapon:
                consider(
                    candidate: FirstPersonFocusCandidate(
                        worldCenter: SIMD3<Float>(worldPosition.x, ground + 0.38, worldPosition.y),
                        worldWidth: width * 0.82,
                        worldHeight: 0.54,
                        distanceGameUnits: distance,
                        alignmentScore: alignment,
                        color: baseColor
                    )
                )
            default:
                break
            }
        }

        let itemCount = Int(game_world_item_count(statePointer))
        for index in 0..<itemCount {
            guard let item = game_world_item_at(statePointer, index)?.pointee, item.active else {
                continue
            }

            let position = SIMD2<Float>(item.position.x, item.position.y)
            let offset = position - playerPosition
            let distance = simd_length(offset)
            guard distance > 2.0, distance <= 130.0 else {
                continue
            }

            let alignment = simd_dot(simd_normalize(offset), forward2D)
            let lateral = abs(simd_dot(offset, right2D))
            guard alignment > 0.08, lateral <= max(34.0, distance * 0.62) else {
                continue
            }

            let ground = terrainElevation(at: position, statePointer: statePointer)
            let worldPosition = renderWorldPosition(position)
            let candidate: FirstPersonFocusCandidate?

            switch item.kind {
            case ItemKind_BulletBox:
                candidate = FirstPersonFocusCandidate(
                    worldCenter: SIMD3<Float>(worldPosition.x, ground + 0.08, worldPosition.y),
                    worldWidth: 0.2,
                    worldHeight: 0.16,
                    distanceGameUnits: distance,
                    alignmentScore: alignment,
                    color: ammoColor(item.ammoType)
                )
            case ItemKind_Magazine:
                candidate = FirstPersonFocusCandidate(
                    worldCenter: SIMD3<Float>(worldPosition.x, ground + 0.14, worldPosition.y),
                    worldWidth: 0.08,
                    worldHeight: 0.28,
                    distanceGameUnits: distance,
                    alignmentScore: alignment,
                    color: SIMD4<Float>(0.93, 0.53, 0.18, 0.92)
                )
            case ItemKind_Gun:
                candidate = FirstPersonFocusCandidate(
                    worldCenter: SIMD3<Float>(worldPosition.x, ground + 0.08, worldPosition.y),
                    worldWidth: 0.36,
                    worldHeight: 0.12,
                    distanceGameUnits: distance,
                    alignmentScore: alignment,
                    color: SIMD4<Float>(0.36, 0.82, 0.86, 0.92)
                )
            case ItemKind_Blade:
                candidate = FirstPersonFocusCandidate(
                    worldCenter: SIMD3<Float>(worldPosition.x, ground + 0.2, worldPosition.y),
                    worldWidth: 0.08,
                    worldHeight: 0.4,
                    distanceGameUnits: distance,
                    alignmentScore: alignment,
                    color: SIMD4<Float>(0.85, 0.86, 0.9, 0.92)
                )
            case ItemKind_Attachment:
                candidate = FirstPersonFocusCandidate(
                    worldCenter: SIMD3<Float>(worldPosition.x, ground + 0.08, worldPosition.y),
                    worldWidth: 0.16,
                    worldHeight: 0.14,
                    distanceGameUnits: distance,
                    alignmentScore: alignment,
                    color: SIMD4<Float>(0.28, 0.82, 0.52, 0.92)
                )
            case ItemKind_Medkit:
                candidate = FirstPersonFocusCandidate(
                    worldCenter: SIMD3<Float>(worldPosition.x, ground + 0.1, worldPosition.y),
                    worldWidth: 0.18,
                    worldHeight: 0.18,
                    distanceGameUnits: distance,
                    alignmentScore: alignment,
                    color: SIMD4<Float>(0.92, 0.24, 0.18, 0.92)
                )
            case ItemKind_Objective:
                candidate = FirstPersonFocusCandidate(
                    worldCenter: SIMD3<Float>(worldPosition.x, ground + 0.5, worldPosition.y),
                    worldWidth: 0.16,
                    worldHeight: 1.05,
                    distanceGameUnits: distance,
                    alignmentScore: alignment,
                    color: SIMD4<Float>(0.96, 0.88, 0.24, 0.94)
                )
            default:
                candidate = nil
            }

            if let candidate {
                consider(candidate: candidate)
            }
        }

        return bestCue
    }

    private func addDepthAwareFocusCue(to instances: inout [RenderInstance], cue: FirstPersonFocusCue) {
        let alpha = max(0.16, min(0.82, 0.88 - cue.distanceGameUnits / 260.0))
        let bracketColor = SIMD4<Float>(cue.color.x, cue.color.y, cue.color.z, alpha)
        let ringSize = cue.size * SIMD2<Float>(1.04, 1.04)
        let tickWidth = max(0.02, cue.size.x * 0.18)
        let tickHeight = max(0.02, cue.size.y * 0.18)

        instances.append(makeInstance(position: cue.screenPosition, size: ringSize, color: SIMD4<Float>(cue.color.x, cue.color.y, cue.color.z, alpha * 0.72), rotation: 0, shape: .ring))
        instances.append(makeInstance(position: cue.screenPosition + SIMD2<Float>(-cue.size.x * 0.54, -cue.size.y * 0.54), size: SIMD2<Float>(tickWidth, 0.012), color: bracketColor, rotation: 0, shape: .rectangle))
        instances.append(makeInstance(position: cue.screenPosition + SIMD2<Float>(-cue.size.x * 0.6, -cue.size.y * 0.48), size: SIMD2<Float>(0.012, tickHeight), color: bracketColor, rotation: 0, shape: .rectangle))
        instances.append(makeInstance(position: cue.screenPosition + SIMD2<Float>(cue.size.x * 0.54, -cue.size.y * 0.54), size: SIMD2<Float>(tickWidth, 0.012), color: bracketColor, rotation: 0, shape: .rectangle))
        instances.append(makeInstance(position: cue.screenPosition + SIMD2<Float>(cue.size.x * 0.6, -cue.size.y * 0.48), size: SIMD2<Float>(0.012, tickHeight), color: bracketColor, rotation: 0, shape: .rectangle))
        instances.append(makeInstance(position: cue.screenPosition + SIMD2<Float>(-cue.size.x * 0.54, cue.size.y * 0.54), size: SIMD2<Float>(tickWidth, 0.012), color: bracketColor, rotation: 0, shape: .rectangle))
        instances.append(makeInstance(position: cue.screenPosition + SIMD2<Float>(-cue.size.x * 0.6, cue.size.y * 0.48), size: SIMD2<Float>(0.012, tickHeight), color: bracketColor, rotation: 0, shape: .rectangle))
        instances.append(makeInstance(position: cue.screenPosition + SIMD2<Float>(cue.size.x * 0.54, cue.size.y * 0.54), size: SIMD2<Float>(tickWidth, 0.012), color: bracketColor, rotation: 0, shape: .rectangle))
        instances.append(makeInstance(position: cue.screenPosition + SIMD2<Float>(cue.size.x * 0.6, cue.size.y * 0.48), size: SIMD2<Float>(0.012, tickHeight), color: bracketColor, rotation: 0, shape: .rectangle))
    }

    private func projectWorldPointToOverlay(_ worldPoint: SIMD3<Float>,
                                            uniforms: World3DUniforms) -> SIMD2<Float>? {
        let clip = uniforms.viewProjectionMatrix * SIMD4<Float>(worldPoint.x, worldPoint.y, worldPoint.z, 1.0)
        guard clip.w > 0.001 else {
            return nil
        }

        let ndc = SIMD3<Float>(clip.x, clip.y, clip.z) / clip.w
        guard ndc.z > -0.2, ndc.z < 1.2 else {
            return nil
        }
        return SIMD2<Float>(ndc.x, -ndc.y)
    }

    private func projectedOverlaySize(worldCenter: SIMD3<Float>,
                                      worldWidth: Float,
                                      worldHeight: Float,
                                      camera: FirstPersonCameraRig,
                                      uniforms: World3DUniforms) -> SIMD2<Float>? {
        guard let center = projectWorldPointToOverlay(worldCenter, uniforms: uniforms),
              let rightPoint = projectWorldPointToOverlay(worldCenter + camera.right * max(0.01, worldWidth * 0.5), uniforms: uniforms),
              let topPoint = projectWorldPointToOverlay(worldCenter + SIMD3<Float>(0, max(0.01, worldHeight * 0.5), 0), uniforms: uniforms) else {
            return nil
        }

        return SIMD2<Float>(
            max(0.02, abs(rightPoint.x - center.x) * 2.0),
            max(0.02, abs(topPoint.y - center.y) * 2.0)
        )
    }

    private func intersectRayWithWorldBox(origin: SIMD3<Float>,
                                          direction: SIMD3<Float>,
                                          instance: World3DInstance) -> Float? {
        let sinYaw = sinf(-instance.yaw)
        let cosYaw = cosf(-instance.yaw)

        func toLocal(_ value: SIMD3<Float>) -> SIMD3<Float> {
            SIMD3<Float>(
                value.x * cosYaw - value.z * sinYaw,
                value.y,
                value.x * sinYaw + value.z * cosYaw
            )
        }

        let localOrigin = toLocal(origin - instance.position)
        let localDirection = toLocal(direction)
        let halfSize = instance.size * 0.5

        var tMin: Float = 0.0
        var tMax: Float = Float.greatestFiniteMagnitude

        for axis in 0..<3 {
            let originAxis = localOrigin[axis]
            let directionAxis = localDirection[axis]
            let minAxis = -halfSize[axis]
            let maxAxis = halfSize[axis]

            if abs(directionAxis) < 0.0001 {
                if originAxis < minAxis || originAxis > maxAxis {
                    return nil
                }
                continue
            }

            let inverseDirection = 1.0 / directionAxis
            let t0 = (minAxis - originAxis) * inverseDirection
            let t1 = (maxAxis - originAxis) * inverseDirection
            tMin = max(tMin, min(t0, t1))
            tMax = min(tMax, max(t0, t1))
            if tMax < tMin {
                return nil
            }
        }

        if tMin > 0.001 {
            return tMin
        }
        return tMax > 0.001 ? tMax : nil
    }

    private func estimateAimTargetDepth(statePointer: UnsafePointer<GameState>,
                                        playerPosition: SIMD2<Float>,
                                        forward: SIMD2<Float>,
                                        right: SIMD2<Float>) -> Float {
        var nearestDepth: Float = 520.0

        func consider(_ position: SIMD2<Float>, width: Float) {
            let delta = position - playerPosition
            let depth = simd_dot(delta, forward)
            guard depth > 18, depth < nearestDepth else {
                return
            }

            let lateral = abs(simd_dot(delta, right))
            guard lateral <= max(18.0, width * 0.72) else {
                return
            }

            nearestDepth = depth
        }

        let structureCount = Int(game_structure_count(statePointer))
        for index in 0..<structureCount {
            guard let structure = game_structure_at(statePointer, index)?.pointee, structure.active else {
                continue
            }
            consider(SIMD2<Float>(structure.position.x, structure.position.y), width: max(structure.size.x, structure.size.y))
        }

        let interactableCount = Int(game_interactable_count(statePointer))
        for index in 0..<interactableCount {
            guard let interactable = game_interactable_at(statePointer, index)?.pointee, interactable.active else {
                continue
            }
            consider(SIMD2<Float>(interactable.position.x, interactable.position.y), width: max(interactable.size.x, interactable.size.y))
        }

        let itemCount = Int(game_world_item_count(statePointer))
        for index in 0..<itemCount {
            guard let item = game_world_item_at(statePointer, index)?.pointee, item.active else {
                continue
            }
            consider(SIMD2<Float>(item.position.x, item.position.y), width: 40)
        }

        let enemyCount = Int(game_enemy_count(statePointer))
        for index in 0..<enemyCount {
            guard let enemy = game_enemy_at(statePointer, index)?.pointee, enemy.active else {
                continue
            }
            consider(SIMD2<Float>(enemy.position.x, enemy.position.y), width: 48)
        }

        return nearestDepth
    }

    private func buildFirstPersonInstances(viewModel: GameViewModel) -> [RenderInstance] {
        var instances: [RenderInstance] = []
        instances.reserveCapacity(520)

        viewModel.withState { statePointer in
            let player = statePointer.pointee.player
            let playerPosition = SIMD2<Float>(player.position.x, player.position.y)
            let forward = normalizedAim(for: player)
            let right = SIMD2<Float>(forward.y, -forward.x)
            let speed = simd_length(SIMD2<Float>(player.velocity.x, player.velocity.y))
            let bobAmplitude = min(0.045, speed * 0.0009) * stanceBobMultiplier(player.stance)
            let swayPhase = statePointer.pointee.missionTime * (speed > 5 ? 10.5 : 6.0)
            let sway = sinf(swayPhase) * bobAmplitude
            let cameraOffset = player.lean * 0.09 + sway * 0.35
            let horizon = baseHorizon(for: player.stance) + (cosf(swayPhase * 0.55) * bobAmplitude * 0.28)

            addFirstPersonBackdrop(
                to: &instances,
                statePointer: statePointer,
                playerPosition: playerPosition,
                horizon: horizon,
                sway: sway
            )

            let occlusionField = buildFirstPersonOcclusionField(
                statePointer: statePointer,
                playerPosition: playerPosition,
                forward: forward,
                right: right,
                horizon: horizon,
                cameraOffset: cameraOffset
            )
            var layers: [PerspectiveLayer] = []
            layers.reserveCapacity(180)
            var focusOverlay: FocusOverlay?

            let structureCount = Int(game_structure_count(statePointer))
            for index in 0..<structureCount {
                guard let structure = game_structure_at(statePointer, index)?.pointee else {
                    continue
                }
                addFirstPersonStructure(
                    structure,
                    to: &layers,
                    playerPosition: playerPosition,
                    forward: forward,
                    right: right,
                    horizon: horizon,
                    cameraOffset: cameraOffset,
                    occlusionField: occlusionField
                )
            }

            let interactableCount = Int(game_interactable_count(statePointer))
            for index in 0..<interactableCount {
                guard let interactable = game_interactable_at(statePointer, index)?.pointee else {
                    continue
                }
                addFirstPersonInteractable(
                    interactable,
                    to: &layers,
                    playerPosition: playerPosition,
                    forward: forward,
                    right: right,
                    horizon: horizon,
                    cameraOffset: cameraOffset,
                    occlusionField: occlusionField,
                    focusOverlay: &focusOverlay
                )
            }

            let itemCount = Int(game_world_item_count(statePointer))
            for index in 0..<itemCount {
                guard let item = game_world_item_at(statePointer, index)?.pointee else {
                    continue
                }
                addFirstPersonItem(
                    item,
                    to: &layers,
                    playerPosition: playerPosition,
                    forward: forward,
                    right: right,
                    horizon: horizon,
                    cameraOffset: cameraOffset,
                    occlusionField: occlusionField,
                    focusOverlay: &focusOverlay
                )
            }

            let enemyCount = Int(game_enemy_count(statePointer))
            for index in 0..<enemyCount {
                guard let enemy = game_enemy_at(statePointer, index)?.pointee else {
                    continue
                }
                addFirstPersonEnemy(
                    enemy,
                    to: &layers,
                    playerPosition: playerPosition,
                    forward: forward,
                    right: right,
                    horizon: horizon,
                    cameraOffset: cameraOffset,
                    occlusionField: occlusionField
                )
            }

            let projectileCount = Int(game_projectile_count(statePointer))
            for index in 0..<projectileCount {
                guard let projectile = game_projectile_at(statePointer, index)?.pointee else {
                    continue
                }
                addFirstPersonProjectile(
                    projectile,
                    to: &layers,
                    playerPosition: playerPosition,
                    forward: forward,
                    right: right,
                    horizon: horizon,
                    cameraOffset: cameraOffset,
                    occlusionField: occlusionField
                )
            }

            layers.sort { $0.depth > $1.depth }
            for layer in layers {
                instances.append(contentsOf: layer.instances)
            }

            if let focusOverlay {
                addFocusOverlay(to: &instances, focusOverlay: focusOverlay)
            }

            let selectedIndex = Int(game_selected_inventory_index(statePointer))
            let selectedItem = selectedIndex >= 0 ? game_inventory_item_at(statePointer, selectedIndex)?.pointee : nil
            let targetDepth = occlusionField.nearestDepth(around: -cameraOffset * 0.2, fallback: 420.0)
            let aimPosition = SIMD2<Float>(-cameraOffset * 0.1, 0.02 + min(player.fireCooldown * 0.18, 0.02))

            addFirstPersonReticle(
                to: &instances,
                player: player,
                selectedItem: selectedItem,
                aimPosition: aimPosition
            )
            addWeaponViewModel(
                to: &instances,
                statePointer: statePointer,
                sway: sway,
                aimPosition: aimPosition,
                horizon: horizon,
                targetDepth: targetDepth
            )
        }

        return instances
    }

    private func addTerrainBackdrop(to instances: inout [RenderInstance], camera: SIMD2<Float>, worldViewport: SIMD2<Float>) {
        instances.append(
            makeInstance(
                position: camera,
                size: worldViewport * 1.5,
                color: SIMD4<Float>(0.08, 0.13, 0.09, 1),
                rotation: 0,
                shape: .rectangle
            )
        )
        instances.append(
            makeInstance(
                position: camera + SIMD2<Float>(-180, 140),
                size: worldViewport * SIMD2<Float>(0.74, 0.26),
                color: SIMD4<Float>(0.12, 0.18, 0.12, 0.62),
                rotation: -0.25,
                shape: .rectangle
            )
        )
        instances.append(
            makeInstance(
                position: camera + SIMD2<Float>(260, -180),
                size: worldViewport * SIMD2<Float>(0.55, 0.21),
                color: SIMD4<Float>(0.18, 0.16, 0.12, 0.42),
                rotation: 0.35,
                shape: .rectangle
            )
        )

        let spacing: Float = 120
        let xStart = floor((camera.x - worldViewport.x * 0.65) / spacing) * spacing
        let xEnd = ceil((camera.x + worldViewport.x * 0.65) / spacing) * spacing
        let yStart = floor((camera.y - worldViewport.y * 0.65) / spacing) * spacing
        let yEnd = ceil((camera.y + worldViewport.y * 0.65) / spacing) * spacing
        let gridColor = SIMD4<Float>(0.28, 0.34, 0.22, 0.28)

        var x = xStart
        while x <= xEnd {
            instances.append(
                makeInstance(
                    position: SIMD2<Float>(x, camera.y),
                    size: SIMD2<Float>(2, worldViewport.y * 1.4),
                    color: gridColor,
                    rotation: 0,
                    shape: .rectangle
                )
            )
            x += spacing
        }

        var y = yStart
        while y <= yEnd {
            instances.append(
                makeInstance(
                    position: SIMD2<Float>(camera.x, y),
                    size: SIMD2<Float>(worldViewport.x * 1.4, 2),
                    color: gridColor,
                    rotation: 0,
                    shape: .rectangle
                )
            )
            y += spacing
        }
    }

    private func addFirstPersonBackdrop(to instances: inout [RenderInstance],
                                        statePointer: UnsafePointer<GameState>,
                                        playerPosition: SIMD2<Float>,
                                        horizon: Float,
                                        sway: Float) {
        let terrainColor = currentTerrainTint(statePointer: statePointer, playerPosition: playerPosition)
        let skyTop = mixedColor(SIMD4<Float>(0.07, 0.13, 0.18, 1), terrainColor, amount: 0.12)
        let skyLow = mixedColor(SIMD4<Float>(0.21, 0.29, 0.28, 1), terrainColor, amount: 0.22)
        let dustGlow = SIMD4<Float>(0.82, 0.68, 0.46, 0.16)
        let hazeColor = mixedColor(SIMD4<Float>(0.56, 0.58, 0.42, 0.14), terrainColor, amount: 0.1)
        let groundColor = mixedColor(SIMD4<Float>(0.18, 0.21, 0.16, 1), terrainColor, amount: 0.72)
        let horizonBand = mixedColor(SIMD4<Float>(0.46, 0.39, 0.25, 0.62), terrainColor, amount: 0.08)
        let ridgeLeft = mixedColor(SIMD4<Float>(0.24, 0.29, 0.24, 0.56), terrainColor, amount: 0.3)
        let ridgeRight = mixedColor(SIMD4<Float>(0.22, 0.25, 0.21, 0.42), terrainColor, amount: 0.26)

        instances.append(makeInstance(position: SIMD2<Float>(0, -0.84), size: SIMD2<Float>(2.8, 0.82), color: skyTop, rotation: 0, shape: .rectangle))
        instances.append(makeInstance(position: SIMD2<Float>(0, -0.34), size: SIMD2<Float>(2.8, 0.72), color: skyLow, rotation: 0, shape: .rectangle))
        instances.append(makeInstance(position: SIMD2<Float>(-0.48, horizon - 0.42), size: SIMD2<Float>(0.52, 0.52), color: dustGlow, rotation: 0, shape: .circle))
        instances.append(makeInstance(position: SIMD2<Float>(0.16, horizon - 0.22), size: SIMD2<Float>(2.36, 0.46), color: hazeColor, rotation: 0, shape: .rectangle))
        instances.append(makeInstance(position: SIMD2<Float>(0.02, horizon + 0.82), size: SIMD2<Float>(2.8, 1.42), color: groundColor, rotation: 0, shape: .rectangle))
        instances.append(makeInstance(position: SIMD2<Float>(0, horizon + 0.02), size: SIMD2<Float>(2.28, 0.06), color: horizonBand, rotation: 0, shape: .rectangle))
        instances.append(makeInstance(position: SIMD2<Float>(-0.74, horizon - 0.29), size: SIMD2<Float>(0.58, 0.2), color: ridgeLeft, rotation: 0, shape: .rectangle))
        instances.append(makeInstance(position: SIMD2<Float>(0.7, horizon - 0.23), size: SIMD2<Float>(0.82, 0.24), color: ridgeRight, rotation: 0, shape: .rectangle))
        instances.append(makeInstance(position: SIMD2<Float>(-0.18, horizon - 0.54), size: SIMD2<Float>(0.44, 0.08), color: SIMD4<Float>(0.7, 0.72, 0.7, 0.08), rotation: -0.04, shape: .rectangle))
        instances.append(makeInstance(position: SIMD2<Float>(0.42, horizon - 0.48), size: SIMD2<Float>(0.58, 0.07), color: SIMD4<Float>(0.76, 0.76, 0.72, 0.06), rotation: 0.03, shape: .rectangle))

        let floorBands: [Float] = [0.18, 0.3, 0.44, 0.6, 0.78, 0.98]
        for (index, bandY) in floorBands.enumerated() {
            let alpha = max(0.08, 0.25 - Float(index) * 0.024)
            let width = 2.1 - Float(index) * 0.1
            let height = 0.018 + Float(index) * 0.006
            instances.append(
                makeInstance(
                    position: SIMD2<Float>(sway * 0.35, horizon + bandY),
                    size: SIMD2<Float>(width, height),
                    color: mixedColor(SIMD4<Float>(0.07, 0.09, 0.08, alpha), terrainColor, amount: 0.18),
                    rotation: 0,
                    shape: .rectangle
                )
            )
        }
    }

    private func addFirstPersonStructure(_ structure: Structure,
                                         to layers: inout [PerspectiveLayer],
                                         playerPosition: SIMD2<Float>,
                                         forward: SIMD2<Float>,
                                         right: SIMD2<Float>,
                                         horizon: Float,
                                         cameraOffset: Float,
                                         occlusionField: OcclusionField) {
        let position = SIMD2<Float>(structure.position.x, structure.position.y)
        let screen = projectFootprint(
            worldPosition: position,
            width: structure.size.x,
            height: firstPersonHeight(for: structure),
            playerPosition: playerPosition,
            forward: forward,
            right: right,
            horizon: horizon,
            cameraOffset: cameraOffset
        )
        guard let screen else {
            return
        }

        let visibility = occlusionField.visibility(center: screen.position.x, width: screen.size.x * 1.1, depth: screen.depth, softness: 34)
        if visibility < 0.06 {
            return
        }

        var layerInstances: [RenderInstance] = []
        let shadowWidth = max(0.05, screen.size.x * 0.8)
        layerInstances.append(
            makeInstance(
                position: SIMD2<Float>(screen.position.x, screen.footY - 0.02),
                size: SIMD2<Float>(shadowWidth, 0.04),
                color: alphaAdjusted(SIMD4<Float>(0.04, 0.04, 0.04, 0.25), factor: visibility, minimumAlpha: 0.03),
                rotation: 0,
                shape: .circle
            )
        )

        switch structure.kind {
        case StructureKind_Ridge:
            layerInstances.append(makeInstance(position: screen.position, size: screen.size * SIMD2<Float>(1.25, 0.72), color: alphaAdjusted(SIMD4<Float>(0.29, 0.27, 0.18, 0.84), factor: visibility, minimumAlpha: 0.14), rotation: 0, shape: .rectangle))
        case StructureKind_Road:
            let roadHeight = max(0.03, screen.size.y * 0.12)
            layerInstances.append(makeInstance(position: SIMD2<Float>(screen.position.x, screen.footY + 0.015), size: SIMD2<Float>(max(0.2, screen.size.x * 1.45), roadHeight), color: alphaAdjusted(SIMD4<Float>(0.18, 0.19, 0.19, 0.62), factor: visibility, minimumAlpha: 0.08), rotation: 0, shape: .rectangle))
            layerInstances.append(makeInstance(position: SIMD2<Float>(screen.position.x, screen.footY + 0.016), size: SIMD2<Float>(max(0.04, screen.size.x * 0.18), max(0.01, roadHeight * 0.28)), color: alphaAdjusted(SIMD4<Float>(0.8, 0.74, 0.42, 0.4), factor: visibility, minimumAlpha: 0.05), rotation: 0, shape: .rectangle))
        case StructureKind_TreeCluster:
            layerInstances.append(makeInstance(position: screen.position + SIMD2<Float>(-screen.size.x * 0.12, -screen.size.y * 0.08), size: screen.size * SIMD2<Float>(0.86, 1.08), color: alphaAdjusted(SIMD4<Float>(0.16, 0.42, 0.2, 0.78), factor: visibility, minimumAlpha: 0.12), rotation: 0, shape: .circle))
            layerInstances.append(makeInstance(position: screen.position + SIMD2<Float>(screen.size.x * 0.16, -screen.size.y * 0.16), size: screen.size * SIMD2<Float>(0.66, 0.88), color: alphaAdjusted(SIMD4<Float>(0.1, 0.31, 0.14, 0.7), factor: visibility, minimumAlpha: 0.12), rotation: 0, shape: .circle))
        case StructureKind_Building:
            layerInstances.append(makeInstance(position: screen.position, size: screen.size, color: alphaAdjusted(SIMD4<Float>(0.48, 0.46, 0.4, 0.94), factor: visibility, minimumAlpha: 0.18), rotation: 0, shape: .rectangle))
            layerInstances.append(makeInstance(position: screen.position + SIMD2<Float>(0, screen.size.y * 0.04), size: screen.size * SIMD2<Float>(0.84, 0.68), color: alphaAdjusted(SIMD4<Float>(0.21, 0.23, 0.22, 0.78), factor: visibility, minimumAlpha: 0.14), rotation: 0, shape: .rectangle))
        case StructureKind_LowWall:
            layerInstances.append(makeInstance(position: screen.position, size: screen.size * SIMD2<Float>(1.05, 0.55), color: alphaAdjusted(SIMD4<Float>(0.7, 0.67, 0.56, 0.95), factor: visibility, minimumAlpha: 0.18), rotation: 0, shape: .rectangle))
        case StructureKind_Tower:
            layerInstances.append(makeInstance(position: screen.position, size: screen.size * SIMD2<Float>(0.72, 1.18), color: alphaAdjusted(SIMD4<Float>(0.54, 0.5, 0.4, 0.94), factor: visibility, minimumAlpha: 0.18), rotation: 0, shape: .rectangle))
            layerInstances.append(makeInstance(position: screen.position + SIMD2<Float>(0, -screen.size.y * 0.26), size: screen.size * SIMD2<Float>(0.98, 0.18), color: alphaAdjusted(SIMD4<Float>(0.27, 0.24, 0.19, 0.84), factor: visibility, minimumAlpha: 0.12), rotation: 0, shape: .rectangle))
        case StructureKind_Convoy:
            layerInstances.append(makeInstance(position: screen.position, size: screen.size * SIMD2<Float>(1.02, 0.72), color: alphaAdjusted(SIMD4<Float>(0.24, 0.28, 0.25, 0.94), factor: visibility, minimumAlpha: 0.18), rotation: 0, shape: .rectangle))
            layerInstances.append(makeInstance(position: screen.position + SIMD2<Float>(0, screen.size.y * 0.05), size: screen.size * SIMD2<Float>(0.66, 0.32), color: alphaAdjusted(SIMD4<Float>(0.1, 0.11, 0.11, 0.86), factor: visibility, minimumAlpha: 0.12), rotation: 0, shape: .rectangle))
        case StructureKind_Door:
            layerInstances.append(makeInstance(position: screen.position, size: screen.size * SIMD2<Float>(0.7, 0.94), color: alphaAdjusted(SIMD4<Float>(0.76, 0.69, 0.53, 0.88), factor: visibility, minimumAlpha: 0.14), rotation: 0, shape: .rectangle))
        default:
            break
        }

        if !layerInstances.isEmpty {
            layers.append(PerspectiveLayer(depth: screen.depth, instances: layerInstances))
        }
    }

    private func addFirstPersonInteractable(_ interactable: Interactable,
                                            to layers: inout [PerspectiveLayer],
                                            playerPosition: SIMD2<Float>,
                                            forward: SIMD2<Float>,
                                            right: SIMD2<Float>,
                                            horizon: Float,
                                            cameraOffset: Float,
                                            occlusionField: OcclusionField,
                                            focusOverlay: inout FocusOverlay?) {
        let position = SIMD2<Float>(interactable.position.x, interactable.position.y)
        let screen = projectFootprint(
            worldPosition: position,
            width: interactable.size.x,
            height: firstPersonHeight(for: interactable),
            playerPosition: playerPosition,
            forward: forward,
            right: right,
            horizon: horizon,
            cameraOffset: cameraOffset
        )
        guard let screen else {
            return
        }

        let visibility = occlusionField.visibility(center: screen.position.x, width: screen.size.x * 1.05, depth: screen.depth)
        if visibility < 0.08 {
            return
        }

        let color = alphaAdjusted(
            interactableColor(kind: interactable.kind, toggled: interactable.toggled, singleUse: interactable.singleUse),
            factor: visibility,
            minimumAlpha: 0.08
        )
        var layerInstances: [RenderInstance] = [
            makeInstance(position: SIMD2<Float>(screen.position.x, screen.footY - 0.014), size: SIMD2<Float>(max(0.03, screen.size.x * 0.52), 0.03), color: alphaAdjusted(SIMD4<Float>(0.04, 0.04, 0.04, 0.22), factor: visibility, minimumAlpha: 0.03), rotation: 0, shape: .circle)
        ]

        switch interactable.kind {
        case InteractableKind_Door:
            layerInstances.append(makeInstance(position: screen.position, size: screen.size * SIMD2<Float>(0.74, 0.9), color: color, rotation: 0, shape: .rectangle))
        case InteractableKind_SupplyCrate:
            layerInstances.append(makeInstance(position: screen.position, size: screen.size * SIMD2<Float>(0.86, 0.54), color: color, rotation: 0, shape: .rectangle))
            layerInstances.append(makeInstance(position: screen.position + SIMD2<Float>(0, -screen.size.y * 0.08), size: screen.size * SIMD2<Float>(0.26, 0.46), color: alphaAdjusted(SIMD4<Float>(0.92, 0.93, 0.95, 0.72), factor: visibility, minimumAlpha: 0.08), rotation: 0, shape: .rectangle))
        case InteractableKind_DeadDrop:
            layerInstances.append(makeInstance(position: screen.position, size: screen.size * SIMD2<Float>(0.8, 0.44), color: color, rotation: 0, shape: .circle))
        case InteractableKind_Radio:
            layerInstances.append(makeInstance(position: screen.position, size: screen.size * SIMD2<Float>(0.56, 0.74), color: color, rotation: 0, shape: .rectangle))
            layerInstances.append(makeInstance(position: screen.position + SIMD2<Float>(0, -screen.size.y * 0.24), size: screen.size * SIMD2<Float>(0.08, 0.44), color: alphaAdjusted(SIMD4<Float>(0.92, 0.95, 0.93, 0.74), factor: visibility, minimumAlpha: 0.08), rotation: 0, shape: .rectangle))
        case InteractableKind_EmplacedWeapon:
            layerInstances.append(makeInstance(position: screen.position + SIMD2<Float>(0, screen.size.y * 0.04), size: screen.size * SIMD2<Float>(0.9, 0.18), color: color, rotation: 0, shape: .rectangle))
            layerInstances.append(makeInstance(position: screen.position + SIMD2<Float>(screen.size.x * 0.16, -screen.size.y * 0.1), size: screen.size * SIMD2<Float>(0.42, 0.08), color: alphaAdjusted(SIMD4<Float>(0.16, 0.16, 0.16, 0.9), factor: visibility, minimumAlpha: 0.08), rotation: 0, shape: .rectangle))
        default:
            break
        }

        registerFocusOverlay(
            &focusOverlay,
            position: screen.position,
            size: screen.size,
            footY: screen.footY,
            color: color,
            depth: screen.depth,
            centeredness: abs(screen.position.x),
            visibility: visibility
        )
        layers.append(PerspectiveLayer(depth: screen.depth, instances: layerInstances))
    }

    private func addFirstPersonItem(_ item: WorldItem,
                                    to layers: inout [PerspectiveLayer],
                                    playerPosition: SIMD2<Float>,
                                    forward: SIMD2<Float>,
                                    right: SIMD2<Float>,
                                    horizon: Float,
                                    cameraOffset: Float,
                                    occlusionField: OcclusionField,
                                    focusOverlay: inout FocusOverlay?) {
        let position = SIMD2<Float>(item.position.x, item.position.y)
        let screen = projectFootprint(
            worldPosition: position,
            width: firstPersonWidth(for: item),
            height: firstPersonHeight(for: item),
            playerPosition: playerPosition,
            forward: forward,
            right: right,
            horizon: horizon,
            cameraOffset: cameraOffset
        )
        guard let screen else {
            return
        }

        let visibility = occlusionField.visibility(center: screen.position.x, width: screen.size.x * 1.1, depth: screen.depth, softness: 20)
        if visibility < 0.08 {
            return
        }

        var layerInstances: [RenderInstance] = [
            makeInstance(position: SIMD2<Float>(screen.position.x, screen.footY - 0.01), size: SIMD2<Float>(max(0.022, screen.size.x * 0.44), 0.024), color: alphaAdjusted(SIMD4<Float>(0.02, 0.02, 0.02, 0.22), factor: visibility, minimumAlpha: 0.03), rotation: 0, shape: .circle)
        ]

        switch item.kind {
        case ItemKind_BulletBox:
            layerInstances.append(makeInstance(position: screen.position, size: screen.size * SIMD2<Float>(0.88, 0.52), color: alphaAdjusted(ammoColor(item.ammoType), factor: visibility, minimumAlpha: 0.08), rotation: 0, shape: .rectangle))
        case ItemKind_Magazine:
            layerInstances.append(makeInstance(position: screen.position, size: screen.size * SIMD2<Float>(0.42, 0.92), color: alphaAdjusted(SIMD4<Float>(0.93, 0.53, 0.18, 0.96), factor: visibility, minimumAlpha: 0.08), rotation: 0, shape: .rectangle))
        case ItemKind_Gun:
            layerInstances.append(makeInstance(position: screen.position, size: screen.size * SIMD2<Float>(1.22, 0.28), color: alphaAdjusted(SIMD4<Float>(0.36, 0.82, 0.86, 0.96), factor: visibility, minimumAlpha: 0.08), rotation: 0, shape: .rectangle))
        case ItemKind_Blade:
            layerInstances.append(makeInstance(position: screen.position, size: screen.size * SIMD2<Float>(0.28, 1.08), color: alphaAdjusted(SIMD4<Float>(0.85, 0.86, 0.9, 0.96), factor: visibility, minimumAlpha: 0.08), rotation: 0, shape: .rectangle))
        case ItemKind_Attachment:
            layerInstances.append(makeInstance(position: screen.position, size: screen.size * SIMD2<Float>(0.84, 0.5), color: alphaAdjusted(SIMD4<Float>(0.28, 0.82, 0.52, 0.96), factor: visibility, minimumAlpha: 0.08), rotation: 0, shape: .rectangle))
        case ItemKind_Medkit:
            layerInstances.append(makeInstance(position: screen.position, size: screen.size * SIMD2<Float>(0.72, 0.72), color: alphaAdjusted(SIMD4<Float>(0.92, 0.24, 0.18, 0.96), factor: visibility, minimumAlpha: 0.08), rotation: 0, shape: .rectangle))
        case ItemKind_Objective:
            layerInstances.append(makeInstance(position: screen.position, size: screen.size * SIMD2<Float>(0.84, 0.84), color: alphaAdjusted(SIMD4<Float>(0.96, 0.88, 0.24, 0.92), factor: visibility, minimumAlpha: 0.08), rotation: 0, shape: .ring))
            layerInstances.append(makeInstance(position: screen.position, size: screen.size * SIMD2<Float>(0.4, 0.4), color: alphaAdjusted(SIMD4<Float>(0.98, 0.92, 0.42, 0.95), factor: visibility, minimumAlpha: 0.08), rotation: 0, shape: .circle))
        default:
            break
        }

        let highlightColor: SIMD4<Float>
        switch item.kind {
        case ItemKind_Objective:
            highlightColor = SIMD4<Float>(0.98, 0.9, 0.34, 0.88)
        case ItemKind_Medkit:
            highlightColor = SIMD4<Float>(0.96, 0.32, 0.24, 0.88)
        case ItemKind_Attachment:
            highlightColor = SIMD4<Float>(0.3, 0.86, 0.54, 0.88)
        default:
            highlightColor = SIMD4<Float>(0.94, 0.84, 0.3, 0.82)
        }

        registerFocusOverlay(
            &focusOverlay,
            position: screen.position,
            size: screen.size,
            footY: screen.footY,
            color: alphaAdjusted(highlightColor, factor: visibility, minimumAlpha: 0.12),
            depth: screen.depth,
            centeredness: abs(screen.position.x),
            visibility: visibility
        )
        layers.append(PerspectiveLayer(depth: screen.depth, instances: layerInstances))
    }

    private func addFirstPersonEnemy(_ enemy: Enemy,
                                     to layers: inout [PerspectiveLayer],
                                     playerPosition: SIMD2<Float>,
                                     forward: SIMD2<Float>,
                                     right: SIMD2<Float>,
                                     horizon: Float,
                                     cameraOffset: Float,
                                     occlusionField: OcclusionField) {
        let position = SIMD2<Float>(enemy.position.x, enemy.position.y)
        let screen = projectFootprint(
            worldPosition: position,
            width: 32,
            height: enemy.fallingBack ? 78 : 88,
            playerPosition: playerPosition,
            forward: forward,
            right: right,
            horizon: horizon,
            cameraOffset: cameraOffset
        )
        guard let screen else {
            return
        }

        let visibility = occlusionField.visibility(center: screen.position.x, width: screen.size.x * 0.92, depth: screen.depth, softness: 18)
        if visibility < 0.1 {
            return
        }

        let healthFactor = max(0.22, enemy.health / 100)
        let flash: Float = enemy.hitTimer > 0 ? 0.22 : 0
        let bodyColor = alphaAdjusted(SIMD4<Float>(0.72 + flash, 0.2 + (0.28 * healthFactor), 0.15, 0.96), factor: visibility, minimumAlpha: 0.1)
        var layerInstances: [RenderInstance] = []
        layerInstances.append(makeInstance(position: SIMD2<Float>(screen.position.x, screen.footY - 0.008), size: SIMD2<Float>(max(0.04, screen.size.x * 0.56), 0.04), color: alphaAdjusted(SIMD4<Float>(0.02, 0.02, 0.02, 0.24), factor: visibility, minimumAlpha: 0.03), rotation: 0, shape: .circle))
        layerInstances.append(makeInstance(position: screen.position + SIMD2<Float>(0, screen.size.y * 0.1), size: screen.size * SIMD2<Float>(0.42, 0.52), color: bodyColor, rotation: 0, shape: .rectangle))
        layerInstances.append(makeInstance(position: screen.position + SIMD2<Float>(0, -screen.size.y * 0.28), size: screen.size * SIMD2<Float>(0.26, 0.26), color: bodyColor, rotation: 0, shape: .circle))
        layerInstances.append(makeInstance(position: screen.position + SIMD2<Float>(0, -screen.size.y * 0.54), size: SIMD2<Float>(max(0.08, screen.size.x * 0.7 * healthFactor), max(0.012, screen.size.y * 0.08)), color: alphaAdjusted(SIMD4<Float>(0.95, 0.78, 0.2, 0.86), factor: visibility, minimumAlpha: 0.06), rotation: 0, shape: .rectangle))
        layers.append(PerspectiveLayer(depth: screen.depth, instances: layerInstances))
    }

    private func addFirstPersonProjectile(_ projectile: Projectile,
                                          to layers: inout [PerspectiveLayer],
                                          playerPosition: SIMD2<Float>,
                                          forward: SIMD2<Float>,
                                          right: SIMD2<Float>,
                                          horizon: Float,
                                          cameraOffset: Float,
                                          occlusionField: OcclusionField) {
        let position = SIMD2<Float>(projectile.position.x, projectile.position.y)
        guard let screen = projectFootprint(
            worldPosition: position,
            width: 10,
            height: 10,
            playerPosition: playerPosition,
            forward: forward,
            right: right,
            horizon: horizon,
            cameraOffset: cameraOffset
        ) else {
            return
        }

        let velocity = SIMD2<Float>(projectile.velocity.x, projectile.velocity.y)
        let lateralVelocity = simd_dot(velocity, right)
        let stretch = max(0.03, min(0.16, simd_length(velocity) / 5200))
        let visibility = occlusionField.visibility(center: screen.position.x, width: max(0.04, stretch), depth: screen.depth, softness: 12)
        if visibility < 0.1 {
            return
        }
        let color = projectile.fromPlayer
            ? alphaAdjusted(SIMD4<Float>(0.96, 0.87, 0.3, 0.92), factor: visibility, minimumAlpha: 0.08)
            : alphaAdjusted(SIMD4<Float>(0.95, 0.34, 0.2, 0.9), factor: visibility, minimumAlpha: 0.08)
        let rotation: Float = lateralVelocity > 0 ? 0.12 : -0.12
        layers.append(
            PerspectiveLayer(
                depth: screen.depth,
                instances: [
                    makeInstance(position: screen.position + SIMD2<Float>(0, -screen.size.y * 0.18), size: SIMD2<Float>(stretch, 0.012), color: color, rotation: rotation, shape: .rectangle)
                ]
            )
        )
    }

    private func addFirstPersonReticle(to instances: inout [RenderInstance],
                                       player: Player,
                                       selectedItem: InventoryItem?,
                                       aimPosition: SIMD2<Float>) {
        let center = aimPosition
        let reticleColor = SIMD4<Float>(0.9, 0.92, 0.95, 0.62 + min(player.suppression / 180, 0.18))
        let spread = 0.022 + min(player.pain / 1200, 0.035) + min(player.suppression / 1600, 0.05)

        if let selectedItem, selectedItem.kind == ItemKind_Gun, selectedItem.opticMounted {
            instances.append(makeInstance(position: center, size: SIMD2<Float>(0.26, 0.26), color: SIMD4<Float>(0.05, 0.06, 0.07, 0.28), rotation: 0, shape: .ring))
            instances.append(makeInstance(position: center, size: SIMD2<Float>(0.18, 0.18), color: SIMD4<Float>(0.08, 0.1, 0.12, 0.18), rotation: 0, shape: .ring))
            instances.append(makeInstance(position: center, size: SIMD2<Float>(0.012, 0.012), color: SIMD4<Float>(0.98, 0.2, 0.18, 0.82), rotation: 0, shape: .circle))
            instances.append(makeInstance(position: center, size: SIMD2<Float>(0.006, 0.08), color: reticleColor, rotation: 0, shape: .rectangle))
            instances.append(makeInstance(position: center, size: SIMD2<Float>(0.08, 0.006), color: reticleColor, rotation: 0, shape: .rectangle))
        } else {
            instances.append(makeInstance(position: center, size: SIMD2<Float>(0.008, 0.09), color: reticleColor, rotation: 0, shape: .rectangle))
            instances.append(makeInstance(position: center, size: SIMD2<Float>(0.09, 0.008), color: reticleColor, rotation: 0, shape: .rectangle))
            instances.append(makeInstance(position: center + SIMD2<Float>(-spread, 0), size: SIMD2<Float>(0.028, 0.006), color: reticleColor, rotation: 0, shape: .rectangle))
            instances.append(makeInstance(position: center + SIMD2<Float>(spread, 0), size: SIMD2<Float>(0.028, 0.006), color: reticleColor, rotation: 0, shape: .rectangle))
            instances.append(makeInstance(position: center + SIMD2<Float>(0, 0.06), size: SIMD2<Float>(0.018, 0.07), color: SIMD4<Float>(0.95, 0.88, 0.78, 0.42), rotation: 0, shape: .rectangle))
            instances.append(makeInstance(position: center + SIMD2<Float>(-0.03, 0.045), size: SIMD2<Float>(0.014, 0.006), color: SIMD4<Float>(0.95, 0.88, 0.78, 0.36), rotation: 0, shape: .rectangle))
            instances.append(makeInstance(position: center + SIMD2<Float>(0.03, 0.045), size: SIMD2<Float>(0.014, 0.006), color: SIMD4<Float>(0.95, 0.88, 0.78, 0.36), rotation: 0, shape: .rectangle))
        }
    }

    private func addWeaponViewModel(to instances: inout [RenderInstance],
                                    statePointer: UnsafePointer<GameState>,
                                    sway: Float,
                                    aimPosition: SIMD2<Float>,
                                    horizon: Float,
                                    targetDepth: Float) {
        let selectedIndex = Int(game_selected_inventory_index(statePointer))
        guard selectedIndex >= 0, let selectedItem = game_inventory_item_at(statePointer, selectedIndex)?.pointee else {
            return
        }

        let player = statePointer.pointee.player
        let recoil = min(0.16, player.fireCooldown * 0.42) + viewmodelKick * 0.08
        let speed = simd_length(SIMD2<Float>(player.velocity.x, player.velocity.y))
        let walkPhase = statePointer.pointee.missionTime * (speed > 6 ? 11.5 : 7.0)
        let walkAmplitude = min(0.045, speed * 0.00095) * stanceBobMultiplier(player.stance)
        let walkSway = sinf(walkPhase) * walkAmplitude
        let walkLift = abs(cosf(walkPhase * 0.6)) * walkAmplitude * 0.55
        let swapProgress = max(0.0, min(1.0, 1.0 - viewmodelSwapTransition))
        let swapPulse = sinf(swapProgress * .pi)
        let swapDrop = viewmodelSwapTransition * 0.28 + swapPulse * 0.05
        let reloadProgress = max(0.0, min(1.0, 1.0 - viewmodelReloadTransition))
        let reloadPulse = sinf(reloadProgress * .pi)
        let reloadDrop = viewmodelReloadTransition * 0.16 + reloadPulse * 0.08
        let reloadTilt = viewmodelReloadTransition * 0.22 + reloadPulse * 0.68
        let meleeProgress = max(0.0, min(1.0, 1.0 - viewmodelMeleeTransition))
        let meleePulse = sinf(meleeProgress * .pi)
        let meleeSwing = viewmodelMeleeTransition * 0.18 + meleePulse * 0.74
        let opticOffset: Float = (selectedItem.kind == ItemKind_Gun && selectedItem.opticMounted) ? -0.08 : 0.0
        let base = SIMD2<Float>(
            0.42 + aimPosition.x * 0.18 + opticOffset + viewmodelDrift + walkSway * 0.36 + swapDrop * 0.09 - reloadTilt * 0.06,
            0.74 + recoil + abs(sway) * 0.22 + aimPosition.y * 0.08 + walkLift + swapDrop + reloadDrop
        )
        let armLead = SIMD2<Float>(
            walkSway * 0.32 - viewmodelDrift * 0.18 + reloadTilt * 0.04,
            walkLift * 0.18 + reloadDrop * 0.04
        )
        let weaponRotation = -0.05 + viewmodelRoll + walkSway * 0.28 - reloadTilt * 0.44
        let armColor = SIMD4<Float>(0.22, 0.24, 0.24, 0.92)
        let primaryArmOffset = SIMD2<Float>(swapDrop * 0.08, reloadDrop * 0.04)
        let supportArmOffset = SIMD2<Float>(reloadTilt * 0.18 + meleeSwing * 0.08, reloadDrop * 0.06 - meleeSwing * 0.04)
        instances.append(makeInstance(position: SIMD2<Float>(base.x - 0.16, 0.9) + armLead + primaryArmOffset, size: SIMD2<Float>(0.28, 0.22), color: armColor, rotation: 0.2 + viewmodelRoll * 0.5 - reloadTilt * 0.18, shape: .rectangle))
        instances.append(makeInstance(position: SIMD2<Float>(base.x + 0.04, 0.94) + armLead * SIMD2<Float>(0.8, 1.1) + supportArmOffset, size: SIMD2<Float>(0.3, 0.24), color: armColor, rotation: -0.08 - viewmodelRoll * 0.35 - reloadTilt * 0.3 - meleeSwing * 0.12, shape: .rectangle))

        switch selectedItem.kind {
        case ItemKind_Gun:
            let weaponColor = SIMD4<Float>(0.32, 0.35, 0.37, 0.98)
            let accentColor = SIMD4<Float>(0.16, 0.17, 0.18, 0.96)
            let receiverBase = base + SIMD2<Float>(-reloadTilt * 0.08, reloadDrop * 0.04)
            let handguardBase = receiverBase + SIMD2<Float>(0.19, -0.04) + SIMD2<Float>(walkSway * 0.08, -viewmodelKick * 0.05 - reloadTilt * 0.02)
            let magazineBase = receiverBase + SIMD2<Float>(-0.1, 0.08) + SIMD2<Float>(-walkSway * 0.06, walkLift * 0.04)
            let reloadMagazineOffset = SIMD2<Float>(-0.18 * viewmodelReloadTransition + reloadProgress * 0.14, 0.16 * viewmodelReloadTransition + reloadPulse * 0.07)
            let supportMagazineOffset = SIMD2<Float>(-0.26 * viewmodelReloadTransition + reloadProgress * 0.18, 0.24 * viewmodelReloadTransition - reloadPulse * 0.08)
            instances.append(makeInstance(position: receiverBase, size: SIMD2<Float>(0.52, 0.14), color: weaponColor, rotation: weaponRotation, shape: .rectangle))
            instances.append(makeInstance(position: handguardBase, size: SIMD2<Float>(0.34, 0.05), color: accentColor, rotation: weaponRotation + 0.03 - reloadTilt * 0.12, shape: .rectangle))
            instances.append(makeInstance(position: magazineBase + reloadMagazineOffset, size: SIMD2<Float>(0.12, 0.18), color: accentColor, rotation: 0.2 + viewmodelRoll * 0.55 - reloadTilt * 0.54, shape: .rectangle))

            if viewmodelReloadTransition > 0.02 {
                instances.append(
                    makeInstance(
                        position: receiverBase + supportMagazineOffset,
                        size: SIMD2<Float>(0.11, 0.17),
                        color: SIMD4<Float>(0.22, 0.24, 0.26, 0.9),
                        rotation: 0.34 - reloadTilt * 0.22,
                        shape: .rectangle
                    )
                )
            }

            if selectedItem.opticMounted {
                instances.append(makeInstance(position: receiverBase + SIMD2<Float>(0.02, -0.1 - reloadTilt * 0.02), size: SIMD2<Float>(0.12, 0.07), color: SIMD4<Float>(0.22, 0.25, 0.28, 0.96), rotation: weaponRotation * 0.18, shape: .rectangle))
                instances.append(makeInstance(position: receiverBase + SIMD2<Float>(0.14, -0.1 - reloadTilt * 0.02), size: SIMD2<Float>(0.08, 0.07), color: SIMD4<Float>(0.12, 0.14, 0.16, 0.96), rotation: weaponRotation * 0.18, shape: .rectangle))
            }
            if selectedItem.suppressed {
                instances.append(makeInstance(position: receiverBase + SIMD2<Float>(0.39, -0.04), size: SIMD2<Float>(0.14, 0.04), color: SIMD4<Float>(0.17, 0.18, 0.2, 0.94), rotation: weaponRotation + 0.03, shape: .rectangle))
            }
            if selectedItem.laserMounted {
                instances.append(makeInstance(position: receiverBase + SIMD2<Float>(0.1, -0.005), size: SIMD2<Float>(0.08, 0.04), color: SIMD4<Float>(0.18, 0.24, 0.18, 0.94), rotation: weaponRotation * 0.2, shape: .rectangle))
                let laserEmitter = receiverBase + SIMD2<Float>(0.18, -0.02)
                let laserTarget = aimPosition
                let beamVector = laserTarget - laserEmitter
                let beamLength = simd_length(beamVector)
                if beamLength > 0.01 {
                    let beamMidpoint = (laserEmitter + laserTarget) * 0.5
                    let beamRotation = atan2f(beamVector.y, beamVector.x)
                    instances.append(makeInstance(position: beamMidpoint, size: SIMD2<Float>(beamLength, 0.004), color: SIMD4<Float>(0.92, 0.16, 0.16, 0.18), rotation: beamRotation, shape: .rectangle))
                }
                let laserDotSize = max(0.012, 0.03 - min(targetDepth / 2400.0, 0.016))
                instances.append(makeInstance(position: laserTarget, size: SIMD2<Float>(laserDotSize, laserDotSize), color: SIMD4<Float>(0.98, 0.2, 0.18, 0.72), rotation: 0, shape: .circle))
            }
            if selectedItem.lightMounted {
                instances.append(makeInstance(position: receiverBase + SIMD2<Float>(0.13, 0.038), size: SIMD2<Float>(0.06, 0.03), color: SIMD4<Float>(0.72, 0.76, 0.68, 0.96), rotation: 0, shape: .rectangle))
                let beamCenter = SIMD2<Float>(aimPosition.x, max(horizon + 0.14, aimPosition.y + 0.1))
                let hotspotSize = max(0.12, 0.34 - min(targetDepth / 2600.0, 0.12))
                instances.append(makeInstance(position: beamCenter + SIMD2<Float>(0, 0.08), size: SIMD2<Float>(0.92, 0.26), color: SIMD4<Float>(0.92, 0.9, 0.72, 0.06), rotation: 0, shape: .rectangle))
                instances.append(makeInstance(position: beamCenter + SIMD2<Float>(0, 0.02), size: SIMD2<Float>(0.56, 0.18), color: SIMD4<Float>(0.96, 0.94, 0.76, 0.09), rotation: 0, shape: .rectangle))
                instances.append(makeInstance(position: aimPosition, size: SIMD2<Float>(hotspotSize, hotspotSize), color: SIMD4<Float>(0.98, 0.96, 0.84, 0.1), rotation: 0, shape: .circle))
            }
            if selectedItem.underbarrelMounted {
                instances.append(makeInstance(position: receiverBase + SIMD2<Float>(0.03, 0.1), size: SIMD2<Float>(0.06, 0.12), color: SIMD4<Float>(0.2, 0.22, 0.22, 0.96), rotation: 0.02 + viewmodelRoll * 0.2, shape: .rectangle))
            }

            if muzzleFlashIntensity > 0.02 {
                let muzzlePosition = receiverBase + SIMD2<Float>(0.56, -0.04 - viewmodelKick * 0.1)
                let flashAlpha = min(0.9, muzzleFlashIntensity * (selectedItem.suppressed ? 0.34 : 0.82))
                let flashSize = selectedItem.suppressed ? SIMD2<Float>(0.11, 0.08) : SIMD2<Float>(0.18, 0.12)
                instances.append(makeInstance(position: muzzlePosition, size: flashSize, color: SIMD4<Float>(1.0, 0.78, 0.28, flashAlpha), rotation: weaponRotation, shape: .circle))
                instances.append(makeInstance(position: muzzlePosition + SIMD2<Float>(0.04, 0), size: flashSize * SIMD2<Float>(1.6, 0.32), color: SIMD4<Float>(1.0, 0.86, 0.52, flashAlpha * 0.68), rotation: weaponRotation, shape: .rectangle))
                instances.append(makeInstance(position: muzzlePosition, size: flashSize * SIMD2<Float>(0.4, 0.4), color: SIMD4<Float>(1.0, 0.96, 0.84, flashAlpha * 0.84), rotation: 0, shape: .circle))
            }
        case ItemKind_Blade:
            let bladeBase = base + SIMD2<Float>(-meleeSwing * 0.22, -meleeSwing * 0.08)
            let slashRotation = 0.56 + walkSway * 0.24 + viewmodelRoll * 0.4 - meleeSwing * 1.2
            instances.append(makeInstance(position: bladeBase + SIMD2<Float>(0.12 + meleeSwing * 0.18, -0.08 - meleeSwing * 0.18), size: SIMD2<Float>(0.08, 0.34), color: SIMD4<Float>(0.86, 0.88, 0.91, 0.98), rotation: slashRotation, shape: .rectangle))
            instances.append(makeInstance(position: bladeBase + SIMD2<Float>(-0.01, 0.06), size: SIMD2<Float>(0.1, 0.12), color: SIMD4<Float>(0.18, 0.18, 0.19, 0.96), rotation: 0.34 + viewmodelRoll * 0.25 - meleeSwing * 0.4, shape: .rectangle))
            if viewmodelMeleeTransition > 0.02 {
                instances.append(makeInstance(position: bladeBase + SIMD2<Float>(-0.04 + meleeSwing * 0.08, -0.02 - meleeSwing * 0.06), size: SIMD2<Float>(0.22, 0.04), color: SIMD4<Float>(0.92, 0.94, 0.98, 0.16 + meleePulse * 0.08), rotation: slashRotation - 0.18, shape: .rectangle))
                instances.append(makeInstance(position: bladeBase + SIMD2<Float>(0.02 + meleeSwing * 0.12, -0.06 - meleeSwing * 0.1), size: SIMD2<Float>(0.16, 0.03), color: SIMD4<Float>(0.82, 0.86, 0.9, 0.12 + meleePulse * 0.06), rotation: slashRotation - 0.08, shape: .rectangle))
            }
        case ItemKind_Medkit:
            instances.append(makeInstance(position: base + SIMD2<Float>(0.02, 0.03), size: SIMD2<Float>(0.26, 0.18), color: SIMD4<Float>(0.82, 0.24, 0.18, 0.96), rotation: -0.06 + walkSway * 0.16, shape: .rectangle))
            instances.append(makeInstance(position: base + SIMD2<Float>(0.02, 0.03), size: SIMD2<Float>(0.08, 0.04), color: SIMD4<Float>(0.96, 0.94, 0.9, 0.96), rotation: 0, shape: .rectangle))
        default:
            instances.append(makeInstance(position: base + SIMD2<Float>(0.06, 0.01), size: SIMD2<Float>(0.18, 0.14), color: SIMD4<Float>(0.32, 0.38, 0.3, 0.96), rotation: -0.04 + walkSway * 0.12, shape: .rectangle))
        }
    }

    private func buildFirstPersonOcclusionField(statePointer: UnsafePointer<GameState>,
                                                playerPosition: SIMD2<Float>,
                                                forward: SIMD2<Float>,
                                                right: SIMD2<Float>,
                                                horizon: Float,
                                                cameraOffset: Float) -> OcclusionField {
        var field = OcclusionField()

        let structureCount = Int(game_structure_count(statePointer))
        for index in 0..<structureCount {
            guard let structure = game_structure_at(statePointer, index)?.pointee else {
                continue
            }

            let strength = occlusionStrength(for: structure)
            if strength <= 0.05 {
                continue
            }

            guard let screen = projectFootprint(
                worldPosition: SIMD2<Float>(structure.position.x, structure.position.y),
                width: structure.size.x,
                height: firstPersonHeight(for: structure),
                playerPosition: playerPosition,
                forward: forward,
                right: right,
                horizon: horizon,
                cameraOffset: cameraOffset
            ) else {
                continue
            }

            field.register(center: screen.position.x, width: screen.size.x * occlusionWidthScale(for: structure), depth: screen.depth, strength: strength)
        }

        let interactableCount = Int(game_interactable_count(statePointer))
        for index in 0..<interactableCount {
            guard let interactable = game_interactable_at(statePointer, index)?.pointee else {
                continue
            }

            let strength = occlusionStrength(for: interactable)
            if strength <= 0.05 {
                continue
            }

            guard let screen = projectFootprint(
                worldPosition: SIMD2<Float>(interactable.position.x, interactable.position.y),
                width: interactable.size.x,
                height: firstPersonHeight(for: interactable),
                playerPosition: playerPosition,
                forward: forward,
                right: right,
                horizon: horizon,
                cameraOffset: cameraOffset
            ) else {
                continue
            }

            field.register(center: screen.position.x, width: screen.size.x * 1.05, depth: screen.depth, strength: strength)
        }

        return field
    }

    private func occlusionStrength(for structure: Structure) -> Float {
        switch structure.kind {
        case StructureKind_Building:
            return 0.96
        case StructureKind_Convoy:
            return 0.9
        case StructureKind_LowWall:
            return 0.78
        case StructureKind_Door:
            return structure.blocksProjectiles ? 0.74 : 0.18
        case StructureKind_Ridge:
            return 0.72
        case StructureKind_Tower:
            return 0.66
        case StructureKind_TreeCluster:
            return 0.42
        default:
            return 0.0
        }
    }

    private func occlusionWidthScale(for structure: Structure) -> Float {
        switch structure.kind {
        case StructureKind_Ridge, StructureKind_Convoy, StructureKind_Building:
            return 1.18
        case StructureKind_TreeCluster:
            return 1.1
        default:
            return 1.0
        }
    }

    private func occlusionStrength(for interactable: Interactable) -> Float {
        switch interactable.kind {
        case InteractableKind_Door:
            return interactable.toggled ? 0.16 : 0.68
        case InteractableKind_SupplyCrate:
            return 0.34
        case InteractableKind_EmplacedWeapon:
            return 0.24
        case InteractableKind_Radio:
            return 0.18
        default:
            return 0.0
        }
    }

    private func registerFocusOverlay(_ focusOverlay: inout FocusOverlay?,
                                      position: SIMD2<Float>,
                                      size: SIMD2<Float>,
                                      footY: Float,
                                      color: SIMD4<Float>,
                                      depth: Float,
                                      centeredness: Float,
                                      visibility: Float) {
        guard depth < 170, centeredness < 0.68, visibility > 0.22 else {
            return
        }

        let score = depth + centeredness * 180.0
        if let existing = focusOverlay, existing.score <= score {
            return
        }

        focusOverlay = FocusOverlay(position: position, size: size, footY: footY, color: color, score: score)
    }

    private func addFocusOverlay(to instances: inout [RenderInstance], focusOverlay: FocusOverlay) {
        let highlightColor = alphaAdjusted(focusOverlay.color, factor: 1.0, minimumAlpha: 0.18)
        instances.append(makeInstance(position: focusOverlay.position, size: focusOverlay.size * SIMD2<Float>(1.34, 1.18), color: SIMD4<Float>(highlightColor.x, highlightColor.y, highlightColor.z, 0.62), rotation: 0, shape: .ring))
        instances.append(makeInstance(position: SIMD2<Float>(focusOverlay.position.x, focusOverlay.footY + 0.05), size: SIMD2<Float>(max(0.08, focusOverlay.size.x * 0.72), 0.014), color: SIMD4<Float>(highlightColor.x, highlightColor.y, highlightColor.z, 0.7), rotation: 0, shape: .rectangle))
    }

    private func normalizedAim(for player: Player) -> SIMD2<Float> {
        let aim = SIMD2<Float>(player.aim.x, player.aim.y)
        if simd_length_squared(aim) > 0.0001 {
            return simd_normalize(aim)
        }
        return SIMD2<Float>(0, 1)
    }

    private func stanceBobMultiplier(_ stance: Stance) -> Float {
        switch stance {
        case Stance_Prone:
            return 0.35
        case Stance_Crouch:
            return 0.7
        default:
            return 1.0
        }
    }

    private func baseHorizon(for stance: Stance) -> Float {
        switch stance {
        case Stance_Prone:
            return -0.02
        case Stance_Crouch:
            return -0.12
        default:
            return -0.2
        }
    }

    private func currentTerrainTint(statePointer: UnsafePointer<GameState>, playerPosition: SIMD2<Float>) -> SIMD4<Float> {
        let terrainTileCount = Int(game_terrain_tile_count(statePointer))
        for index in 0..<terrainTileCount {
            guard let tile = game_terrain_tile_at(statePointer, index)?.pointee else {
                continue
            }
            let halfWidth = tile.size.x * 0.5
            let halfHeight = tile.size.y * 0.5
            if abs(playerPosition.x - tile.position.x) <= halfWidth && abs(playerPosition.y - tile.position.y) <= halfHeight {
                return terrainColor(tile.material)
            }
        }
        return SIMD4<Float>(0.18, 0.27, 0.15, 0.96)
    }

    private func firstPersonHeight(for structure: Structure) -> Float {
        switch structure.kind {
        case StructureKind_Building:
            return max(structure.size.y * 1.45, 150)
        case StructureKind_Tower:
            return max(structure.size.y * 1.7, 190)
        case StructureKind_TreeCluster:
            return max(structure.size.x * 1.5, 160)
        case StructureKind_Convoy:
            return max(structure.size.y * 1.2, 84)
        case StructureKind_LowWall:
            return max(structure.size.y * 0.82, 48)
        case StructureKind_Door:
            return max(structure.size.y * 1.22, 88)
        case StructureKind_Ridge:
            return max(structure.size.y * 0.8, 120)
        case StructureKind_Road:
            return 26
        default:
            return max(structure.size.y, 60)
        }
    }

    private func firstPersonHeight(for interactable: Interactable) -> Float {
        switch interactable.kind {
        case InteractableKind_Door:
            return max(interactable.size.y * 1.2, 90)
        case InteractableKind_SupplyCrate:
            return 52
        case InteractableKind_DeadDrop:
            return 28
        case InteractableKind_Radio:
            return 72
        case InteractableKind_EmplacedWeapon:
            return 44
        default:
            return 48
        }
    }

    private func firstPersonHeight(for item: WorldItem) -> Float {
        switch item.kind {
        case ItemKind_BulletBox:
            return 18
        case ItemKind_Magazine:
            return 30
        case ItemKind_Gun:
            return 18
        case ItemKind_Blade:
            return 40
        case ItemKind_Attachment:
            return 18
        case ItemKind_Medkit:
            return 24
        case ItemKind_Objective:
            return 28
        default:
            return 20
        }
    }

    private func firstPersonWidth(for item: WorldItem) -> Float {
        switch item.kind {
        case ItemKind_BulletBox:
            return 22
        case ItemKind_Magazine:
            return 14
        case ItemKind_Gun:
            return 42
        case ItemKind_Blade:
            return 12
        case ItemKind_Attachment:
            return 24
        case ItemKind_Medkit:
            return 24
        case ItemKind_Objective:
            return 24
        default:
            return 18
        }
    }

    private func makeWorldUniforms(camera: FirstPersonCameraRig, drawableSize: CGSize) -> World3DUniforms {
        let aspect = max(Float(drawableSize.width / max(drawableSize.height, 1)), 0.5)
        let projection = makePerspectiveMatrix(
            fieldOfViewDegrees: FirstPerson3DConfig.verticalFovDegrees,
            aspectRatio: aspect,
            nearZ: FirstPerson3DConfig.nearPlane,
            farZ: FirstPerson3DConfig.farPlane
        )
        let view = makeLookAtMatrix(
            eye: camera.position,
            center: camera.position + camera.forward,
            up: camera.up
        )

        return World3DUniforms(
            viewProjectionMatrix: projection * view,
            cameraPosition: camera.position,
            fogStart: 6.8,
            lightDirection: simd_normalize(SIMD3<Float>(-0.54, -0.76, 0.32)),
            fogEnd: 29.5,
            fogColor: SIMD4<Float>(0.34, 0.38, 0.34, 1.0),
            sunColor: SIMD4<Float>(1.0, 0.84, 0.66, 1.0),
            ambientColor: SIMD4<Float>(0.4, 0.44, 0.4, 1.0),
            shadowColor: SIMD4<Float>(0.11, 0.13, 0.14, 1.0),
            hazeColor: SIMD4<Float>(0.76, 0.66, 0.5, 1.0)
        )
    }

    private func appendWorldBox(to instances: inout [World3DInstance],
                                position: SIMD3<Float>,
                                size: SIMD3<Float>,
                                color: SIMD4<Float>,
                                yaw: Float = 0,
                                lighting: Float = 1.0) {
        instances.append(
            World3DInstance(
                position: position,
                yaw: yaw,
                size: SIMD3<Float>(max(0.01, size.x), max(0.01, size.y), max(0.01, size.z)),
                lighting: lighting,
                color: color
            )
        )
    }

    private func renderWorldPosition(_ worldPosition: SIMD2<Float>) -> SIMD2<Float> {
        worldPosition * FirstPerson3DConfig.horizontalScale
    }

    private func terrainElevation(at worldPosition: SIMD2<Float>, statePointer: UnsafePointer<GameState>) -> Float {
        let terrainTileCount = Int(game_terrain_tile_count(statePointer))
        for index in 0..<terrainTileCount {
            guard let tile = game_terrain_tile_at(statePointer, index)?.pointee else {
                continue
            }

            let halfWidth = tile.size.x * 0.5
            let halfHeight = tile.size.y * 0.5
            if abs(worldPosition.x - tile.position.x) <= halfWidth && abs(worldPosition.y - tile.position.y) <= halfHeight {
                return tile.height * FirstPerson3DConfig.terrainHeightScale
            }
        }

        return 0
    }

    private func cameraEyeHeight(for stance: Stance) -> Float {
        switch stance {
        case Stance_Prone:
            return 0.58
        case Stance_Crouch:
            return 1.08
        default:
            return 1.62
        }
    }

    private func cameraPitch(for stance: Stance) -> Float {
        switch stance {
        case Stance_Prone:
            return -0.02
        case Stance_Crouch:
            return -0.06
        default:
            return -0.08
        }
    }

    private func makePerspectiveMatrix(fieldOfViewDegrees: Float,
                                       aspectRatio: Float,
                                       nearZ: Float,
                                       farZ: Float) -> simd_float4x4 {
        let fovRadians = fieldOfViewDegrees * (.pi / 180.0)
        let yScale = 1.0 / tanf(fovRadians * 0.5)
        let xScale = yScale / aspectRatio
        let zScale = farZ / (nearZ - farZ)
        let wzScale = (nearZ * farZ) / (nearZ - farZ)

        return simd_float4x4(
            SIMD4<Float>(xScale, 0, 0, 0),
            SIMD4<Float>(0, yScale, 0, 0),
            SIMD4<Float>(0, 0, zScale, -1),
            SIMD4<Float>(0, 0, wzScale, 0)
        )
    }

    private func makeLookAtMatrix(eye: SIMD3<Float>,
                                  center: SIMD3<Float>,
                                  up: SIMD3<Float>) -> simd_float4x4 {
        let forward = simd_normalize(center - eye)
        let side = simd_normalize(simd_cross(up, forward))
        let cameraUp = simd_cross(forward, side)

        return simd_float4x4(
            SIMD4<Float>(side.x, cameraUp.x, -forward.x, 0),
            SIMD4<Float>(side.y, cameraUp.y, -forward.y, 0),
            SIMD4<Float>(side.z, cameraUp.z, -forward.z, 0),
            SIMD4<Float>(-simd_dot(side, eye), -simd_dot(cameraUp, eye), simd_dot(forward, eye), 1)
        )
    }

    private static func makeCubeVertices() -> [World3DVertex] {
        let p000 = SIMD3<Float>(-0.5, -0.5, -0.5)
        let p001 = SIMD3<Float>(-0.5, -0.5, 0.5)
        let p010 = SIMD3<Float>(-0.5, 0.5, -0.5)
        let p011 = SIMD3<Float>(-0.5, 0.5, 0.5)
        let p100 = SIMD3<Float>(0.5, -0.5, -0.5)
        let p101 = SIMD3<Float>(0.5, -0.5, 0.5)
        let p110 = SIMD3<Float>(0.5, 0.5, -0.5)
        let p111 = SIMD3<Float>(0.5, 0.5, 0.5)

        func face(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, _ d: SIMD3<Float>, normal: SIMD3<Float>) -> [World3DVertex] {
            [
                World3DVertex(position: a, normal: normal),
                World3DVertex(position: b, normal: normal),
                World3DVertex(position: c, normal: normal),
                World3DVertex(position: a, normal: normal),
                World3DVertex(position: c, normal: normal),
                World3DVertex(position: d, normal: normal)
            ]
        }

        return
            face(p001, p101, p111, p011, normal: SIMD3<Float>(0, 0, 1)) +
            face(p100, p000, p010, p110, normal: SIMD3<Float>(0, 0, -1)) +
            face(p000, p001, p011, p010, normal: SIMD3<Float>(-1, 0, 0)) +
            face(p101, p100, p110, p111, normal: SIMD3<Float>(1, 0, 0)) +
            face(p010, p011, p111, p110, normal: SIMD3<Float>(0, 1, 0)) +
            face(p000, p100, p101, p001, normal: SIMD3<Float>(0, -1, 0))
    }

    private func alphaAdjusted(_ color: SIMD4<Float>, factor: Float, minimumAlpha: Float) -> SIMD4<Float> {
        var adjusted = color
        adjusted.w = max(minimumAlpha, min(1.0, color.w * factor))
        return adjusted
    }

    private func projectFootprint(worldPosition: SIMD2<Float>,
                                  width: Float,
                                  height: Float,
                                  playerPosition: SIMD2<Float>,
                                  forward: SIMD2<Float>,
                                  right: SIMD2<Float>,
                                  horizon: Float,
                                  cameraOffset: Float) -> PerspectiveProjection? {
        let delta = worldPosition - playerPosition
        let depth = simd_dot(delta, forward)
        guard depth > 28, depth < 1400 else {
            return nil
        }

        let lateral = simd_dot(delta, right)
        let screenX = (lateral / depth) * 1.16 - cameraOffset
        guard abs(screenX) <= 1.45 else {
            return nil
        }

        let scale = 1.55 / max(depth, 1)
        let screenWidth = min(1.7, max(0.02, width * scale))
        let screenHeight = min(1.85, max(0.02, height * scale))
        let footY = horizon + min(0.84, 92 / depth)
        let centerY = footY - screenHeight * 0.5
        return PerspectiveProjection(
            position: SIMD2<Float>(screenX, centerY),
            size: SIMD2<Float>(screenWidth, screenHeight),
            depth: depth,
            footY: footY
        )
    }

    private func makeInstance(position: SIMD2<Float>, size: SIMD2<Float>, color: SIMD4<Float>, rotation: Float, shape: RenderShape) -> RenderInstance {
        RenderInstance(position: position, size: size, color: color, rotation: rotation, shape: shape.rawValue)
    }

    private func mixedColor(_ base: SIMD4<Float>, _ tint: SIMD4<Float>, amount: Float) -> SIMD4<Float> {
        let t = min(max(amount, 0.0), 1.0)
        return SIMD4<Float>(
            base.x + (tint.x - base.x) * t,
            base.y + (tint.y - base.y) * t,
            base.z + (tint.z - base.z) * t,
            base.w + (tint.w - base.w) * t
        )
    }

    private func ammoColor(_ ammoType: AmmoType) -> SIMD4<Float> {
        switch ammoType {
        case AmmoType_556:
            return SIMD4<Float>(0.93, 0.73, 0.22, 1)
        case AmmoType_9mm:
            return SIMD4<Float>(0.9, 0.52, 0.2, 1)
        default:
            return SIMD4<Float>(0.78, 0.8, 0.82, 1)
        }
    }

    private func structurePalette(for kind: StructureKind) -> (primary: SIMD4<Float>, secondary: SIMD4<Float>, accent: SIMD4<Float>) {
        switch kind {
        case StructureKind_Ridge:
            return (
                SIMD4<Float>(0.39, 0.29, 0.19, 0.98),
                SIMD4<Float>(0.58, 0.46, 0.3, 0.94),
                SIMD4<Float>(0.23, 0.18, 0.15, 0.94)
            )
        case StructureKind_Road:
            return (
                SIMD4<Float>(0.21, 0.22, 0.22, 1.0),
                SIMD4<Float>(0.74, 0.69, 0.45, 0.9),
                SIMD4<Float>(0.12, 0.13, 0.14, 0.94)
            )
        case StructureKind_TreeCluster:
            return (
                SIMD4<Float>(0.32, 0.22, 0.14, 0.98),
                SIMD4<Float>(0.23, 0.42, 0.22, 0.96),
                SIMD4<Float>(0.12, 0.25, 0.15, 0.96)
            )
        case StructureKind_Building:
            return (
                SIMD4<Float>(0.58, 0.52, 0.42, 0.99),
                SIMD4<Float>(0.24, 0.29, 0.27, 0.98),
                SIMD4<Float>(0.15, 0.19, 0.2, 0.94)
            )
        case StructureKind_LowWall:
            return (
                SIMD4<Float>(0.74, 0.69, 0.57, 0.99),
                SIMD4<Float>(0.88, 0.82, 0.69, 0.96),
                SIMD4<Float>(0.59, 0.56, 0.45, 0.94)
            )
        case StructureKind_Tower:
            return (
                SIMD4<Float>(0.53, 0.48, 0.37, 0.98),
                SIMD4<Float>(0.25, 0.28, 0.24, 0.98),
                SIMD4<Float>(0.35, 0.31, 0.24, 0.94)
            )
        case StructureKind_Convoy:
            return (
                SIMD4<Float>(0.28, 0.34, 0.29, 0.99),
                SIMD4<Float>(0.14, 0.17, 0.17, 0.98),
                SIMD4<Float>(0.34, 0.41, 0.43, 0.82)
            )
        default:
            return (
                SIMD4<Float>(0.56, 0.56, 0.52, 0.98),
                SIMD4<Float>(0.24, 0.26, 0.26, 0.94),
                SIMD4<Float>(0.16, 0.18, 0.18, 0.92)
            )
        }
    }

    private func terrainColor(_ material: TerrainMaterial) -> SIMD4<Float> {
        switch material {
        case TerrainMaterial_Road:
            return SIMD4<Float>(0.24, 0.24, 0.22, 0.96)
        case TerrainMaterial_Mud:
            return SIMD4<Float>(0.31, 0.2, 0.15, 0.96)
        case TerrainMaterial_Rock:
            return SIMD4<Float>(0.47, 0.41, 0.32, 0.96)
        case TerrainMaterial_Compound:
            return SIMD4<Float>(0.53, 0.47, 0.36, 0.94)
        case TerrainMaterial_Forest:
            return SIMD4<Float>(0.16, 0.27, 0.16, 0.96)
        default:
            return SIMD4<Float>(0.22, 0.31, 0.18, 0.96)
        }
    }

    private func terrainAccentColor(_ material: TerrainMaterial, variation: Float, height: Float) -> SIMD4<Float> {
        let heightTint = min(max(height / 72.0, -0.08), 0.12)
        switch material {
        case TerrainMaterial_Road:
            return SIMD4<Float>(0.34 + heightTint, 0.33 + heightTint * 0.7, 0.3 + variation * 0.04, 0.94)
        case TerrainMaterial_Mud:
            return SIMD4<Float>(0.42 + variation * 0.04, 0.26 + heightTint * 0.5, 0.18 + variation * 0.03, 0.94)
        case TerrainMaterial_Rock:
            return SIMD4<Float>(0.54 + variation * 0.06, 0.48 + heightTint * 0.8, 0.38 + variation * 0.04, 0.95)
        case TerrainMaterial_Compound:
            return SIMD4<Float>(0.62 + heightTint * 0.6, 0.55 + variation * 0.04, 0.43 + variation * 0.03, 0.94)
        case TerrainMaterial_Forest:
            return SIMD4<Float>(0.2 + variation * 0.03, 0.33 + heightTint * 0.6, 0.18 + variation * 0.02, 0.94)
        default:
            return SIMD4<Float>(0.28 + variation * 0.04, 0.38 + heightTint * 0.7, 0.22 + variation * 0.03, 0.94)
        }
    }

    private func terrainSkylineColor(_ material: TerrainMaterial, distance: Float, height: Float) -> SIMD4<Float> {
        let fade = 1.0 - min(max((distance - 9.0) / 31.0, 0.0), 1.0)
        let alpha = max(0.05, 0.18 * fade)
        let heightTint = min(max(height / 88.0, -0.04), 0.08)

        switch material {
        case TerrainMaterial_Rock:
            return SIMD4<Float>(0.29 + heightTint, 0.3 + heightTint, 0.28, alpha)
        case TerrainMaterial_Forest:
            return SIMD4<Float>(0.2, 0.3 + heightTint, 0.2, alpha * 1.08)
        case TerrainMaterial_Compound:
            return SIMD4<Float>(0.34 + heightTint, 0.33 + heightTint * 0.8, 0.28, alpha)
        case TerrainMaterial_Road:
            return SIMD4<Float>(0.22, 0.24, 0.24, alpha * 0.9)
        case TerrainMaterial_Mud:
            return SIMD4<Float>(0.25, 0.2, 0.18, alpha * 0.92)
        default:
            return SIMD4<Float>(0.23, 0.29 + heightTint, 0.21, alpha)
        }
    }

    private func terrainVariationSeed(position: SIMD2<Float>) -> Float {
        let noise = sinf(position.x * 0.011 + position.y * 0.007) + cosf(position.x * 0.005 - position.y * 0.013)
        return min(max((noise + 2.0) * 0.25, 0.0), 1.0)
    }

    private func interactablePalette(kind: InteractableKind,
                                     toggled: Bool,
                                     singleUse: Bool) -> (primary: SIMD4<Float>, secondary: SIMD4<Float>, accent: SIMD4<Float>) {
        let spentFade: Float = (singleUse && toggled) ? 0.45 : 1.0

        switch kind {
        case InteractableKind_Door:
            return (
                SIMD4<Float>(0.7, 0.58, 0.42, toggled ? 0.34 : 0.96),
                SIMD4<Float>(0.3, 0.23, 0.16, 0.94),
                SIMD4<Float>(0.18, 0.14, 0.11, 0.92)
            )
        case InteractableKind_SupplyCrate:
            return (
                SIMD4<Float>(0.43, 0.54, 0.45, 0.92 * spentFade),
                SIMD4<Float>(0.78, 0.79, 0.74, 0.94 * spentFade),
                SIMD4<Float>(0.21, 0.24, 0.2, 0.92 * spentFade)
            )
        case InteractableKind_DeadDrop:
            return (
                SIMD4<Float>(0.54, 0.41, 0.22, 0.92 * spentFade),
                SIMD4<Float>(0.24, 0.19, 0.15, 0.9 * spentFade),
                SIMD4<Float>(0.16, 0.13, 0.1, 0.88 * spentFade)
            )
        case InteractableKind_Radio:
            return (
                SIMD4<Float>(0.42, 0.62, 0.46, 0.92 * spentFade),
                SIMD4<Float>(0.74, 0.78, 0.74, 0.94 * spentFade),
                SIMD4<Float>(0.18, 0.21, 0.18, 0.92 * spentFade)
            )
        case InteractableKind_EmplacedWeapon:
            return (
                SIMD4<Float>(0.42, 0.29, 0.22, 0.9),
                SIMD4<Float>(0.16, 0.17, 0.17, 0.96),
                SIMD4<Float>(0.28, 0.24, 0.19, 0.94)
            )
        default:
            return (
                SIMD4<Float>(0.64, 0.64, 0.62, 0.84),
                SIMD4<Float>(0.28, 0.28, 0.28, 0.88),
                SIMD4<Float>(0.18, 0.18, 0.18, 0.86)
            )
        }
    }

    private func interactableColor(kind: InteractableKind, toggled: Bool, singleUse: Bool) -> SIMD4<Float> {
        interactablePalette(kind: kind, toggled: toggled, singleUse: singleUse).primary
    }

    private func fieldItemColor(_ item: WorldItem) -> SIMD4<Float> {
        switch item.kind {
        case ItemKind_BulletBox:
            return mixedColor(ammoColor(item.ammoType), SIMD4<Float>(0.46, 0.34, 0.18, 0.98), amount: 0.34)
        case ItemKind_Magazine:
            return SIMD4<Float>(0.42, 0.25, 0.16, 0.98)
        case ItemKind_Gun:
            return SIMD4<Float>(0.32, 0.36, 0.35, 0.98)
        case ItemKind_Blade:
            return SIMD4<Float>(0.74, 0.78, 0.8, 0.98)
        case ItemKind_Attachment:
            return SIMD4<Float>(0.3, 0.46, 0.32, 0.98)
        case ItemKind_Medkit:
            return SIMD4<Float>(0.72, 0.18, 0.14, 0.98)
        case ItemKind_Objective:
            return SIMD4<Float>(0.86, 0.76, 0.28, 0.99)
        default:
            return SIMD4<Float>(0.52, 0.56, 0.52, 0.96)
        }
    }
}
