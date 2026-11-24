import Foundation
import simd

struct RigidSample: Codable {
    let elapsedSeconds: Double
    let arTimestamp: Double
    let rigidToOrigin: [Float]
    let visibleTagIDs: [Int]
}
struct RigidFile: Codable {
    let format: String
    let tagSizeMeters: Double
    let cubeEdgeMeters: Double
    let tagIDs: [Int]
    let samples: [RigidSample]
    let calibrationStatus: String
    let cubeFromTag: [Int: [Float]]
}

// All methods called from TrackingStore's serial AR frame queue.
// A graph of simultaneous face detections establishes relative tag transforms;
// the cube may move during calibration because only SAME-FRAME relative poses are used.
private func rotationOf(_ m: simd_float4x4) -> simd_quatf {
    simd_quatf(simd_float3x3(columns: (SIMD3<Float>(m.columns.0.x, m.columns.0.y, m.columns.0.z), SIMD3<Float>(m.columns.1.x, m.columns.1.y, m.columns.1.z), SIMD3<Float>(m.columns.2.x, m.columns.2.y, m.columns.2.z))))
}

final class RigidTracking {
    struct Edge { var transform: simd_float4x4; var count: Int }
    var calibrating = false
    private(set) var model: [Int: simd_float4x4] = [:] // cubeFromTag
    private var edges: [Int: [Int: Edge]] = [:] // tagAFromTagB
    private var seen = Set<Int>()
    private(set) var calibratedEdge: Float = 0.09
    var cubeEdge: Float = 0.09
    var tagSize: Float = 0.075
    var observedIDs: [Int] { seen.sorted() }
    var ready: Bool { !calibrating && model.count >= 5 }
    var connectedCount: Int {
        guard let root = seen.sorted().first else { return 0 }
        var visited: Set<Int> = [root]
        var pending = [root]
        while let current = pending.popLast() {
            for (other, edge) in edges[current] ?? [:] where edge.count >= 3 && !visited.contains(other) {
                visited.insert(other); pending.append(other)
            }
        }
        return visited.count
    }
    var canFinish: Bool { calibrating && seen.count >= 5 && connectedCount >= seen.count }
    init() { load() }
    private struct Saved: Codable { var tagSize: Float; var edge: Float; var transforms: [Int: [Float]] }
    private func save() {
        let data = Saved(tagSize: tagSize, edge: cubeEdge, transforms: model.mapValues(flatten))
        if let encoded = try? JSONEncoder().encode(data) { UserDefaults.standard.set(encoded, forKey: "McTrackRigidCalibrationV2") }
    }
    private func load() {
        guard let data = UserDefaults.standard.data(forKey: "McTrackRigidCalibrationV2"),
              let saved = try? JSONDecoder().decode(Saved.self, from: data) else { return }
        tagSize = saved.tagSize; cubeEdge = saved.edge; calibratedEdge = saved.edge
        model = saved.transforms.compactMapValues { values in
            guard values.count == 16 else { return nil }
            return simd_float4x4(columns: (
                SIMD4<Float>(values[0],values[1],values[2],values[3]),
                SIMD4<Float>(values[4],values[5],values[6],values[7]),
                SIMD4<Float>(values[8],values[9],values[10],values[11]),
                SIMD4<Float>(values[12],values[13],values[14],values[15])))
        }
        seen = Set(model.keys)
    }

