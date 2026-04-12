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
    private let maxInstances = 1024

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
            Float(view.drawableSize.width) * 1.05,
            Float(view.drawableSize.height) * 1.05
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
        instances.reserveCapacity(256)

        addTerrain(to: &instances, camera: camera, worldViewport: worldViewport)

        viewModel.withState { statePointer in
            let extraction = statePointer.pointee.extractionZone
            let extractionColor = statePointer.pointee.victory
                ? SIMD4<Float>(0.4, 0.82, 0.46, 0.6)
                : SIMD4<Float>(0.95, 0.78, 0.2, 0.6)
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
                    instances.append(makeInstance(position: position, size: SIMD2<Float>(36, 14), color: SIMD4<Float>(0.36, 0.82, 0.86, 1), rotation: 0.3, shape: .rectangle))
                case ItemKind_Blade:
                    instances.append(makeInstance(position: position, size: SIMD2<Float>(14, 40), color: SIMD4<Float>(0.85, 0.86, 0.9, 1), rotation: 0.52, shape: .rectangle))
                case ItemKind_Attachment:
                    instances.append(makeInstance(position: position, size: SIMD2<Float>(24, 18), color: SIMD4<Float>(0.28, 0.82, 0.52, 1), rotation: 0.1, shape: .rectangle))
                case ItemKind_Medkit:
                    instances.append(makeInstance(position: position, size: SIMD2<Float>(24, 24), color: SIMD4<Float>(0.92, 0.24, 0.18, 1), rotation: 0, shape: .rectangle))
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
                instances.append(makeInstance(position: position, size: SIMD2<Float>(34, 34), color: SIMD4<Float>(0.72, 0.18 + (0.3 * healthFactor), 0.15, 0.96), rotation: 0, shape: .circle))
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
            let aimRotation = atan2f(aim.y, aim.x)
            let playerColor = statePointer.pointee.missionFailed
                ? SIMD4<Float>(0.52, 0.19, 0.18, 0.85)
                : SIMD4<Float>(0.26, 0.56, 0.9, 0.98)

            instances.append(makeInstance(position: playerPosition, size: SIMD2<Float>(40, 40), color: SIMD4<Float>(0.11, 0.17, 0.2, 0.45), rotation: 0, shape: .ring))
            instances.append(makeInstance(position: playerPosition, size: SIMD2<Float>(30, 30), color: playerColor, rotation: 0, shape: .circle))
            instances.append(makeInstance(position: playerPosition + (aim * 25), size: SIMD2<Float>(34, 8), color: SIMD4<Float>(0.96, 0.87, 0.76, 0.95), rotation: aimRotation, shape: .rectangle))
            instances.append(makeInstance(position: playerPosition + (aim * 90), size: SIMD2<Float>(120, 2), color: SIMD4<Float>(0.3, 0.7, 0.96, 0.25), rotation: aimRotation, shape: .rectangle))
        }

        return instances
    }

    private func addTerrain(to instances: inout [RenderInstance], camera: SIMD2<Float>, worldViewport: SIMD2<Float>) {
        instances.append(
            makeInstance(
                position: camera,
                size: worldViewport * 1.45,
                color: SIMD4<Float>(0.08, 0.13, 0.09, 1),
                rotation: 0,
                shape: .rectangle
            )
        )

        instances.append(
            makeInstance(
                position: camera + SIMD2<Float>(-140, 120),
                size: worldViewport * SIMD2<Float>(0.62, 0.28),
                color: SIMD4<Float>(0.15, 0.2, 0.12, 0.75),
                rotation: -0.3,
                shape: .rectangle
            )
        )
        instances.append(
            makeInstance(
                position: camera + SIMD2<Float>(240, -160),
                size: worldViewport * SIMD2<Float>(0.52, 0.22),
                color: SIMD4<Float>(0.18, 0.14, 0.1, 0.55),
                rotation: 0.4,
                shape: .rectangle
            )
        )

        let spacing: Float = 120
        let xStart = floor((camera.x - worldViewport.x * 0.65) / spacing) * spacing
        let xEnd = ceil((camera.x + worldViewport.x * 0.65) / spacing) * spacing
        let yStart = floor((camera.y - worldViewport.y * 0.65) / spacing) * spacing
        let yEnd = ceil((camera.y + worldViewport.y * 0.65) / spacing) * spacing
        let gridColor = SIMD4<Float>(0.28, 0.34, 0.22, 0.32)

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
}
