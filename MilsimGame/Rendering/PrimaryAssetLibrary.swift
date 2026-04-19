import Foundation
@preconcurrency import MetalKit
@preconcurrency import ModelIO
import simd

enum PrimaryAssetID: CaseIterable {
    case characterMatt
    case characterSam
    case characterShaun
    case characterLis
    case assaultRifle
    case bullpup
    case marksmanRifle
    case submachineGun
    case sidearm
    case fieldKnife
    case optic
    case suppressor
    case weaponLight
    case verticalGrip
    case laserModule
    case backpack
    case medkit
    case ammoBox
    case magazine
    case objective
}

struct PrimaryAssetPart {
    let submesh: MTKSubmesh
    let baseColor: SIMD4<Float>
}

struct PrimaryAssetGeometry {
    let mesh: MTKMesh
    let parts: [PrimaryAssetPart]
}

final class PrimaryAssetMesh {
    let geometries: [PrimaryAssetGeometry]
    let boundsSize: SIMD3<Float>
    let preTransform: simd_float4x4

    init(geometries: [PrimaryAssetGeometry],
         boundsSize: SIMD3<Float>,
         preTransform: simd_float4x4) {
        self.geometries = geometries
        self.boundsSize = boundsSize
        self.preTransform = preTransform
    }
}

final class PrimaryAssetLibrary {
    static func makeMetalVertexDescriptor() -> MTLVertexDescriptor {
        let descriptor = MTLVertexDescriptor()
        descriptor.attributes[0].format = .float3
        descriptor.attributes[0].offset = 0
        descriptor.attributes[0].bufferIndex = 0
        descriptor.attributes[1].format = .float3
        descriptor.attributes[1].offset = MemoryLayout<SIMD3<Float>>.stride
        descriptor.attributes[1].bufferIndex = 0
        descriptor.layouts[0].stride = MemoryLayout<SIMD3<Float>>.stride * 2
        return descriptor
    }

    private static func makeModelIOVertexDescriptor() -> MDLVertexDescriptor {
        let descriptor = MTKModelIOVertexDescriptorFromMetal(makeMetalVertexDescriptor())
        (descriptor.attributes[0] as? MDLVertexAttribute)?.name = MDLVertexAttributePosition
        (descriptor.attributes[1] as? MDLVertexAttribute)?.name = MDLVertexAttributeNormal
        return descriptor
    }

    private enum AssetAnchor {
        case center
        case bottomCenter
    }

    private struct AssetSpec {
        let relativePath: String
        let anchor: AssetAnchor
        let baseRotation: SIMD3<Float>
    }

    private static let specs: [PrimaryAssetID: AssetSpec] = [
        .characterMatt: AssetSpec(relativePath: "Characters/Characters_Matt.obj", anchor: .bottomCenter, baseRotation: .zero),
        .characterSam: AssetSpec(relativePath: "Characters/Characters_Sam.obj", anchor: .bottomCenter, baseRotation: .zero),
        .characterShaun: AssetSpec(relativePath: "Characters/Characters_Shaun.obj", anchor: .bottomCenter, baseRotation: .zero),
        .characterLis: AssetSpec(relativePath: "Characters/Characters_Lis.obj", anchor: .bottomCenter, baseRotation: .zero),
        .assaultRifle: AssetSpec(relativePath: "Guns/AssaultRifle_4.obj", anchor: .center, baseRotation: SIMD3<Float>(0, .pi * 0.5, 0)),
        .bullpup: AssetSpec(relativePath: "Guns/Bullpup_2.obj", anchor: .center, baseRotation: SIMD3<Float>(0, .pi * 0.5, 0)),
        .marksmanRifle: AssetSpec(relativePath: "Guns/Rifle.obj", anchor: .center, baseRotation: .zero),
        .submachineGun: AssetSpec(relativePath: "Guns/SMG.obj", anchor: .center, baseRotation: .zero),
        .sidearm: AssetSpec(relativePath: "Guns/Pistol_4.obj", anchor: .center, baseRotation: SIMD3<Float>(0, .pi * 0.5, 0)),
        .fieldKnife: AssetSpec(relativePath: "Props/Knife.obj", anchor: .center, baseRotation: SIMD3<Float>(.pi * 0.5, 0, 0)),
        .optic: AssetSpec(relativePath: "Accessories/Scope_2.obj", anchor: .center, baseRotation: SIMD3<Float>(0, .pi * 0.5, 0)),
        .suppressor: AssetSpec(relativePath: "Accessories/Silencer_long.obj", anchor: .center, baseRotation: SIMD3<Float>(0, .pi * 0.5, 0)),
        .weaponLight: AssetSpec(relativePath: "Accessories/Flashlight.obj", anchor: .center, baseRotation: SIMD3<Float>(0, .pi * 0.5, 0)),
        .verticalGrip: AssetSpec(relativePath: "Accessories/Grip.obj", anchor: .center, baseRotation: SIMD3<Float>(0, .pi * 0.5, -.pi * 0.5)),
        .laserModule: AssetSpec(relativePath: "Props/Battery_Small.obj", anchor: .center, baseRotation: SIMD3<Float>(.pi * 0.5, 0, 0)),
        .backpack: AssetSpec(relativePath: "Props/Backpack.obj", anchor: .center, baseRotation: .zero),
        .medkit: AssetSpec(relativePath: "Props/FirstAidKit_Hard.obj", anchor: .center, baseRotation: SIMD3<Float>(0, .pi * 0.5, 0)),
        .ammoBox: AssetSpec(relativePath: "Props/Matchbox.obj", anchor: .center, baseRotation: SIMD3<Float>(0, 0, .pi * 0.5)),
        .magazine: AssetSpec(relativePath: "Props/Matchbox.obj", anchor: .center, baseRotation: SIMD3<Float>(.pi * 0.5, 0, 0)),
        .objective: AssetSpec(relativePath: "Props/Compass_Open.obj", anchor: .center, baseRotation: SIMD3<Float>(-.pi * 0.5, 0, 0))
    ]

