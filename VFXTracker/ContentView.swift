import SwiftUI
import ARKit

struct ContentView: View {
    @StateObject private var store = TrackingStore()
    @State private var showingExportError = false
    @State private var exportError = ""

    var body: some View {
        ZStack {
            ARCameraView(store: store)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("VFX TRACKER")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .tracking(1.6)
                        Text(store.trackingDescription)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(store.trackingDescription == "Tracking: Normal" ? .green : .yellow)
                    }
                    Spacer()
                    Text("CAM 01")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(.black.opacity(0.55), in: Capsule())
                }
                .padding(16)
                .background(.black.opacity(0.45))

                Spacer()

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.isRecording ? "RECORDING TRACK" : "READY")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(store.isRecording ? .red : .white)
                        Text("\(store.sampleCount) samples")
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                    }
                    Spacer()
                    if store.isRecording {
                        Circle().fill(.red).frame(width: 9, height: 9)
                    }
                }
                .padding(14)
                .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 16)

                HStack(spacing: 12) {
                    Button {
                        if store.isRecording {
                            store.stopRecording()
                        } else {
                            let timestamp = ARSession().currentFrame?.timestamp ?? ProcessInfo.processInfo.systemUptime
                            store.startRecording(at: timestamp)
                        }
                    } label: {
                        Label(store.isRecording ? "STOP" : "RECORD", systemImage: store.isRecording ? "stop.fill" : "record.circle")
                            .font(.system(size: 15, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(store.isRecording ? Color.red : Color.white, in: RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(store.isRecording ? .white : .black)
                    }

                    Button {
                        do {
                            _ = try store.makeExport()
                        } catch {
                            exportError = error.localizedDescription
                            showingExportError = true
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(width: 54, height: 52)
                            .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(.white)
                    }
                    .disabled(store.sampleCount == 0)
                    .opacity(store.sampleCount == 0 ? 0.4 : 1)
                }
                .padding(16)
                .background(.black.opacity(0.55))
            }
        }
        .sheet(item: Binding(
            get: { store.exportURL.map(ExportItem.init) },
            set: { _ in store.exportURL = nil }
        )) { item in
            ShareSheet(activityItems: [item.url])
                .presentationDetents([.medium, .large])
        }
        .alert("Export failed", isPresented: $showingExportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError)
        }
    }
}

private struct ExportItem: Identifiable {
    let id = UUID()
    let url: URL
    init(_ url: URL) { self.url = url }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
