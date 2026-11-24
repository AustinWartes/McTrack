import Foundation
import ARKit
import CoreVideo
import simd

struct MarkerObservation: Codable {
    let id: Int
    let elapsedSeconds: Double
    let arTimestamp: Double
    let markerToOrigin: [Float]
    let decisionMargin: Float
    let sensorCorners: [Float]
}
struct MarkerFile: Codable {
    let format: String
    let family: String
    let tagSizeMeters: Double
    let coordinateSystem: String
    let observations: [MarkerObservation]
}
struct LiveMarker {
    let weight: Float
    let id: Int
    let transform: simd_float4x4
}

// Own and call the native detector on a single serial queue, never on the render thread.
final class TagTracking {
    private let detector: UnsafeMutableRawPointer?
    private var lastScan: TimeInterval = -1
    var tagSize: Double = 0.0889  // Printed AprilTag detection boundary, not paper width.
    init() { detector = mc_tag_create() }
    deinit { if let detector { mc_tag_destroy(detector) } }

    func detect(frame: ARFrame, origin: simd_float4x4, elapsed: Double?) -> ([LiveMarker], [MarkerObservation])? {
        // nil = scan skipped; empty arrays = completed scan without detections.
        guard let detector else { return nil }
        guard lastScan < 0 || frame.timestamp - lastScan >= 1.0 / 31.0 else { return nil }
        lastScan = frame.timestamp
        let pixel = frame.capturedImage
        guard CVPixelBufferGetPlaneCount(pixel) > 0 else { return ([], []) }
        CVPixelBufferLockBaseAddress(pixel, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixel, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddressOfPlane(pixel, 0) else { return ([], []) }
        let width = CVPixelBufferGetWidthOfPlane(pixel, 0)
        let height = CVPixelBufferGetHeightOfPlane(pixel, 0)
        let stride = CVPixelBufferGetBytesPerRowOfPlane(pixel, 0)
        let k = frame.camera.intrinsics
        let image = frame.camera.imageResolution
        let sx = Double(width) / Double(image.width)
        let sy = Double(height) / Double(image.height)
        var poses = [MCTagPose](repeating: MCTagPose(), count: 32)
        let count = poses.withUnsafeMutableBufferPointer { ptr in
            Int(mc_tag_detect(detector, base.assumingMemoryBound(to: UInt8.self),
                Int32(width), Int32(height), Int32(stride),
                Double(k.columns.0.x) * sx, Double(k.columns.1.y) * sy,
                Double(k.columns.2.x) * sx, Double(k.columns.2.y) * sy,
                tagSize, ptr.baseAddress, Int32(ptr.count)))
        }
        guard count > 0 else { return ([], []) }
        var live: [LiveMarker] = []
        var recorded: [MarkerObservation] = []
        // AprilTag pose: X right, Y down, Z forward from camera. ARKit: X right, Y up, -Z forward.
        // Change of basis from detector camera to ARKit camera.
        let cameraBasis = simd_float4x4(diagonal: SIMD4<Float>(1, -1, -1, 1))
        let inverseOrigin = simd_inverse(origin)
        for p in poses.prefix(count) {
            let r = p.rotation
            let t = p.translation
            // Rotation matrix is row-major from the C library.
            let cameraFromTag = simd_float4x4(
                SIMD4<Float>(r.0, r.3, r.6, 0),
                SIMD4<Float>(r.1, r.4, r.7, 0),
                SIMD4<Float>(r.2, r.5, r.8, 0),
                SIMD4<Float>(t.0, t.1, t.2, 1))
            // Tag coordinate frame from AprilTag pose is X right, Y down, Z forward.
            // Convert both camera and marker axes to ARKit conventions.
            let markerWorld = frame.camera.transform * cameraBasis * cameraFromTag * cameraBasis
            let local = inverseOrigin * markerWorld
            let normal = SIMD3<Float>(markerWorld.columns.2.x, markerWorld.columns.2.y, markerWorld.columns.2.z)
            let towardCamera = SIMD3<Float>(frame.camera.transform.columns.3.x - markerWorld.columns.3.x, frame.camera.transform.columns.3.y - markerWorld.columns.3.y, frame.camera.transform.columns.3.z - markerWorld.columns.3.z)
            let angle = max(0.15, abs(simd_dot(normal, simd_normalize(towardCamera))))
            let weight = max(0.1, min(3, p.decision_margin / 50)) * angle * angle
            live.append(LiveMarker(weight: weight, id: Int(p.id), transform: markerWorld))
            if let elapsed {
                recorded.append(MarkerObservation(id: Int(p.id), elapsedSeconds: elapsed,
                    arTimestamp: frame.timestamp, markerToOrigin: flatten(local), decisionMargin: p.decision_margin, sensorCorners: [p.corners.0 / Float(sx), p.corners.1 / Float(sy), p.corners.2 / Float(sx), p.corners.3 / Float(sy), p.corners.4 / Float(sx), p.corners.5 / Float(sy), p.corners.6 / Float(sx), p.corners.7 / Float(sy)]))
            }
        }
        return (live, recorded)
    }
}
