import SwiftUI
import ARKit
import SceneKit
import simd
import UIKit

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
        private let groundGrid = SCNNode()
        private var gridMaterial: SCNMaterial?
        private var gridOrigin: simd_float4x4?
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
            groundGrid.isHidden = true
            gridOrigin = nil
            currentPlacement = nil
            store.resetOrigin()
            view.session.run(config, options: [.resetTracking, .removeExistingAnchors])
        }

        init(store: TrackingStore) { self.store = store }

        func setup(in view: ARSCNView) {
            self.view = view
            makeReticle()
            makeGizmo()
            makeGroundGrid()
            view.scene.rootNode.addChildNode(reticle)
            view.scene.rootNode.addChildNode(gizmo)
            view.scene.rootNode.addChildNode(groundGrid)
            reticle.isHidden = true
            gizmo.isHidden = true
            groundGrid.isHidden = true
            let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
            view.addGestureRecognizer(tap)
        }

        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            store.process(frame)
            let now = frame.timestamp
            guard now - lastRaycast > 0.033 else { return }
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
            if gridOrigin == nil {
                // The grid is established once in world space, not parented to the reticle.
                gridOrigin = result.worldTransform
                groundGrid.simdTransform = result.worldTransform
            }
            if let base = gridOrigin {
                let local = simd_inverse(base) * result.worldTransform
                let u = 0.5 + local.columns.3.x / 5.0
                let v = 0.5 - local.columns.3.z / 5.0
                gridMaterial?.setValue(SCNVector3(u, v, 0), forKey: "revealUV")
                groundGrid.isHidden = false
            }
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
            groundGrid.isHidden = true
            store.setOrigin(matrix)
        }

        func resetPlacement() {
            guard !store.recording else { return }
            placed = false
            gizmo.isHidden = true
            groundGrid.isHidden = true
            gridOrigin = nil
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

        // All placement graphics are flat, unlit, and double-sided.
        // The ring is an opaque texture, so no overlapping torus/shadow geometry is needed.
        private func makeReticle() {
            let size: CGFloat = 512
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
            let image = renderer.image { context in
                let cg = context.cgContext
                let coral = UIColor(red: 231/255, green: 125/255, blue: 118/255, alpha: 1)
                let ivory = UIColor(red: 242/255, green: 240/255, blue: 236/255, alpha: 1)
                cg.setStrokeColor(coral.cgColor)
                cg.setLineWidth(17)
                cg.strokeEllipse(in: CGRect(x: 45, y: 45, width: 422, height: 422))
                cg.setStrokeColor(coral.cgColor)
                cg.setLineWidth(12)
                cg.strokeEllipse(in: CGRect(x: 215, y: 215, width: 82, height: 82))
                cg.setFillColor(ivory.cgColor)
                cg.fillEllipse(in: CGRect(x: 237, y: 237, width: 38, height: 38))
            }
            let plane = SCNPlane(width: 0.24, height: 0.24)
            let m = material(.white)
            m.diffuse.contents = image
            m.transparencyMode = .aOne
            m.writesToDepthBuffer = false
            m.readsFromDepthBuffer = false
            plane.materials = [m]
            let node = SCNNode(geometry: plane)
            node.eulerAngles.x = -.pi / 2
            node.position.y = 0.008
            reticle.addChildNode(node)
        }

        private func makeGroundGrid() {
            let size: CGFloat = 2048
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
            let image = renderer.image { context in
                let cg = context.cgContext
                cg.setFillColor(UIColor(red: 242/255, green: 240/255, blue: 236/255, alpha: 1).cgColor)
                // A 5 m square of fixed dots, 5 cm apart.
                // The shader reveals only a small radius around the moving reticle.
                let count = 100
                let step = size / CGFloat(count)
                for x in 0...count {
                    for y in 0...count {
                        let px = CGFloat(x) * step
                        let py = CGFloat(y) * step
                        cg.fillEllipse(in: CGRect(x: px - 3.0, y: py - 3.0, width: 6, height: 6))
                    }
                }
            }
            let plane = SCNPlane(width: 5, height: 5)
            let m = material(.white)
            m.diffuse.contents = image
            m.transparencyMode = .aOne
            m.writesToDepthBuffer = false
            m.readsFromDepthBuffer = false
            m.setValue(SCNVector3(0.5, 0.5, 0), forKey: "revealUV")
            m.shaderModifiers = [.surface: """
                uniform vec3 revealUV;
                float distanceMeters = distance(_surface.diffuseTexcoord, revealUV.xy) * 5.0;
                float fade = 1.0 - smoothstep(0.12, 0.72, distanceMeters);
                _surface.diffuse.a *= fade;
            """]
            plane.materials = [m]
            gridMaterial = m
            let node = SCNNode(geometry: plane)
            node.eulerAngles.x = -.pi / 2
            node.position.y = 0.003
            groundGrid.addChildNode(node)
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
