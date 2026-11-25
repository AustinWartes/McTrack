import SwiftUI
import UIKit
import ARKit
import AVFoundation

struct ContentView: View {
    @ObservedObject var store: TrackingStore
    var onHome: () -> Void
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var coordinator: ARCameraView.Coordinator?
    @State private var showCameraSettings = false
    @State private var showRigidSettings = false
    @State private var exposureLocked = false
    @State private var exposure: Double = 0
    @State private var temperature: Double = 5500
    @State private var autoWhiteBalance = true
    @State private var cameraFeedback = ""
    @FocusState private var editingDimensions: Bool
    private let coral = Color(red: 1.0, green: 0.27, blue: 0.36)
    private let brightCoral = Color(red: 1.0, green: 0.69, blue: 0.69)
    private let glass = Color.black.opacity(0.036)

    // Tighter additive-style halo: bright inner rim and restrained colored outer light.
    private func glassCapsule(active: Bool = false) -> some View {
        Capsule()
            .fill(Color.clear)
            .background(.ultraThinMaterial, in: Capsule()).environment(\.colorScheme, .dark)
            .overlay(Capsule().fill(glass))
            .overlay(Capsule().strokeBorder(active ? LinearGradient(colors: [coral, brightCoral, coral], startPoint: .topLeading, endPoint: .bottomTrailing) : LinearGradient(colors: [.white.opacity(0.30), .white.opacity(0.30)], startPoint: .top, endPoint: .bottom), lineWidth: 1.25))
            .shadow(color: active ? coral.opacity(0.65) : .clear, radius: 5)
            .shadow(color: active ? coral.opacity(0.20) : .clear, radius: 12)
    }
    private func glassRounded(_ radius: CGFloat = 18, active: Bool = false) -> some View {
        RoundedRectangle(cornerRadius: radius)
            .fill(Color.clear)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius)).environment(\.colorScheme, .dark)
            .overlay(RoundedRectangle(cornerRadius: radius).fill(glass))
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

    private func applyCameraSettings() {
        guard !store.recording, let device = ARWorldTrackingConfiguration.configurableCaptureDeviceForPrimaryCamera else { cameraFeedback = "Camera controls unavailable"; return }
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            let bias = min(device.maxExposureTargetBias, max(device.minExposureTargetBias, Float(exposure)))
            if exposureLocked {
                if device.isExposureModeSupported(.locked) { device.exposureMode = .locked } else { exposureLocked = false }
            } else {
                if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
                device.setExposureTargetBias(bias, completionHandler: nil)
            }
            if autoWhiteBalance {
                if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) { device.whiteBalanceMode = .continuousAutoWhiteBalance }
            } else if device.isWhiteBalanceModeSupported(.locked) {
                let gains = device.deviceWhiteBalanceGains(for: AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(temperature: Float(temperature), tint: 0))
                let maxGain = device.maxWhiteBalanceGain
                let safe = AVCaptureDevice.WhiteBalanceGains(redGain: min(maxGain, max(1, gains.redGain)), greenGain: min(maxGain, max(1, gains.greenGain)), blueGain: min(maxGain, max(1, gains.blueGain)))
                device.setWhiteBalanceModeLocked(with: safe, completionHandler: nil)
            } else { cameraFeedback = "Manual white balance unavailable"; return }
            cameraFeedback = "Camera settings applied"
        } catch { cameraFeedback = error.localizedDescription }
    }

    var body: some View {
        ZStack {
            ARCameraView(store: store, coordinatorRef: $coordinator)
                .ignoresSafeArea()
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Button(action: onHome) { Image(systemName: "chevron.left").padding(8) }.disabled(store.recording || store.saving)
                    framedWordmark
                    Spacer()
                    Text(store.status == "Tracking normal" ? "● TRACKING" : "● LIMITED")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(store.status == "Tracking normal" ? .green : .yellow)
                    Button { showRigidSettings = false; showCameraSettings.toggle() } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 19))
                            .frame(width: 42, height: 42)
                            .background(.ultraThinMaterial, in: Circle()).environment(\.colorScheme, .dark)
                            .overlay(Circle().fill(glass))
                            .overlay(Circle().stroke(showCameraSettings ? coral : .white.opacity(0.35), lineWidth: 1))
                            .shadow(color: showCameraSettings ? coral.opacity(0.72) : coral.opacity(0.14), radius: showCameraSettings ? 7 : 3)
                    }
                    .accessibilityLabel("Camera settings")
                }
                .padding(.horizontal, 18).padding(.top, 10)

                if showCameraSettings {
                    ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            HStack { Image(systemName: showRigidSettings ? "cube" : "camera").foregroundStyle(coral).shadow(color: .red, radius: 5); Text(showRigidSettings ? "Rigid Body" : "Camera") }
                                .font(.system(size: 15, weight: .semibold))
                            Spacer()
                            Button { editingDimensions = false; if showRigidSettings { store.updateRigidDimensions() }; showCameraSettings = false } label: { Image(systemName: "xmark").padding(6) }
                        }
                        if !showRigidSettings {
                            HStack {
                                Label("Exposure", systemImage: "sun.max")
                                Spacer()
                                Text(String(format: "%+.1f EV", exposure)).monospacedDigit().foregroundStyle(brightCoral)
                                Button { exposureLocked.toggle(); applyCameraSettings() } label: {
                                    Image(systemName: exposureLocked ? "lock.fill" : "lock.open").foregroundStyle(exposureLocked ? brightCoral : .white).padding(6)
                                }.accessibilityLabel(exposureLocked ? "Unlock exposure" : "Lock exposure")
                            }
                            GlowSlider(value: $exposure, range: -2...2, step: 0.1, commit: applyCameraSettings).disabled(exposureLocked).opacity(exposureLocked ? 0.4 : 1)
                            HStack {
                                Text("WB").font(.system(size: 10, weight: .bold)).padding(4).overlay(RoundedRectangle(cornerRadius: 4).stroke(.white.opacity(0.5)))
                                Text("Auto white balance"); Spacer()
                                GlowToggle(value: $autoWhiteBalance).onChange(of: autoWhiteBalance) { _, _ in applyCameraSettings() }
                            }
                            if !autoWhiteBalance {
                                HStack { Text("Temperature"); Spacer(); Text("\(Int(temperature)) K").foregroundStyle(brightCoral) }
                                GlowSlider(value: $temperature, range: 2500...8500, step: 100, commit: applyCameraSettings)
                            }
                            Button("Reset camera settings") { exposureLocked = false; exposure = 0; autoWhiteBalance = true; temperature = 5500; applyCameraSettings() }.foregroundStyle(brightCoral)
                            if !cameraFeedback.isEmpty && cameraFeedback != "Camera settings applied" { Text(cameraFeedback).font(.caption) }
                        } else {
                            HStack { Text("Tag boundary (mm)"); Spacer(); TextField("75", value: $store.rigidTagMillimeters, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).focused($editingDimensions).frame(width: 90).foregroundStyle(brightCoral) }
                            HStack { Text("Cube edge (mm)"); Spacer(); TextField("90", value: $store.rigidCubeMillimeters, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).focused($editingDimensions).frame(width: 90).foregroundStyle(brightCoral) }
                            
                            HStack { Text("Extended Z axis"); Spacer(); GlowToggle(value: $store.showRigidAxis) }
                            HStack { Text("Axis length"); Spacer(); Text("\(store.rigidAxisLength, specifier: "%.2f") m").foregroundStyle(brightCoral) }
                            GlowSlider(value: $store.rigidAxisLength, range: 0.25...2, step: 0.05, commit: {})
                            Button("Recalibrate") { editingDimensions = false; store.updateRigidDimensions(); store.startRigidCalibration(); showCameraSettings = false }.foregroundStyle(brightCoral)
                        }
                    }.font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
                    .disabled(store.recording).padding(14)
                    .background(glassRounded()).padding(.horizontal, 16).padding(.top, 8)
                    
                    }
                    .frame(maxHeight: verticalSizeClass == .compact ? 125 : 320)
                    .onChange(of: editingDimensions) { _, active in if !active { store.updateRigidDimensions() } }

                }

                Spacer()
                if editingDimensions { HStack { Spacer(); Button { editingDimensions = false } label: { Label("Done", systemImage: "checkmark").font(.system(size: 14, weight: .semibold)).foregroundStyle(brightCoral).shadow(color: .red, radius: 4).padding(.horizontal, 15).padding(.vertical, 9).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12)).environment(\.colorScheme, .dark).overlay(RoundedRectangle(cornerRadius: 12).fill(coral.opacity(0.10))).overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(coral, lineWidth: 1).shadow(color: .red, radius: 5)) } }.padding(.horizontal, 18) }
                if !editingDimensions {
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
                }

                if store.trackingMode == .rigid {
                    VStack(spacing: 6) {
                        HStack(spacing: 8) {
                            Button { if showRigidSettings && showCameraSettings { editingDimensions = false; showCameraSettings = false } else { showRigidSettings = true; showCameraSettings = true } } label: {
                                Label("Cube Settings", systemImage: "cube.transparent")
                            }
                            Spacer(minLength: 3)
                            if store.rigidCalibrating {
                                Text("\(store.rigidFaceCount)/5 faces")
                                    .foregroundStyle(brightCoral)
                            } else {
                                Text(store.rigidReady ? "READY" : "NOT CALIBRATED")
                                    .foregroundStyle(store.rigidReady ? .green : brightCoral)
                            }
                            Button(store.rigidCalibrating ? "Finish" : (store.rigidReady ? "Recalibrate" : "Calibrate")) {
                                if store.rigidCalibrating { store.finishRigidCalibration() }
                                else { store.startRigidCalibration() }
                            }
                            .disabled(store.recording)
                        }
                        if store.rigidCalibrating {
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(.white.opacity(0.14))
                                    Capsule().fill(coral).frame(width: geo.size.width * CGFloat(store.rigidFaceCount) / 5.0)
                                }
                            }
                            .frame(height: 4)
                            Text(store.rigidConnectedCount < store.rigidFaceCount ? "Show neighboring faces together to connect them" : "Rotate to show all five faces")
                                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.75))
                        }
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .padding(11)
                    .background(glassRounded(12))
                    .padding(.horizontal, 16).padding(.bottom, 10)
                }

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


                HStack(spacing: 10) {
                    Button {
                        if store.recording { store.end(); CaptureOrientation.unlock() } else { let angle = CaptureOrientation.lock(); store.begin(rotation: angle) }
                    } label: {
                        Label(store.recording ? "STOP" : "RECORD", systemImage: store.recording ? "stop.fill" : "record.circle")
                            .font(.system(size: 15, weight: .bold))
                            .frame(maxWidth: .infinity).frame(height: 52)
                            .background(store.recording ? coral : .white, in: RoundedRectangle(cornerRadius: 14))
                            .shadow(color: coral.opacity(0.45), radius: 11)
                            .foregroundStyle(store.recording ? .white : .black)
                    }
                    .disabled(store.saving)
                    Button { store.refreshTakes(); store.showTakes = true } label: {
                        Image(systemName: "folder")
                            .font(.system(size: 19, weight: .medium))
                            .frame(width: 54, height: 52)
                            .background(glassRounded(14))
                    }
                    .foregroundStyle(.white)
                    .disabled(store.recording || store.saving)
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
            LinearGradient(colors: [.black.opacity(0.53), .black.opacity(0.20), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 110).ignoresSafeArea(edges: .top).allowsHitTesting(false)
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false; CaptureOrientation.unlock(); store.resetOrigin() }
        .onChange(of: store.recording) { _, active in if !active { CaptureOrientation.unlock() } }
        .sheet(isPresented: $store.showTakes) {
            RecordingLibrary(store: store, close: { store.showTakes = false })
        }
    }
}


