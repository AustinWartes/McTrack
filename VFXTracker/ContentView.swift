import SwiftUI
import UIKit
import ARKit
import AVFoundation

struct ContentView: View {
    @StateObject private var store = TrackingStore()
    @State private var coordinator: ARCameraView.Coordinator?
    @State private var showCameraSettings = false
    private let coral = Color(red: 0.96, green: 0.43, blue: 0.42)
    private let glass = Color.black.opacity(0.37)

    var body: some View {
        ZStack {
            ARCameraView(store: store, coordinatorRef: $coordinator)
                .ignoresSafeArea()
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "viewfinder")
                        .foregroundStyle(coral)
                        .font(.system(size: 19, weight: .medium))
                    (Text("Mc").foregroundColor(.white) + Text("Track").foregroundColor(coral))
                        .font(.system(size: 23, weight: .bold, design: .rounded))
                        .italic()
                    Spacer()
                    Text(store.status == "Tracking normal" ? "● TRACKING" : "● LIMITED")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(store.status == "Tracking normal" ? .green : .yellow)
                    Button { showCameraSettings.toggle() } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 19))
                            .frame(width: 42, height: 42)
                            .background(glass, in: Circle())
                            .overlay(Circle().stroke(showCameraSettings ? coral : .white.opacity(0.22), lineWidth: 1))
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
                    .background(glass, in: RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(coral.opacity(0.45), lineWidth: 1))
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
                            .background(glass, in: Capsule())
                            .overlay(Capsule().stroke(coral.opacity(0.45), lineWidth: 1))
                    } else {
                        Label(store.canPlaceOrigin ? "Tap to Set Origin" : "Scan Surface", systemImage: "scope")
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 13).padding(.vertical, 11)
                            .background(glass, in: Capsule())
                            .overlay(Capsule().stroke(coral.opacity(0.45), lineWidth: 1))
                    }
                }
                .padding(.horizontal, 18).padding(.bottom, 12)

                HStack(spacing: 7) {
                    Button { store.cycleTrackingMode() } label: {
                        Label(store.trackingMode.title, systemImage: store.trackingMode.symbol)
                            .frame(maxWidth: .infinity)
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
                .padding(.horizontal, 12).padding(.vertical, 13)
                .background(glass, in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.23), lineWidth: 1))
                .padding(.horizontal, 16).padding(.bottom, 12)

                HStack(spacing: 10) {
                    Button {
                        if store.recording { store.end() } else { store.begin() }
                    } label: {
                        Label(store.recording ? "STOP" : "RECORD", systemImage: store.recording ? "stop.fill" : "record.circle")
                            .font(.system(size: 15, weight: .bold))
                            .frame(maxWidth: .infinity).frame(height: 52)
                            .background(store.recording ? coral : .white, in: RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(store.recording ? .white : .black)
                    }
                    Button { store.refreshTakes(); store.showTakes = true } label: {
                        Image(systemName: "folder")
                            .font(.system(size: 19, weight: .medium))
                            .frame(width: 54, height: 52)
                            .background(glass, in: RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.24), lineWidth: 1))
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

