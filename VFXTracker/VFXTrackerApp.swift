import SwiftUI
import UIKit

final class CaptureOrientation: NSObject, UIApplicationDelegate {
    static var mask: UIInterfaceOrientationMask = .allButUpsideDown
    static var scene: UIWindowScene? { UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive } }
    static func lock() -> Int {
        let orientation = scene?.interfaceOrientation ?? .portrait
        let angle: Int
        switch orientation {
        case .landscapeLeft: mask = .landscapeLeft; angle = 180
        case .landscapeRight: mask = .landscapeRight; angle = 0
        default: mask = .portrait; angle = 90
        }
        scene?.windows.first?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        return angle
    }
    static func unlock() {
        mask = .allButUpsideDown
        scene?.windows.first?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
    }
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask { Self.mask }
}

@main
struct VFXTrackerApp: App {
    @UIApplicationDelegateAdaptor(CaptureOrientation.self) var delegate
    var body: some Scene { WindowGroup { HomeView().preferredColorScheme(.dark) } }
}

struct HomeView: View {
    @StateObject private var store = TrackingStore()
    @State private var shooting = false
    @State private var library = false
    private let coral = Color(red: 1, green: 0.27, blue: 0.36)
    var body: some View {
        if shooting {
            ContentView(store: store, onHome: { shooting = false })
        } else if library {
            RecordingLibrary(store: store, close: { library = false })
        } else {
            ZStack {
                Color(red: 0.045, green: 0.05, blue: 0.065).ignoresSafeArea()
                VStack(spacing: 24) {
                    HStack(spacing: 0) { Text("Mc").foregroundStyle(.white); Text("Track").foregroundStyle(coral).shadow(color: coral.opacity(0.8), radius: 12) }
                        .font(.system(size: 52, weight: .bold, design: .rounded)).italic()
                    Text("CAMERA  /  OBJECT TRACKING").font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(3).foregroundStyle(.secondary)
                    VStack(spacing: 12) {
                        Button { shooting = true } label: { Label("Start Shooting", systemImage: "viewfinder").frame(maxWidth: .infinity).padding(16).background(coral, in: RoundedRectangle(cornerRadius: 16)).foregroundStyle(.white).shadow(color: coral.opacity(0.35), radius: 12) }
                        Button { store.refreshTakes(); library = true } label: { Label("Recordings", systemImage: "folder").frame(maxWidth: .infinity).padding(16).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.2))).foregroundStyle(.white) }
                    }.font(.system(size: 17, weight: .semibold)).frame(maxWidth: 340)
                }.padding(24)
            }
        }
    }
}
