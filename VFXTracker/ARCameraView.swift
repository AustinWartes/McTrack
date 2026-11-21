import SwiftUI
import ARKit
import SceneKit
import simd

struct ARCameraView: UIViewRepresentable {
    @ObservedObject var store: TrackingStore
    @Binding var coordinatorRef: Coordinator?

    func makeCoordinator() -> Coordinator { Coordinator(store: store) }

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        view.scene = SCNScene()
        view.delegate = context.coordinator
        view.session.delegate = context.coordinator
        view.automaticallyUpdatesLighting = false
        view.autoenablesDefaultLighting = false
        view.rendersContinuously = true
        view.contentMode = .scaleAspectFill
        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravity
        configuration.planeDetection = [.horizontal]
        context.coordinator.applyVideoFormat(to: configuration)
        view.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        context.coordinator.setup(in: view)
        DispatchQueue.main.async { self.coordinatorRef = context.coordinator }
        return view
    }

    func updateUIView(_ view: ARSCNView, context: Context) {
        context.coordinator.updateFormatIfNeeded()
    }

    static func dismantleUIView(_ view: ARSCNView, coordinator: Coordinator) {
        view.session.pause()
    }

    final class Coordinator: NSObject, ARSCNViewDelegate, ARSessionDelegate {
        private let store: TrackingStore
        private weak var view: ARSCNView?
        private let reticle = SCNNode()
        private let gizmo = SCNNode()
        private var lastRaycast: TimeInterval = 0
        private var currentPlacement: simd_float4x4?
        private var placed = false
        private var configuredResolution = 1080

        func applyVideoFormat(to configuration: ARWorldTrackingConfiguration) {
            let target = store.resolution
            let formats = ARWorldTrackingConfiguration.supportedVideoFormats
            let matches = formats.filter { format in
                let width = Int(format.imageResolution.width)
                let height = Int(format.imageResolution.height)
                let longSide = max(width, height)
                return target == 2160 ? longSide >= 3840 : longSide >= 1920 && longSide < 3840
            }
            if let selected = matches.sorted(by: { abs($0.framesPerSecond - 60) < abs($1.framesPerSecond - 60) }).first {
                configuration.videoFormat = selected
            }
            configuredResolution = target
        }

        func updateFormatIfNeeded() {
            guard configuredResolution != store.resolution, !store.recording, let view = view else { return }
            let config = ARWorldTrackingConfiguration()
            config.worldAlignment = .gravity
            config.planeDetection = [.horizontal]
            applyVideoFormat(to: config)
            // Reconfiguration resets the session and invalidates the previously placed origin.
            placed = false
            reticle.isHidden = true
            gizmo.isHidden = true
            currentPlacement = nil
            store.resetOrigin()
            view.session.run(config, options: [.resetTracking, .removeExistingAnchors])
        }

        init(store: TrackingStore) { self.store = store }

        func setup(in view: ARSCNView) {
            self.view = view
            makeReticle()
            makeGizmo()
            view.scene.rootNode.addChildNode(reticle)
            view.scene.rootNode.addChildNode(gizmo)
            reticle.isHidden = true
            gizmo.isHidden = true
            let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
            view.addGestureRecognizer(tap)
        }

        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            store.process(frame)
            let now = frame.timestamp
            guard now - lastRaycast > 0.09 else { return }
            lastRaycast = now
            DispatchQueue.main.async { [weak self] in self?.updatePlacement() }
        }

        private func updatePlacement() {
            guard let view = view, !placed else { return }
            let center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
            guard let query = view.raycastQuery(from: center, allowing: .estimatedPlane, alignment: .horizontal),
                  let result = view.session.raycast(query).first else {
                reticle.isHidden = true
                currentPlacement = nil
                if store.canPlaceOrigin { store.canPlaceOrigin = false }
                return
            }
            currentPlacement = result.worldTransform
            reticle.simdTransform = result.worldTransform
            reticle.isHidden = false
            if !store.canPlaceOrigin { store.canPlaceOrigin = true }
            if store.message == "Scan a textured floor" { store.message = "Tap to set origin" }
        }

        @objc private func tapped(_ gesture: UITapGestureRecognizer) { placeOrigin() }

        func placeOrigin() {
            guard !placed, let matrix = currentPlacement else { return }
            placed = true
            gizmo.simdTransform = matrix
            gizmo.isHidden = false
            reticle.isHidden = true
            store.setOrigin(matrix)
        }

        func resetPlacement() {
            guard !store.recording else { return }
            placed = false
            gizmo.isHidden = true
            currentPlacement = nil
            store.resetOrigin()
        }

        private func material(_ color: UIColor) -> SCNMaterial {
            let m = SCNMaterial()
            m.diffuse.contents = color
            m.lightingModel = .constant
            m.isDoubleSided = true
            m.readsFromDepthBuffer = true
            return m
        }

        private func segment(_ a: SIMD3<Float>, _ b: SIMD3<Float>, radius: CGFloat, color: UIColor, parent: SCNNode) {
            let delta = b - a
            let length = simd_length(delta)
            guard length > 0.0001 else { return }
            let shape = SCNCylinder(radius: radius, height: CGFloat(length))
            shape.radialSegmentCount = 7
            shape.materials = [material(color)]
            let node = SCNNode(geometry: shape)
            node.simdPosition = (a + b) / 2
            node.simdOrientation = simd_quatf(from: SIMD3<Float>(0,1,0), to: simd_normalize(delta))
            parent.addChildNode(node)
        }

        private func makeReticle() {
            let coral = UIColor(red: 231/255, green: 125/255, blue: 118/255, alpha: 1)
            let ivory = UIColor(red: 242/255, green: 240/255, blue: 236/255, alpha: 1)
            // Two low-profile rings make the indicator readable on light and dark floors.
            for (radius, pipe, color, height) in [
                (CGFloat(0.096), CGFloat(0.006), UIColor.black.withAlphaComponent(0.60), Float(0.004)),
                (CGFloat(0.095), CGFloat(0.003), coral, Float(0.006))
            ] {
                let ring = SCNTorus(ringRadius: radius, pipeRadius: pipe)
                ring.materials = [material(color)]
                let node = SCNNode(geometry: ring)
                node.simdPosition.y = height
                reticle.addChildNode(node)
            }
            let dot = SCNSphere(radius: 0.010)
            dot.materials = [material(coral)]
            let center = SCNNode(geometry: dot)
            center.simdPosition.y = 0.010
            reticle.addChildNode(center)
            let core = SCNSphere(radius: 0.006)
            core.materials = [material(ivory)]
            let coreNode = SCNNode(geometry: core)
            coreNode.simdPosition.y = 0.015
            reticle.addChildNode(coreNode)

            // Radial fade in the horizontal XZ plane, independent of screen crop.
            // Dot sizes and opacity remain high near the ring, then taper to zero.
            let spacing: Float = 0.047
            let maxRadius: Float = 0.59
            for x in -13...13 {
                for z in -13...13 {
                    let px = Float(x) * spacing
                    let pz = Float(z) * spacing
                    let distance = hypot(px, pz)
                    if distance < 0.12 || distance >= maxRadius { continue }
                    let t = min(1, max(0, (distance - 0.12) / (maxRadius - 0.12)))
                    let fade = (1 - t) * (1 - t) * (1 + 2 * t)
                    let alpha = CGFloat(0.92 * fade)
                    if alpha < 0.035 { continue }
                    let geometry = SCNSphere(radius: CGFloat(0.0030 * (0.65 + 0.35 * fade)))
                    geometry.segmentCount = 6
                    geometry.materials = [material(ivory.withAlphaComponent(alpha))]
                    let node = SCNNode(geometry: geometry)
                    node.simdPosition = SIMD3<Float>(px, 0.005, pz)
                    reticle.addChildNode(node)
                }
            }
        }

        private func makeGizmo() {
            let axes: [(SIMD3<Float>, UIColor)] = [
                (SIMD3<Float>(1,0,0), .systemRed),
                (SIMD3<Float>(0,1,0), .systemGreen),
                (SIMD3<Float>(0,0,1), .systemBlue)
            ]
            for (direction, color) in axes {
                segment(.zero, direction * 0.28, radius: 0.0035, color: color, parent: gizmo)
                for index in 0..<6 {
                    let start = Float(index) * 0.046 + 0.008
                    let end = start + 0.024
                    segment(-direction * start, -direction * end, radius: 0.002, color: color.withAlphaComponent(0.68), parent: gizmo)
                }
            }
            let center = SCNSphere(radius: 0.006)
            center.materials = [material(.white)]
            gizmo.addChildNode(SCNNode(geometry: center))
        }
    }
}
