import Foundation
import ARKit
import simd

struct CameraSample: Codable {
    let frameTimestamp: Double
    let elapsedSeconds: Double
    let cameraTransform: [Float]
    let trackingState: String
}

final class TrackingStore: ObservableObject {
    @Published var isRecording = false
    @Published var sampleCount = 0
    @Published var trackingDescription = "Starting AR session..."
    @Published var exportURL: URL?

    private let lock = NSLock()
    private var samples: [CameraSample] = []
    private var recordingStartTimestamp: TimeInterval?

    func updateTrackingState(_ state: ARCamera.TrackingState) {
        let description: String
        switch state {
        case .normal:
            description = "Tracking: Normal"
        case .notAvailable:
            description = "Tracking: Unavailable"
        case .limited(let reason):
            switch reason {
            case .initializing: description = "Tracking: Initializing"
            case .excessiveMotion: description = "Tracking: Excessive motion"
            case .insufficientFeatures: description = "Tracking: Need more visual detail"
            case .relocalizing: description = "Tracking: Relocalizing"
            @unknown default: description = "Tracking: Limited"
            }
        }
        DispatchQueue.main.async { self.trackingDescription = description }
    }

    func startRecording(at timestamp: TimeInterval) {
        lock.lock()
        samples.removeAll(keepingCapacity: true)
        recordingStartTimestamp = nil
        isRecording = true
        sampleCount = 0
        lock.unlock()
    }

    func stopRecording() {
        lock.lock()
        isRecording = false
        lock.unlock()
    }

    func append(frame: ARFrame) {
        lock.lock()
        defer { lock.unlock() }
        guard isRecording else { return }
        if recordingStartTimestamp == nil { recordingStartTimestamp = frame.timestamp }
        guard let start = recordingStartTimestamp else { return }

        let matrix = frame.camera.transform
        let values: [Float] = [
            matrix.columns.0.x, matrix.columns.0.y, matrix.columns.0.z, matrix.columns.0.w,
            matrix.columns.1.x, matrix.columns.1.y, matrix.columns.1.z, matrix.columns.1.w,
            matrix.columns.2.x, matrix.columns.2.y, matrix.columns.2.z, matrix.columns.2.w,
            matrix.columns.3.x, matrix.columns.3.y, matrix.columns.3.z, matrix.columns.3.w
        ]

        let state: String
        switch frame.camera.trackingState {
        case .normal: state = "normal"
        case .notAvailable: state = "notAvailable"
        case .limited: state = "limited"
        }

        samples.append(CameraSample(
            frameTimestamp: frame.timestamp,
            elapsedSeconds: frame.timestamp - start,
            cameraTransform: values,
            trackingState: state
        ))
        let count = samples.count
        DispatchQueue.main.async { self.sampleCount = count }
    }

    func makeExport() throws -> URL {
        lock.lock()
        let snapshot = samples
        lock.unlock()

        let payload: [String: Any] = [
            "format": "VFXTracker_CameraTrack_v1",
            "coordinateSystem": "ARKit world coordinates; right-handed; meters",
            "matrixLayout": "column-major, 16 Float values",
            "notes": "Camera transform is the ARKit camera-to-world transform. frameTimestamp is ARKit's frame timestamp in seconds. elapsedSeconds is relative to recording start.",
            "sampleCount": snapshot.count,
            "samples": snapshot.map {
                [
                    "frameTimestamp": $0.frameTimestamp,
                    "elapsedSeconds": $0.elapsedSeconds,
                    "cameraTransform": $0.cameraTransform,
                    "trackingState": $0.trackingState
                ] as [String: Any]
            }
        ]

        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("VFXTracker_CameraTrack_\(Int(Date().timeIntervalSince1970)).json")
        try data.write(to: url, options: .atomic)
        DispatchQueue.main.async { self.exportURL = url }
        return url
    }
}
