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
    var ready: Bool { !calibrating && model.count >= 2 }
    init() { load() }
    private struct Saved: Codable { var tagSize: Float; var edge: Float; var transforms: [Int: [Float]] }
    private func save() {
        let data = Saved(tagSize: tagSize, edge: cubeEdge, transforms: model.mapValues(flatten))
        if let encoded = try? JSONEncoder().encode(data) { UserDefaults.standard.set(encoded, forKey: "McTrackRigidCalibrationV1") }
    }
    private func load() {
        guard let data = UserDefaults.standard.data(forKey: "McTrackRigidCalibrationV1"),
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
        // Each tag's +Z normal points away from its printed face. For a cube, its
        // center lies half an edge length behind that face. Estimate center in
        // root-tag coordinates; use the user-adjustable cube edge for scale.
        var centers = SIMD3<Float>(repeating: 0)
        for pose in rootFromTag.values {
            centers += SIMD3<Float>(pose.columns.3.x, pose.columns.3.y, pose.columns.3.z) - SIMD3<Float>(pose.columns.2.x, pose.columns.2.y, pose.columns.2.z) * (cubeEdge * 0.5)
        }
        centers /= Float(rootFromTag.count)
        var rootFromCube = matrix_identity_float4x4
        rootFromCube.columns.3 = SIMD4<Float>(centers, 1)
        let cubeFromRoot = simd_inverse(rootFromCube)
        model = rootFromTag.mapValues { cubeFromRoot * $0 }
        calibratedEdge = cubeEdge
        calibrating = false
        save()
        return true
    }
    func estimate(_ tags: [LiveMarker]) -> (simd_float4x4, [Int])? {
        guard ready else { return nil }
        let candidates: [(Int, simd_float4x4)] = tags.compactMap { tag in
            guard let cubeFromTag = model[tag.id] else { return nil }
            return (tag.id, tag.transform * simd_inverse(cubeFromTag))
        }
        guard let first = candidates.first else { return nil }
        // Weighted mean of independent face estimates. Reject gross disagreement.
        let positions = candidates.map { SIMD3<Float>($0.1.columns.3.x, $0.1.columns.3.y, $0.1.columns.3.z) }
        let firstPos = SIMD3<Float>(first.1.columns.3.x, first.1.columns.3.y, first.1.columns.3.z)
        let filtered = candidates.filter { simd_length(SIMD3<Float>($0.1.columns.3.x, $0.1.columns.3.y, $0.1.columns.3.z) - firstPos) < max(0.08, cubeEdge) }
        guard !filtered.isEmpty else { return nil }
        var translation = SIMD3<Float>(repeating: 0)
        var orientation = rotationOf(filtered[0].1)
        for (i, pair) in filtered.enumerated() {
            translation += SIMD3<Float>(pair.1.columns.3.x, pair.1.columns.3.y, pair.1.columns.3.z)
            if i > 0 { orientation = simd_slerp(orientation, rotationOf(pair.1), 1 / Float(i + 1)) }
        }
        translation /= Float(filtered.count)
        var pose = simd_float4x4(orientation)
        pose.columns.3 = SIMD4<Float>(translation, 1)
        return (pose, filtered.map { $0.0 })
    }
}