private struct GlowSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let commit: () -> Void
    private let red = Color(red: 0.88, green: 0.23, blue: 0.30)
    private let thumb = Color(red: 1, green: 0.58, blue: 0.55)
    var body: some View {
        GeometryReader { g in
            let w = max(1, g.size.width - 16)
            let x = CGFloat(min(1, max(0, (value-range.lowerBound)/(range.upperBound-range.lowerBound)))) * w
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.18)).frame(height: 3)
                Capsule().fill(red).frame(width: x, height: 3).shadow(color: red, radius: 4)
                Circle().fill(thumb).frame(width: 14, height: 14).shadow(color: red, radius: 5).offset(x: x-7)
            }.padding(.horizontal, 8).frame(height: 28).contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { d in
                let f = Double(min(1, max(0, (d.location.x-8)/w)))
                value = min(range.upperBound, max(range.lowerBound, range.lowerBound + ((f*(range.upperBound-range.lowerBound))/step).rounded()*step))
            }.onEnded { _ in commit() })
        }.frame(height: 28)
        .accessibilityElement().accessibilityLabel("Adjustment").accessibilityValue(String(format: "%.2f", value))
        .accessibilityAdjustableAction { direction in
            switch direction { case .increment: value = min(range.upperBound, value+step); case .decrement: value = max(range.lowerBound, value-step); @unknown default: break }; commit()
        }
    }
}
private struct GlowToggle: View {
    @Binding var value: Bool
    var body: some View {
        Button { value.toggle() } label: {
            Capsule().fill(value ? Color(red: 0.88, green: 0.23, blue: 0.30) : .white.opacity(0.16))
                .frame(width: 36, height: 20).shadow(color: value ? .red.opacity(0.6) : .clear, radius: 4)
                .overlay(alignment: value ? .trailing : .leading) {
                    Circle().fill(value ? Color(red: 1, green: 0.66, blue: 0.63) : .white.opacity(0.8)).frame(width: 14, height: 14).shadow(color: value ? .red : .clear, radius: 3).padding(3)
                }.frame(minHeight: 32)
        }.buttonStyle(.plain).accessibilityValue(value ? "On" : "Off")
    }
}
