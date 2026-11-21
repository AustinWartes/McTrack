import Foundation
import ARKit
import AVFoundation
import Combine
import simd

struct TrackSample: Codable {
    let elapsedSeconds: Double
    let arTimestamp: Double
    let cameraToOrigin: [Float]
    let trackingState: String
    let fx: Float
    let fy: Float
    let cx: Float
    let cy: Float
    let imageWidth: Int
    let imageHeight: Int
}

struct TrackFile: Codable {
    let format: String
    let coordinateSystem: String
    let matrixLayout: String
    let originToARWorld: [Float]
    let samples: [TrackSample]
}

func flatten(_ m: simd_float4x4) -> [Float] {
    [m.columns.0.x,m.columns.0.y,m.columns.0.z,m.columns.0.w,
     m.columns.1.x,m.columns.1.y,m.columns.1.z,m.columns.1.w,
     m.columns.2.x,m.columns.2.y,m.columns.2.z,m.columns.2.w,
     m.columns.3.x,m.columns.3.y,m.columns.3.z,m.columns.3.w]
}

final class TrackingStore: ObservableObject {
    @Published var recording = false
    @Published var resolution = 1080
    @Published var fps = 30
    @Published var supports4K = ARWorldTrackingConfiguration.supportedVideoFormats.contains {
        max(Int($0.imageResolution.width), Int($0.imageResolution.height)) >= 3840
    }

    func cycleFPS() {
        guard !recording else { return }
        let modes = resolution == 2160 ? [30, 24] : [30, 60, 24]
        guard let index = modes.firstIndex(of: fps) else { fps = 30; return }
        fps = modes[(index + 1) % modes.count]
    }

    func cycleResolution() {
        guard !recording, supports4K else { return }
        resolution = resolution == 1080 ? 2160 : 1080
        if resolution == 2160 && fps == 60 { fps = 30 }
    }
    @Published var hasOrigin = false
    @Published var canPlaceOrigin = false
    @Published var status = "Initializing tracking"
    @Published var message = "Scan a textured floor"
    @Published var takes: [URL] = []
    @Published var showTakes = false
    @Published var latestTake: URL?

    // All ARFrame work runs on the ARSession delegate serial queue.
    private let queue = DispatchQueue(label: "mctrack.frames")
    private var origin = matrix_identity_float4x4
    private var selectedOrigin = false
    private var samples: [TrackSample] = []
    private var startTimestamp: Double?
    private var lastTimestamp: Double = -1
    private var writer: TakeWriter?
    private var activeFolder: URL?
    private var lastStatus = ""

    let takesFolder: URL = {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let folder = documents.appendingPathComponent("Takes", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }()

    init() { refreshTakes() }

    func refreshTakes() {
        let urls = (try? FileManager.default.contentsOfDirectory(at: takesFolder, includingPropertiesForKeys: nil)) ?? []
        DispatchQueue.main.async { self.takes = urls.filter { $0.hasDirectoryPath }.sorted { $0.lastPathComponent > $1.lastPathComponent } }
    }

    func setOrigin(_ matrix: simd_float4x4) {
        queue.async {
            self.origin = matrix
            self.selectedOrigin = true
            DispatchQueue.main.async {
                self.hasOrigin = true
                self.message = "Origin set"
            }
        }
    }

    func resetOrigin() {
        queue.async {
            guard self.writer == nil else { return }
            self.selectedOrigin = false
            self.origin = matrix_identity_float4x4
            DispatchQueue.main.async { self.hasOrigin = false; self.message = "Tap to set origin" }
        }
    }

    func begin() {
        queue.async {
            guard self.writer == nil else { return }
            let folder = self.takesFolder.appendingPathComponent("Take_" + Self.dateName(), isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let writer = try TakeWriter(url: folder.appendingPathComponent("video.mov"), resolution: self.resolution, fps: self.fps)
                self.writer = writer
                self.activeFolder = folder
                self.samples.removeAll(keepingCapacity: true)
                self.startTimestamp = nil
                self.lastTimestamp = -1
                DispatchQueue.main.async { self.recording = true; self.message = "Recording" }
            } catch {
                DispatchQueue.main.async { self.message = "Record error: \(error.localizedDescription)" }
            }
        }
    }

    func end() {
        queue.async {
            guard let writer = self.writer, let folder = self.activeFolder else { return }
            self.writer = nil
            self.activeFolder = nil
            let samples = self.samples
            let origin = self.origin
            DispatchQueue.main.async { self.recording = false; self.message = "Saving take…" }
            writer.finish { result in
                do {
                    let track = TrackFile(format: "McTrack_v2", coordinateSystem: "Origin-local ARKit right-handed coordinates, meters; +Y up. Camera-to-origin transforms.", matrixLayout: "column-major", originToARWorld: flatten(origin), samples: samples)
                    let data = try JSONEncoder.pretty.encode(track)
                    try data.write(to: folder.appendingPathComponent("tracking.json"), options: .atomic)
                    let metadata: [String: Any] = ["video": "video.mov", "tracking": "tracking.json", "sampleCount": samples.count, "videoOrientation": "portrait", "videoPixelSize": [self.resolution, self.resolution == 1080 ? 1920 : 3840], "videoFPS": self.fps, "audioRequested": true, "audioStatus": writer.audioStatus]
                    let meta = try JSONSerialization.data(withJSONObject: metadata, options: .prettyPrinted)
                    try meta.write(to: folder.appendingPathComponent("metadata.json"), options: .atomic)
                    DispatchQueue.main.async {
                        self.latestTake = folder
                        self.message = result == nil ? "Take saved" : "Saved with video warning"
                        self.refreshTakes()
                    }
                } catch {
                    DispatchQueue.main.async { self.message = "Save error: \(error.localizedDescription)" }
                }
            }
        }
    }

    func process(_ frame: ARFrame) {
        queue.async {
            let state: String
            switch frame.camera.trackingState {
            case .normal: state = "Tracking normal"
            case .notAvailable: state = "Tracking unavailable"
            case .limited: state = "Tracking limited"
            }
            if state != self.lastStatus {
                self.lastStatus = state
                DispatchQueue.main.async { self.status = state }
            }
            guard let writer = self.writer else { return }
            guard frame.timestamp > self.lastTimestamp else { return }
            self.lastTimestamp = frame.timestamp
            if self.startTimestamp == nil { self.startTimestamp = frame.timestamp }
            guard let start = self.startTimestamp else { return }
            let camera = frame.camera
            let k = camera.intrinsics
            let resolution = camera.imageResolution
            let local = simd_inverse(self.origin) * camera.transform
            self.samples.append(TrackSample(elapsedSeconds: frame.timestamp - start, arTimestamp: frame.timestamp, cameraToOrigin: flatten(local), trackingState: state, fx: k.columns.0.x, fy: k.columns.1.y, cx: k.columns.2.x, cy: k.columns.2.y, imageWidth: Int(resolution.width), imageHeight: Int(resolution.height)))
            writer.appendVideo(frame.capturedImage, arTimestamp: frame.timestamp)
        }
    }

    private static func dateName() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd_HHmmss_SSS"; return f.string(from: Date())
    }
}

extension JSONEncoder {
    static var pretty: JSONEncoder { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; return encoder }
}
