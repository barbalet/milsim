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

        let worldViewport = SIMD2<Float>(
            Float(view.drawableSize.width) * 1.08,
            Float(view.drawableSize.height) * 1.08
        )

        let input = inputController.makeInput(viewSize: view.bounds.size, worldViewport: worldViewport)
        viewModel.step(input: input, dt: deltaTime)
        let camera = viewModel.currentPlayerPosition()

        var uniforms = RenderUniforms(camera: camera, worldViewport: worldViewport)
        memcpy(uniformsBuffer.contents(), &uniforms, MemoryLayout<RenderUniforms>.stride)

        let instances = buildInstances(viewModel: viewModel, camera: camera, worldViewport: worldViewport)
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

    private func buildInstances(viewModel: GameViewModel, camera: SIMD2<Float>, worldViewport: SIMD2<Float>) -> [RenderInstance] {
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
