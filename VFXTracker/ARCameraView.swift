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
        view.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        context.coordinator.setup(in: view)
        DispatchQueue.main.async { self.coordinatorRef = context.coordinator }
        return view
    }

    func updateUIView(_ view: ARSCNView, context: Context) {}

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
            let white = UIColor.white.withAlphaComponent(0.55)
            let ring = SCNTorus(ringRadius: 0.095, pipeRadius: 0.0015)
            ring.materials = [material(white)]
            reticle.addChildNode(SCNNode(geometry: ring))
            let dot = SCNSphere(radius: 0.005)
            dot.materials = [material(UIColor.white.withAlphaComponent(0.7))]
            reticle.addChildNode(SCNNode(geometry: dot))
            // Sparse radial dot field. Opacity fades smoothly with distance.
            for x in -8...8 {
                for z in -8...8 {
                    let px = Float(x) * 0.037
                    let pz = Float(z) * 0.037
                    let radius = sqrt(px*px + pz*pz)
                    if radius < 0.11 || radius > 0.32 { continue }
                    let alpha = CGFloat(max(0, 1 - radius/0.32)) * 0.40
                    let geometry = SCNSphere(radius: 0.0018)
                    geometry.segmentCount = 6
                    geometry.materials = [material(UIColor.white.withAlphaComponent(alpha))]
                    let node = SCNNode(geometry: geometry)
                    node.simdPosition = SIMD3<Float>(px, 0.002, pz)
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