    private let allocator: MTKMeshBufferAllocator
    private var meshes: [PrimaryAssetID: PrimaryAssetMesh] = [:]

    init(device: MTLDevice) throws {
        allocator = MTKMeshBufferAllocator(device: device)

        for assetID in PrimaryAssetID.allCases {
            guard let spec = Self.specs[assetID] else {
                continue
            }
            meshes[assetID] = try loadMesh(assetID: assetID, spec: spec)
        }
    }

    func mesh(for assetID: PrimaryAssetID) -> PrimaryAssetMesh? {
        meshes[assetID]
    }

    private func loadMesh(assetID: PrimaryAssetID, spec: AssetSpec) throws -> PrimaryAssetMesh {
        guard let assetURL = Bundle.main.url(forResource: spec.relativePath, withExtension: nil, subdirectory: "PrimaryAssets") else {
            throw NSError(domain: "PrimaryAssetLibrary", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing bundled asset for \(assetID): \(spec.relativePath)"])
        }

        let modelIOVertexDescriptor = Self.makeModelIOVertexDescriptor()
        let asset = MDLAsset(url: assetURL, vertexDescriptor: modelIOVertexDescriptor, bufferAllocator: allocator)
        let sourceMeshes = asset.childObjects(of: MDLMesh.self) as? [MDLMesh] ?? []
        guard !sourceMeshes.isEmpty else {
            throw NSError(domain: "PrimaryAssetLibrary", code: 2, userInfo: [NSLocalizedDescriptionKey: "No meshes found in \(spec.relativePath)"])
        }

        for mdlMesh in sourceMeshes {
            mdlMesh.addNormals(withAttributeNamed: MDLVertexAttributeNormal, creaseThreshold: 0.35)
            mdlMesh.vertexDescriptor = modelIOVertexDescriptor
        }

        let loadedMeshes = try MTKMesh.newMeshes(asset: asset, device: allocator.device)
        let geometries = zip(loadedMeshes.modelIOMeshes, loadedMeshes.metalKitMeshes).map { mdlMesh, metalMesh in
            let mdlSubmeshes = mdlMesh.submeshes as? [MDLSubmesh] ?? []
            let parts = zip(mdlSubmeshes, metalMesh.submeshes).map { mdlSubmesh, metalSubmesh in
                PrimaryAssetPart(submesh: metalSubmesh, baseColor: Self.baseColor(for: mdlSubmesh))
            }
            return PrimaryAssetGeometry(mesh: metalMesh, parts: parts)
        }

        let (boundsMin, boundsMax) = Self.combinedBounds(for: sourceMeshes)
        let (preTransform, boundsSize) = Self.normalizedTransform(boundsMin: boundsMin, boundsMax: boundsMax, spec: spec)
        return PrimaryAssetMesh(geometries: geometries, boundsSize: boundsSize, preTransform: preTransform)
    }

    private static func baseColor(for submesh: MDLSubmesh) -> SIMD4<Float> {
        guard let property = submesh.material?.property(with: .baseColor) else {
            return SIMD4<Float>(repeating: 1)
        }

        switch property.type {
        case .float3:
            let color = property.float3Value
            return SIMD4<Float>(color.x, color.y, color.z, 1)
        case .float4:
            return property.float4Value
        default:
            return SIMD4<Float>(repeating: 1)
        }
    }

    private static func combinedBounds(for meshes: [MDLMesh]) -> (min: SIMD3<Float>, max: SIMD3<Float>) {
        var minimum = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var maximum = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)

        for mesh in meshes {
            let bounds = mesh.boundingBox
            let meshMin = bounds.minBounds
            let meshMax = bounds.maxBounds
            minimum.x = min(minimum.x, meshMin.x)
            minimum.y = min(minimum.y, meshMin.y)
            minimum.z = min(minimum.z, meshMin.z)
            maximum.x = max(maximum.x, meshMax.x)
            maximum.y = max(maximum.y, meshMax.y)
            maximum.z = max(maximum.z, meshMax.z)
        }

        return (minimum, maximum)
    }

