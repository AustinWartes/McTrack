import SwiftUI
import UIKit
import ARKit
import AVFoundation

struct ContentView: View {
    @StateObject private var store = TrackingStore()
    @State private var coordinator: ARCameraView.Coordinator?
    @State private var showCameraSettings = false
    private let coral = Color(red: 0.96, green: 0.43, blue: 0.42)
    private let glass = Color.black.opacity(0.25)

    private func glassCapsule(active: Bool = false) -> some View {
        Capsule()
            .fill(.ultraThinMaterial)
            .overlay(Capsule().fill(Color.black.opacity(0.19)))
            .overlay(Capsule().stroke(active ? coral.opacity(0.95) : .white.opacity(0.30), lineWidth: active ? 1.5 : 0.8))
            .shadow(color: active ? coral.opacity(0.85) : .clear, radius: 11)
            .shadow(color: active ? coral.opacity(0.48) : .clear, radius: 22)
    }
    private func glassRounded(_ radius: CGFloat = 18, active: Bool = false) -> some View {
        RoundedRectangle(cornerRadius: radius)
            .fill(.ultraThinMaterial)
            .overlay(RoundedRectangle(cornerRadius: radius).fill(.black.opacity(0.19)))
            .overlay(RoundedRectangle(cornerRadius: radius).stroke(active ? coral : .white.opacity(0.25), lineWidth: 1))
            .shadow(color: active ? coral.opacity(0.70) : .clear, radius: 12)
    }
    private var framedWordmark: some View {
        (Text("Mc").foregroundColor(.white) + Text("Track").foregroundColor(coral))
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
                    .stroke(coral, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .shadow(color: coral, radius: 5)
                    .shadow(color: coral.opacity(0.85), radius: 12)
                }
            }
            .shadow(color: coral.opacity(0.35), radius: 8)
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
                            .shadow(color: showCameraSettings ? coral.opacity(0.95) : coral.opacity(0.22), radius: showCameraSettings ? 16 : 5)
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
                    .background(glassRounded(active: true))
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
                        Label(store.trackingMode.title, systemImage: store.trackingMode.symbol)
                            .foregroundStyle(coral)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(glassCapsule(active: true))
                    }
                    .disabled(store.recording)
                    .accessibilityLabel("Cycle tracking mode")
                    Rectangle().fill(.white.opacity(0.2)).frame(width: 1, height: 20)
                    Button { store.cycleResolution() } label: {
                        Text(store.resolution == 2160 ? "4K" : "1080p")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(store.recording || !store.supports4K)
                    Rectangle().fill(.white.opacity(0.2)).frame(width: 1, height: 20)
                    Button { store.cycleFPS() } label: {
                        Text("\(store.fps) FPS").frame(maxWidth: .infinity)
                    }
                    .disabled(store.recording)
                }
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 9).padding(.vertical, 6)
                .background(glassRounded())
                .padding(.horizontal, 16).padding(.bottom, 12)

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
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
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

