import SwiftUI
import UIKit
import ARKit
import AVFoundation

struct ContentView: View {
    @StateObject private var store = TrackingStore()
    @State private var coordinator: ARCameraView.Coordinator?

    var body: some View {
        ZStack {
            ARCameraView(store: store, coordinatorRef: $coordinator)
                .ignoresSafeArea()
            VStack(spacing: 0) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("McTrack")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                        Text(store.status)
                            .font(.system(size: 11))
                            .foregroundStyle(store.status == "Tracking normal" ? .green : .yellow)
                    }
                    Spacer()
                    if store.hasOrigin {
                        Button("Reset Origin") { coordinator?.resetPlacement() }
                            .disabled(store.recording)
                            .font(.system(size: 12, weight: .semibold))
                    } else {
                        Text(store.canPlaceOrigin ? "TAP TO SET ORIGIN" : "SCAN FLOOR")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
                .padding(.horizontal, 18).padding(.vertical, 12)
                .background(.black.opacity(0.42))
                Spacer()
                HStack(spacing: 10) {
                    Button {
                        if store.recording { store.end() } else { store.begin() }
                    } label: {
                        Label(store.recording ? "STOP" : "RECORD", systemImage: store.recording ? "stop.fill" : "record.circle")
                            .font(.system(size: 15, weight: .bold))
                            .frame(maxWidth: .infinity).frame(height: 52)
                            .background(store.recording ? .red : .white, in: RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(store.recording ? .white : .black)
                    }
                    Button { store.refreshTakes(); store.showTakes = true } label: {
                        Image(systemName: "folder")
                            .font(.system(size: 19, weight: .medium))
                            .frame(width: 54, height: 52)
                            .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 14))
                    }
                    .foregroundStyle(.white)
                }
                .padding(.horizontal, 16)
                Text(store.message)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.top, 7).padding(.bottom, 12)
            }
        }
        .onAppear { AVCaptureDevice.requestAccess(for: .audio) { _ in } }
        .sheet(isPresented: $store.showTakes) {
            NavigationStack {
                List {
                    ForEach(store.takes, id: \.path) { folder in
                        ShareLink(item: folder, preview: SharePreview(folder.lastPathComponent)) {
                            Label(folder.lastPathComponent, systemImage: "folder")
                        }
                    }
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