    func invalidate() { model.removeAll(); edges.removeAll(); seen.removeAll(); calibrating = false; UserDefaults.standard.removeObject(forKey: "McTrackRigidCalibrationV2") }
    func start() { calibrating = true; model.removeAll(); edges.removeAll(); seen.removeAll() }
    func cancel() { calibrating = false }
    func updateCalibration(_ tags: [LiveMarker]) {
        guard calibrating else { return }
        for tag in tags { seen.insert(tag.id) }
        guard tags.count >= 2 else { return }
        for a in tags {
            for b in tags where a.id != b.id {
                let relative = simd_inverse(a.transform) * b.transform
                // Running translation and rotation average in quaternion space, with outlier rejection.
                var edge = edges[a.id]?[b.id] ?? Edge(transform: relative, count: 0)
                let distance = simd_length(SIMD3<Float>(relative.columns.3.x, relative.columns.3.y, relative.columns.3.z) - SIMD3<Float>(edge.transform.columns.3.x, edge.transform.columns.3.y, edge.transform.columns.3.z))
                if edge.count > 3 && distance > max(0.04, cubeEdge * 0.45) { continue }
                let weight = 1.0 / Float(min(edge.count + 1, 60))
                let t = simd_mix(SIMD3<Float>(edge.transform.columns.3.x, edge.transform.columns.3.y, edge.transform.columns.3.z), SIMD3<Float>(relative.columns.3.x, relative.columns.3.y, relative.columns.3.z), SIMD3<Float>(repeating: weight))
                let qOld = rotationOf(edge.transform)
                let qNew = rotationOf(relative)
                let q = simd_slerp(qOld, qNew, weight)
                edge.transform = simd_float4x4(q)
                edge.transform.columns.3 = SIMD4<Float>(t, 1)
                edge.count += 1
                edges[a.id, default: [:]][b.id] = edge
            }
        }
    }
    func finish() -> Bool {
        guard calibrating else { return ready }
        guard let root = seen.sorted().first else { return false }
        var rootFromTag: [Int: simd_float4x4] = [root: matrix_identity_float4x4]
        var pending = [root]
        while !pending.isEmpty {
            let current = pending.removeFirst()
            guard let adjacent = edges[current], let rootFromCurrent = rootFromTag[current] else { continue }
            for (other, edge) in adjacent where edge.count >= 3 && rootFromTag[other] == nil {
                rootFromTag[other] = rootFromCurrent * edge.transform
                pending.append(other)
            }
        }
        guard rootFromTag.count >= 5 else { return false }
        // Opposite face spacing is the known physical cube edge. Estimate the
        // effective detector-boundary size from both opposing pairs.
        let ordered = rootFromTag.sorted { $0.key < $1.key }
        var spacings: [Float] = []
        for i in ordered.indices {
            for j in ordered.indices where j > i {
                let a = ordered[i].value, b = ordered[j].value
                let na = SIMD3<Float>(a.columns.2.x,a.columns.2.y,a.columns.2.z)
                let nb = SIMD3<Float>(b.columns.2.x,b.columns.2.y,b.columns.2.z)
                if simd_dot(na,nb) < -0.90 {
                    let d = SIMD3<Float>(a.columns.3.x-b.columns.3.x,a.columns.3.y-b.columns.3.y,a.columns.3.z-b.columns.3.z)
                    spacings.append(abs(simd_dot(d,simd_normalize(na-nb))))
                }
            }
        }
        if spacings.count == 2 {
            let mean = (spacings[0]+spacings[1])*0.5
            if mean > 0.001 && abs(spacings[0]-spacings[1])/mean < 0.15 {
                let factor = cubeEdge/mean
                if factor >= 0.35 && factor <= 1.5 {
                    tagSize *= factor
                    rootFromTag = rootFromTag.mapValues { m in
                        var scaled = m
                        scaled.columns.3 = SIMD4<Float>(m.columns.3.x*factor,m.columns.3.y*factor,m.columns.3.z*factor,1)
                        return scaled
                    }
                }
            }
        }
        // Each tag's +Z normal points away from its printed face. For a cube, its
        // center lies half an edge length behind that face. Estimate center in
        // root-tag coordinates; use the user-adjustable cube edge for scale.
        var centers = SIMD3<Float>(repeating: 0)
        for pose in rootFromTag.values {
            centers += SIMD3<Float>(pose.columns.3.x, pose.columns.3.y, pose.columns.3.z) - SIMD3<Float>(pose.columns.2.x, pose.columns.2.y, pose.columns.2.z) * (cubeEdge * 0.5)
        }
        centers /= Float(rootFromTag.count)
        // Identify the unpaired outward normal, then construct an orthonormal cube basis.
        let faces = rootFromTag.sorted { $0.key < $1.key }
        func normal(_ m: simd_float4x4) -> SIMD3<Float> { simd_normalize(SIMD3<Float>(m.columns.2.x,m.columns.2.y,m.columns.2.z)) }
        guard let top = faces.max(by: { a,b in
            let na = normal(a.value), nb = normal(b.value)
            return (faces.map { simd_dot(na, normal($0.value)) }.min() ?? -1) < (faces.map { simd_dot(nb, normal($0.value)) }.min() ?? -1)
        }) else { return false }
        let z = normal(top.value)
        guard let side = faces.first(where: { abs(simd_dot(normal($0.value), z)) < 0.5 }) else { return false }
        let sideNormal = normal(side.value)
        let x = simd_normalize(sideNormal - z * simd_dot(sideNormal,z))
        let y = simd_normalize(simd_cross(z,x))
        // Fit center using face planes, not tag centers: in-plane placement errors do not shift the cube.
        var lhs = simd_float3x3(diagonal: SIMD3<Float>(repeating: 0))
        var rhs = SIMD3<Float>(repeating: 0)
        for face in faces {
            let n = normal(face.value)
            let p = SIMD3<Float>(face.value.columns.3.x,face.value.columns.3.y,face.value.columns.3.z)
            lhs += simd_float3x3(columns: (n*n.x,n*n.y,n*n.z))
            rhs += n * (simd_dot(n,p) - cubeEdge * 0.5)
        }
        if abs(simd_determinant(lhs)) > 0.01 { centers = simd_inverse(lhs) * rhs }
        var rootFromCube = simd_float4x4(columns: (SIMD4<Float>(x,0), SIMD4<Float>(y,0), SIMD4<Float>(z,0), SIMD4<Float>(centers,1)))
        let cubeFromRoot = simd_inverse(rootFromCube)
        model = rootFromTag.mapValues { cubeFromRoot * $0 }
        calibratedEdge = cubeEdge
        calibrating = false
        save()
        return true
    }
    func estimate(_ tags: [LiveMarker]) -> (simd_float4x4, [Int])? {
        guard ready else { return nil }
        let candidates: [(Int, simd_float4x4, Float)] = tags.compactMap { tag in
            guard let cubeFromTag = model[tag.id] else { return nil }
            return (tag.id, tag.transform * simd_inverse(cubeFromTag), tag.weight)
        }
        guard !candidates.isEmpty else { return nil }
        func position(_ m: simd_float4x4) -> SIMD3<Float> { SIMD3<Float>(m.columns.3.x,m.columns.3.y,m.columns.3.z) }
        let threshold = max(0.025, cubeEdge * 0.45)
        func agrees(_ a: simd_float4x4, _ b: simd_float4x4) -> Bool {
            simd_length(position(a)-position(b)) < threshold && abs(simd_dot(rotationOf(a).vector, rotationOf(b).vector)) > 0.94
        }
        let ranked = candidates.sorted { a,b in
            let ac = candidates.filter { agrees(a.1,$0.1) }.count
            let bc = candidates.filter { agrees(b.1,$0.1) }.count
            return ac == bc ? a.2 > b.2 : ac > bc
        }
        guard let best = ranked.first else { return nil }
        let filtered = ranked.filter { agrees(best.1,$0.1) }
        var translation = SIMD3<Float>(repeating: 0)
        var orientation = rotationOf(best.1)
        var total: Float = 0
        for pair in filtered {
            let w = pair.2
            translation += position(pair.1) * w
            orientation = simd_slerp(orientation, rotationOf(pair.1), w / (total + w))
            total += w
        }
        guard total > 0 else { return nil }
        translation /= total
        var pose = simd_float4x4(orientation)
        pose.columns.3 = SIMD4<Float>(translation, 1)
        return (pose, filtered.map { $0.0 })
    }
}