    private static func normalizedTransform(boundsMin: SIMD3<Float>,
                                            boundsMax: SIMD3<Float>,
                                            spec: AssetSpec) -> (transform: simd_float4x4, boundsSize: SIMD3<Float>) {
        let baseRotation = makeEulerRotationMatrix(spec.baseRotation)
        let rotatedCorners = boundingCorners(min: boundsMin, max: boundsMax).map { corner -> SIMD3<Float> in
            let transformed = baseRotation * SIMD4<Float>(corner.x, corner.y, corner.z, 1)
            return SIMD3<Float>(transformed.x, transformed.y, transformed.z)
        }

        var rotatedMin = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var rotatedMax = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        for corner in rotatedCorners {
            rotatedMin = simd_min(rotatedMin, corner)
            rotatedMax = simd_max(rotatedMax, corner)
        }

        let anchorPoint: SIMD3<Float>
        switch spec.anchor {
        case .center:
            anchorPoint = (rotatedMin + rotatedMax) * 0.5
        case .bottomCenter:
            anchorPoint = SIMD3<Float>((rotatedMin.x + rotatedMax.x) * 0.5, rotatedMin.y, (rotatedMin.z + rotatedMax.z) * 0.5)
        }

        let translateToAnchor = makeTranslationMatrix(-anchorPoint)
        let normalizedBounds = simd_max(rotatedMax - rotatedMin, SIMD3<Float>(repeating: 0.001))
        return (translateToAnchor * baseRotation, normalizedBounds)
    }

    private static func boundingCorners(min boundsMin: SIMD3<Float>, max boundsMax: SIMD3<Float>) -> [SIMD3<Float>] {
        [
            SIMD3<Float>(boundsMin.x, boundsMin.y, boundsMin.z),
            SIMD3<Float>(boundsMin.x, boundsMin.y, boundsMax.z),
            SIMD3<Float>(boundsMin.x, boundsMax.y, boundsMin.z),
            SIMD3<Float>(boundsMin.x, boundsMax.y, boundsMax.z),
            SIMD3<Float>(boundsMax.x, boundsMin.y, boundsMin.z),
            SIMD3<Float>(boundsMax.x, boundsMin.y, boundsMax.z),
            SIMD3<Float>(boundsMax.x, boundsMax.y, boundsMin.z),
            SIMD3<Float>(boundsMax.x, boundsMax.y, boundsMax.z)
        ]
    }
}

private func makeEulerRotationMatrix(_ euler: SIMD3<Float>) -> simd_float4x4 {
    makeRotationYMatrix(euler.y) * makeRotationXMatrix(euler.x) * makeRotationZMatrix(euler.z)
}

private func makeTranslationMatrix(_ translation: SIMD3<Float>) -> simd_float4x4 {
    simd_float4x4(
        SIMD4<Float>(1, 0, 0, 0),
        SIMD4<Float>(0, 1, 0, 0),
        SIMD4<Float>(0, 0, 1, 0),
        SIMD4<Float>(translation.x, translation.y, translation.z, 1)
    )
}

private func makeRotationXMatrix(_ angle: Float) -> simd_float4x4 {
    let s = sinf(angle)
    let c = cosf(angle)
    return simd_float4x4(
        SIMD4<Float>(1, 0, 0, 0),
        SIMD4<Float>(0, c, s, 0),
        SIMD4<Float>(0, -s, c, 0),
        SIMD4<Float>(0, 0, 0, 1)
    )
}

private func makeRotationYMatrix(_ angle: Float) -> simd_float4x4 {
    let s = sinf(angle)
    let c = cosf(angle)
    return simd_float4x4(
        SIMD4<Float>(c, 0, -s, 0),
        SIMD4<Float>(0, 1, 0, 0),
        SIMD4<Float>(s, 0, c, 0),
        SIMD4<Float>(0, 0, 0, 1)
    )
}

private func makeRotationZMatrix(_ angle: Float) -> simd_float4x4 {
    let s = sinf(angle)
    let c = cosf(angle)
    return simd_float4x4(
        SIMD4<Float>(c, s, 0, 0),
        SIMD4<Float>(-s, c, 0, 0),
        SIMD4<Float>(0, 0, 1, 0),
        SIMD4<Float>(0, 0, 0, 1)
    )
}
