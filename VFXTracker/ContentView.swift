import SwiftUI
import UIKit
import ARKit
import AVFoundation

struct ContentView: View {
    @StateObject private var store = TrackingStore()
    @State private var coordinator: ARCameraView.Coordinator?
    @State private var showCameraSettings = false
    @State private var showRigidSettings = false
    private let coral = Color(red: 1.0, green: 0.27, blue: 0.36)
    private let brightCoral = Color(red: 1.0, green: 0.69, blue: 0.69)
    private let glass = Color.black.opacity(0.08)

    // Tighter additive-style halo: bright inner rim and restrained colored outer light.
    private func glassCapsule(active: Bool = false) -> some View {
        Capsule()
            .fill(.ultraThinMaterial)
            .overlay(Capsule().fill(Color.white.opacity(0.025)))
            .overlay(Capsule().strokeBorder(active ? LinearGradient(colors: [coral, brightCoral, coral], startPoint: .topLeading, endPoint: .bottomTrailing) : LinearGradient(colors: [.white.opacity(0.30), .white.opacity(0.30)], startPoint: .top, endPoint: .bottom), lineWidth: 1.25))
            .shadow(color: active ? coral.opacity(0.65) : .clear, radius: 5)
            .shadow(color: active ? coral.opacity(0.20) : .clear, radius: 12)
    }
    private func glassRounded(_ radius: CGFloat = 18, active: Bool = false) -> some View {
        RoundedRectangle(cornerRadius: radius)
            .fill(.ultraThinMaterial)
            .overlay(RoundedRectangle(cornerRadius: radius).fill(.white.opacity(0.025)))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(active ? LinearGradient(colors: [coral, brightCoral, coral], startPoint: .topLeading, endPoint: .bottomTrailing) : LinearGradient(colors: [.white.opacity(0.33), .white.opacity(0.33)], startPoint: .top, endPoint: .bottom), lineWidth: 1.0))
            .shadow(color: active ? coral.opacity(0.48) : .clear, radius: 5)
    }
    private var framedWordmark: some View {
        HStack(spacing: 0) {
            Text("Mc")
                .foregroundStyle(.white)
                .shadow(color: .white.opacity(0.75), radius: 3)
                .shadow(color: .white.opacity(0.25), radius: 8)
            Text("Track")
                .foregroundStyle(coral)
                // The lighter salmon is a very thin edge highlight around the red fill.
                .shadow(color: brightCoral.opacity(0.95), radius: 0.65)
                .shadow(color: coral.opacity(0.90), radius: 5)
                .shadow(color: coral.opacity(0.55), radius: 12)
        }
        .font(.system(size: 23, weight: .bold, design: .rounded))
        .italic()
        .padding(.horizontal, 15)
        .padding(.vertical, 5)
        .overlay {
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                Path { path in
                    let arm: CGFloat = 10
                    path.move(to: CGPoint(x: arm, y: 0)); path.addLine(to: .zero); path.addLine(to: CGPoint(x: 0, y: arm))
                    path.move(to: CGPoint(x: w-arm, y: 0)); path.addLine(to: CGPoint(x: w, y: 0)); path.addLine(to: CGPoint(x: w, y: arm))
                    path.move(to: CGPoint(x: 0, y: h-arm)); path.addLine(to: CGPoint(x: 0, y: h)); path.addLine(to: CGPoint(x: arm, y: h))
                    path.move(to: CGPoint(x: w-arm, y: h)); path.addLine(to: CGPoint(x: w, y: h)); path.addLine(to: CGPoint(x: w, y: h-arm))
                }
                .stroke(coral, style: StrokeStyle(lineWidth: 1.55, lineCap: .round, lineJoin: .round))
                .shadow(color: coral, radius: 5)
                .shadow(color: coral.opacity(0.85), radius: 12)
            }
        }
    }

    var body: some View {
        ZStack {
            ARCameraView(store: store, coordinatorRef: $coordinator)
                .ignoresSafeArea()
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    framedWordmark
                    Spacer()
                    Text(store.status == "Tracking normal" ? "● TRACKING" : "● LIMITED")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(store.status == "Tracking normal" ? .green : .yellow)
                    Button { showCameraSettings.toggle() } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 19))
                            .frame(width: 42, height: 42)
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay(Circle().stroke(showCameraSettings ? coral : .white.opacity(0.35), lineWidth: 1))
                            .shadow(color: showCameraSettings ? coral.opacity(0.72) : coral.opacity(0.14), radius: showCameraSettings ? 7 : 3)
                    }
                    .accessibilityLabel("Camera settings")
                }
                .padding(.horizontal, 18).padding(.top, 10)

                if showCameraSettings {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("Camera Settings", systemImage: "camera")
                                .font(.system(size: 14, weight: .semibold))
                            Spacer()
                            Button { showCameraSettings = false } label: { Image(systemName: "xmark.circle.fill") }
                        }
                        Text("ARKit controls the capture camera. Manual exposure and white balance require separate device capability testing before they can be enabled safely.")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.76))
                    }
                    .padding(14)
                    .background(glassRounded())
                    .padding(.horizontal, 16).padding(.top, 8)
                }

                Spacer()
                HStack {
                    Spacer()
                    if store.hasOrigin {
                        Button("Reset Origin") { coordinator?.resetPlacement() }
                            .disabled(store.recording)
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 13).padding(.vertical, 11)
                            .background(glassCapsule(active: true))
                    } else {
                        Label(store.canPlaceOrigin ? "Tap to Set Origin" : "Scan Surface", systemImage: "scope")
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 13).padding(.vertical, 11)
                            .background(glassCapsule(active: true))
                    }
                }
                .padding(.horizontal, 18).padding(.bottom, 12)

                HStack(spacing: 7) {
                    Button { store.cycleTrackingMode() } label: {
                        HStack(spacing: 5) {
                            Image(systemName: store.trackingMode.symbol).foregroundStyle(coral)
                            Text(store.trackingMode.title).foregroundStyle(.white)
                        }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Capsule().strokeBorder(LinearGradient(colors: [coral, brightCoral, coral], startPoint: .leading, endPoint: .trailing), lineWidth: 1.3)
                                .shadow(color: coral.opacity(0.55), radius: 5))
                    }
                    .disabled(store.recording)
                    .accessibilityLabel("Cycle tracking mode")
                    Button { store.cycleResolution() } label: {
                        Text(store.resolution == 2160 ? "4K" : "1080p")
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                            .background(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 1))
                    }
                    .disabled(store.recording || !store.supports4K)
                    Button { store.cycleFPS() } label: {
                        Text("\(store.fps) FPS").frame(maxWidth: .infinity)
                            .padding(.vertical, 8).background(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 1))
                    }
                    .disabled(store.recording)
                }
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 7).padding(.vertical, 5)
                .background(glassRounded())
                .padding(.horizontal, 16).padding(.bottom, 12)

                if store.trackingMode == .rigid {
                    HStack(spacing: 8) {
                        Button { showRigidSettings = true } label: {
                            Label("Cube Settings", systemImage: "cube.transparent")
                        }
                        Spacer()
                        Text(store.rigidReady ? "CALIBRATED" : (store.rigidCalibrating ? "SCANNING" : "NOT CALIBRATED"))
                            .foregroundStyle(store.rigidReady ? .green : brightCoral)
                        Button(store.rigidCalibrating ? "Finish" : "Calibrate") {
                            if store.rigidCalibrating { store.finishRigidCalibration() }
                            else { store.startRigidCalibration() }
                        }
                        .disabled(store.recording)
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .padding(11)
                    .background(glassRounded(12))
                    .padding(.horizontal, 16).padding(.bottom, 10)
                }

                HStack(spacing: 10) {
                    Button {
                        if store.recording { store.end() } else { store.begin() }
                    } label: {
                        Label(store.recording ? "STOP" : "RECORD", systemImage: store.recording ? "stop.fill" : "record.circle")
                            .font(.system(size: 15, weight: .bold))
                            .frame(maxWidth: .infinity).frame(height: 52)
                            .background(store.recording ? coral : .white, in: RoundedRectangle(cornerRadius: 14))
                            .shadow(color: coral.opacity(0.45), radius: 11)
                            .foregroundStyle(store.recording ? .white : .black)
                    }
                    Button { store.refreshTakes(); store.showTakes = true } label: {
                        Image(systemName: "folder")
                            .font(.system(size: 19, weight: .medium))
                            .frame(width: 54, height: 52)
                            .background(glassRounded(14))
                    }
                    .foregroundStyle(.white)
                }
                .padding(.horizontal, 16)
                Text(store.message)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.top, 7).padding(.bottom, 12)
            }
            .foregroundStyle(.white)
        }
        .overlay(alignment: .top) {
            LinearGradient(colors: [.black.opacity(0.28), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 65).ignoresSafeArea(edges: .top).allowsHitTesting(false)
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .sheet(isPresented: $showRigidSettings) {
            NavigationStack {
                Form {
                    Section("Cube dimensions") {
                        HStack {
                            Text("AprilTag size (mm)")
                            Spacer()
                            TextField("75", value: $store.rigidTagMillimeters, format: .number)
                                .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                                .frame(width: 95)
                        }
                        HStack {
                            Text("Cube edge (mm)")
                            Spacer()
                            TextField("90", value: $store.rigidCubeMillimeters, format: .number)
                                .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                                .frame(width: 95)
                        }
                        Text("Measure the detection boundary of the black-and-white tag, not the surrounding paper. Cube edge is the outside face-to-face dimension.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Section("Calibration") {
                        Text("Detected IDs: \(store.rigidDetectedIDs)")
                        Text("Show adjacent faces together while slowly rotating the cube. Keep the cube in the camera view; move the camera if needed.")
                            .font(.footnote)
                        Button("Recalibrate") { store.startRigidCalibration() }
                            .disabled(store.recording)
                    }
                }
                .navigationTitle("Rigid Cube")
                .toolbar { ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        store.rigidTagMillimeters = max(10, min(300, store.rigidTagMillimeters))
                        store.rigidCubeMillimeters = max(20, min(500, store.rigidCubeMillimeters))
                        store.updateRigidDimensions()
                        showRigidSettings = false
                    }
                }}
            }
        }
        .sheet(isPresented: $store.showTakes) {
            NavigationStack {
                List {
                    ForEach(store.takes, id: \.path) { folder in
                        ShareLink(item: folder, preview: SharePreview(folder.lastPathComponent)) {
                            Label(folder.lastPathComponent, systemImage: "folder")
                        }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    VStack(spacing: 8) {
                        Text("Saved locally: Files → On My iPhone → McTrack → Takes")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                        Button("Open Files") {
                            if let url = URL(string: "shareddocuments://") {
                                UIApplication.shared.open(url)
                            }
                        }
                        .font(.system(size: 13, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(12)
                }
                .navigationTitle("Saved Takes")
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { store.showTakes = false } } }
                .overlay {
                    if store.takes.isEmpty { ContentUnavailableView("No takes yet", systemImage: "folder", description: Text("Record a take to save it here.")) }
                }
            }
        }
    }
}

