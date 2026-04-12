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

final class GameRenderer: NSObject, MTKViewDelegate {
    weak var viewModel: GameViewModel?

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private let quadVertexBuffer: MTLBuffer
    private let instanceBuffer: MTLBuffer
    private let uniformsBuffer: MTLBuffer
    private let inputController: InputController

    private var lastFrameTime: CFTimeInterval?
    private let maxInstances = 1400

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
            let fragmentFunction = library.makeFunction(name: "instancedFragment")
        else {
            fatalError("Unable to load Metal shader functions.")
        }

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.label = "MilsimGamePipeline"
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
        pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        do {
            pipelineState = try self.device.makeRenderPipelineState(descriptor: pipelineDescriptor)
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

        guard
            let quadVertexBuffer = self.device.makeBuffer(bytes: quadVertices, length: MemoryLayout<SIMD2<Float>>.stride * quadVertices.count),
            let instanceBuffer = self.device.makeBuffer(length: MemoryLayout<RenderInstance>.stride * maxInstances),
            let uniformsBuffer = self.device.makeBuffer(length: MemoryLayout<RenderUniforms>.stride)
        else {
            fatalError("Unable to allocate Metal buffers.")
        }

        self.quadVertexBuffer = quadVertexBuffer
        self.instanceBuffer = instanceBuffer
        self.uniformsBuffer = uniformsBuffer

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

        let simulationViewport = SIMD2<Float>(
            Float(view.drawableSize.width) * 1.08,
            Float(view.drawableSize.height) * 1.08
        )

        let input = inputController.makeInput(viewSize: view.bounds.size, worldViewport: simulationViewport)
        viewModel.step(input: input, dt: deltaTime)
        let firstPersonPresentation = viewModel.isFirstPersonPresentation()
        let camera = firstPersonPresentation ? .zero : viewModel.currentPlayerPosition()
        let renderViewport = firstPersonPresentation ? SIMD2<Float>(2, 2) : simulationViewport

        var uniforms = RenderUniforms(camera: camera, worldViewport: renderViewport)
        memcpy(uniformsBuffer.contents(), &uniforms, MemoryLayout<RenderUniforms>.stride)

        let instances = firstPersonPresentation
            ? buildFirstPersonInstances(viewModel: viewModel)
            : buildTopDownInstances(viewModel: viewModel, camera: camera, worldViewport: renderViewport)
        let instanceCount = min(instances.count, maxInstances)
        if instanceCount > 0 {
            let compactInstances = Array(instances.prefix(instanceCount))
            compactInstances.withUnsafeBytes { rawBuffer in
                guard let baseAddress = rawBuffer.baseAddress else {
                    return
                }
                memcpy(instanceBuffer.contents(), baseAddress, rawBuffer.count)
            }
        }

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }

        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBuffer(quadVertexBuffer, offset: 0, index: 0)
        encoder.setVertexBuffer(instanceBuffer, offset: 0, index: 1)
        encoder.setVertexBuffer(uniformsBuffer, offset: 0, index: 2)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: instanceCount)
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
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

            addFirstPersonReticle(
                to: &instances,
                player: player,
                selectedItem: selectedItem,
                cameraOffset: cameraOffset
            )
            addWeaponViewModel(
                to: &instances,
                statePointer: statePointer,
                sway: sway,
                cameraOffset: cameraOffset,
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
        let skyColor = SIMD4<Float>(0.16, 0.22, 0.28, 1)
        let hazeColor = SIMD4<Float>(0.54, 0.58, 0.44, 0.14)
        let groundColor = SIMD4<Float>(
            min(terrainColor.x + 0.04, 1),
            min(terrainColor.y + 0.02, 1),
            min(terrainColor.z + 0.01, 1),
            1
        )
        let horizonBand = SIMD4<Float>(0.42, 0.39, 0.27, 0.6)

        instances.append(makeInstance(position: SIMD2<Float>(0, -0.66), size: SIMD2<Float>(2.6, 1.25), color: skyColor, rotation: 0, shape: .rectangle))
        instances.append(makeInstance(position: SIMD2<Float>(0.22, horizon - 0.18), size: SIMD2<Float>(2.3, 0.42), color: hazeColor, rotation: 0, shape: .rectangle))
        instances.append(makeInstance(position: SIMD2<Float>(0, horizon + 0.82), size: SIMD2<Float>(2.6, 1.42), color: groundColor, rotation: 0, shape: .rectangle))
        instances.append(makeInstance(position: SIMD2<Float>(0, horizon + 0.02), size: SIMD2<Float>(2.2, 0.05), color: horizonBand, rotation: 0, shape: .rectangle))
        instances.append(makeInstance(position: SIMD2<Float>(-0.72, horizon - 0.28), size: SIMD2<Float>(0.5, 0.18), color: SIMD4<Float>(0.3, 0.36, 0.29, 0.46), rotation: 0, shape: .rectangle))
        instances.append(makeInstance(position: SIMD2<Float>(0.68, horizon - 0.24), size: SIMD2<Float>(0.76, 0.22), color: SIMD4<Float>(0.26, 0.31, 0.26, 0.38), rotation: 0, shape: .rectangle))

        let floorBands: [Float] = [0.18, 0.3, 0.44, 0.6, 0.78, 0.98]
        for (index, bandY) in floorBands.enumerated() {
            let alpha = max(0.08, 0.24 - Float(index) * 0.022)
            let width = 2.1 - Float(index) * 0.1
            let height = 0.018 + Float(index) * 0.006
            instances.append(
                makeInstance(
                    position: SIMD2<Float>(sway * 0.35, horizon + bandY),
                    size: SIMD2<Float>(width, height),
                    color: SIMD4<Float>(0.08, 0.1, 0.08, alpha),
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
                                       cameraOffset: Float) {
        let center = SIMD2<Float>(-cameraOffset * 0.1, 0.02 + min(player.fireCooldown * 0.18, 0.02))
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
                                    cameraOffset: Float,
                                    horizon: Float,
                                    targetDepth: Float) {
        let selectedIndex = Int(game_selected_inventory_index(statePointer))
        guard selectedIndex >= 0, let selectedItem = game_inventory_item_at(statePointer, selectedIndex)?.pointee else {
            return
        }

        let player = statePointer.pointee.player
        let recoil = min(0.12, player.fireCooldown * 0.38)
        let opticOffset: Float = (selectedItem.kind == ItemKind_Gun && selectedItem.opticMounted) ? -0.08 : 0.0
        let base = SIMD2<Float>(0.42 + cameraOffset * 0.55 + opticOffset, 0.74 + recoil + abs(sway) * 0.22)
        let armColor = SIMD4<Float>(0.22, 0.24, 0.24, 0.92)
        instances.append(makeInstance(position: SIMD2<Float>(base.x - 0.16, 0.9), size: SIMD2<Float>(0.28, 0.22), color: armColor, rotation: 0.2, shape: .rectangle))
        instances.append(makeInstance(position: SIMD2<Float>(base.x + 0.04, 0.94), size: SIMD2<Float>(0.3, 0.24), color: armColor, rotation: -0.08, shape: .rectangle))

        switch selectedItem.kind {
        case ItemKind_Gun:
            let weaponColor = SIMD4<Float>(0.32, 0.35, 0.37, 0.98)
            let accentColor = SIMD4<Float>(0.16, 0.17, 0.18, 0.96)
            instances.append(makeInstance(position: base, size: SIMD2<Float>(0.52, 0.14), color: weaponColor, rotation: -0.05, shape: .rectangle))
            instances.append(makeInstance(position: base + SIMD2<Float>(0.19, -0.04), size: SIMD2<Float>(0.34, 0.05), color: accentColor, rotation: -0.02, shape: .rectangle))
            instances.append(makeInstance(position: base + SIMD2<Float>(-0.1, 0.08), size: SIMD2<Float>(0.12, 0.18), color: accentColor, rotation: 0.2, shape: .rectangle))

            if selectedItem.opticMounted {
                instances.append(makeInstance(position: base + SIMD2<Float>(0.02, -0.1), size: SIMD2<Float>(0.12, 0.07), color: SIMD4<Float>(0.22, 0.25, 0.28, 0.96), rotation: 0, shape: .rectangle))
                instances.append(makeInstance(position: base + SIMD2<Float>(0.14, -0.1), size: SIMD2<Float>(0.08, 0.07), color: SIMD4<Float>(0.12, 0.14, 0.16, 0.96), rotation: 0, shape: .rectangle))
            }
            if selectedItem.suppressed {
                instances.append(makeInstance(position: base + SIMD2<Float>(0.39, -0.04), size: SIMD2<Float>(0.14, 0.04), color: SIMD4<Float>(0.17, 0.18, 0.2, 0.94), rotation: -0.02, shape: .rectangle))
            }
            if selectedItem.laserMounted {
                instances.append(makeInstance(position: base + SIMD2<Float>(0.1, -0.005), size: SIMD2<Float>(0.08, 0.04), color: SIMD4<Float>(0.18, 0.24, 0.18, 0.94), rotation: 0, shape: .rectangle))
                let laserTarget = SIMD2<Float>(-cameraOffset * 0.1, 0.02)
                let beamVector = laserTarget - (base + SIMD2<Float>(0.18, -0.02))
                let beamLength = simd_length(beamVector)
                if beamLength > 0.01 {
                    let beamMidpoint = (base + SIMD2<Float>(0.18, -0.02) + laserTarget) * 0.5
                    let beamRotation = atan2f(beamVector.y, beamVector.x)
                    instances.append(makeInstance(position: beamMidpoint, size: SIMD2<Float>(beamLength, 0.004), color: SIMD4<Float>(0.92, 0.16, 0.16, 0.18), rotation: beamRotation, shape: .rectangle))
                }
                let laserDotSize = max(0.012, 0.03 - min(targetDepth / 2400.0, 0.016))
                instances.append(makeInstance(position: laserTarget, size: SIMD2<Float>(laserDotSize, laserDotSize), color: SIMD4<Float>(0.98, 0.2, 0.18, 0.72), rotation: 0, shape: .circle))
            }
            if selectedItem.lightMounted {
                instances.append(makeInstance(position: base + SIMD2<Float>(0.13, 0.038), size: SIMD2<Float>(0.06, 0.03), color: SIMD4<Float>(0.72, 0.76, 0.68, 0.96), rotation: 0, shape: .rectangle))
                let beamCenter = SIMD2<Float>(-cameraOffset * 0.12, max(horizon + 0.14, 0.08))
                let hotspotSize = max(0.12, 0.34 - min(targetDepth / 2600.0, 0.12))
                instances.append(makeInstance(position: beamCenter + SIMD2<Float>(0, 0.08), size: SIMD2<Float>(0.92, 0.26), color: SIMD4<Float>(0.92, 0.9, 0.72, 0.06), rotation: 0, shape: .rectangle))
                instances.append(makeInstance(position: beamCenter + SIMD2<Float>(0, 0.02), size: SIMD2<Float>(0.56, 0.18), color: SIMD4<Float>(0.96, 0.94, 0.76, 0.09), rotation: 0, shape: .rectangle))
                instances.append(makeInstance(position: SIMD2<Float>(-cameraOffset * 0.08, 0.03), size: SIMD2<Float>(hotspotSize, hotspotSize), color: SIMD4<Float>(0.98, 0.96, 0.84, 0.1), rotation: 0, shape: .circle))
            }
            if selectedItem.underbarrelMounted {
                instances.append(makeInstance(position: base + SIMD2<Float>(0.03, 0.1), size: SIMD2<Float>(0.06, 0.12), color: SIMD4<Float>(0.2, 0.22, 0.22, 0.96), rotation: 0.02, shape: .rectangle))
            }

            if player.fireCooldown > 0.02 {
                instances.append(makeInstance(position: base + SIMD2<Float>(0.56, -0.04), size: SIMD2<Float>(0.12, 0.08), color: SIMD4<Float>(0.96, 0.74, 0.22, 0.32), rotation: 0, shape: .circle))
            }
        case ItemKind_Blade:
            instances.append(makeInstance(position: base + SIMD2<Float>(0.12, -0.08), size: SIMD2<Float>(0.08, 0.34), color: SIMD4<Float>(0.86, 0.88, 0.91, 0.98), rotation: 0.56, shape: .rectangle))
            instances.append(makeInstance(position: base + SIMD2<Float>(-0.01, 0.06), size: SIMD2<Float>(0.1, 0.12), color: SIMD4<Float>(0.18, 0.18, 0.19, 0.96), rotation: 0.34, shape: .rectangle))
        case ItemKind_Medkit:
            instances.append(makeInstance(position: base + SIMD2<Float>(0.02, 0.03), size: SIMD2<Float>(0.26, 0.18), color: SIMD4<Float>(0.82, 0.24, 0.18, 0.96), rotation: -0.06, shape: .rectangle))
            instances.append(makeInstance(position: base + SIMD2<Float>(0.02, 0.03), size: SIMD2<Float>(0.08, 0.04), color: SIMD4<Float>(0.96, 0.94, 0.9, 0.96), rotation: 0, shape: .rectangle))
        default:
            instances.append(makeInstance(position: base + SIMD2<Float>(0.06, 0.01), size: SIMD2<Float>(0.18, 0.14), color: SIMD4<Float>(0.32, 0.38, 0.3, 0.96), rotation: -0.04, shape: .rectangle))
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

    private func terrainColor(_ material: TerrainMaterial) -> SIMD4<Float> {
        switch material {
        case TerrainMaterial_Road:
            return SIMD4<Float>(0.26, 0.27, 0.25, 0.96)
        case TerrainMaterial_Mud:
            return SIMD4<Float>(0.34, 0.22, 0.16, 0.96)
        case TerrainMaterial_Rock:
            return SIMD4<Float>(0.41, 0.37, 0.28, 0.96)
        case TerrainMaterial_Compound:
            return SIMD4<Float>(0.48, 0.43, 0.34, 0.94)
        case TerrainMaterial_Forest:
            return SIMD4<Float>(0.12, 0.28, 0.14, 0.96)
        default:
            return SIMD4<Float>(0.18, 0.27, 0.15, 0.96)
        }
    }

    private func interactableColor(kind: InteractableKind, toggled: Bool, singleUse: Bool) -> SIMD4<Float> {
        let spentFade: Float = (singleUse && toggled) ? 0.45 : 1.0

        switch kind {
        case InteractableKind_Door:
            return SIMD4<Float>(0.81, 0.74, 0.58, toggled ? 0.32 : 0.9)
        case InteractableKind_SupplyCrate:
            return SIMD4<Float>(0.28, 0.58, 0.86, 0.92 * spentFade)
        case InteractableKind_DeadDrop:
            return SIMD4<Float>(0.92, 0.72, 0.24, 0.92 * spentFade)
        case InteractableKind_Radio:
            return SIMD4<Float>(0.34, 0.82, 0.46, 0.92 * spentFade)
        case InteractableKind_EmplacedWeapon:
            return SIMD4<Float>(0.76, 0.28, 0.22, 0.9)
        default:
            return SIMD4<Float>(0.8, 0.8, 0.8, 0.8)
        }
    }
}
