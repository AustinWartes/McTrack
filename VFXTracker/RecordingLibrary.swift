import SwiftUI
import AVKit
import AVFoundation
import simd

struct RecordingLibrary: View {
    @ObservedObject var store: TrackingStore
    var close: () -> Void
    var body: some View {
        NavigationStack {
            List(store.takes, id: \.path) { folder in
                NavigationLink { TakePlayback(folder: folder) } label: {
                    Label(folder.lastPathComponent, systemImage: "film").font(.subheadline)
                }
            }
            .navigationTitle("Recordings")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done", action: close) } }
            .overlay { if store.takes.isEmpty { ContentUnavailableView("No recordings", systemImage: "film", description: Text("Start shooting to create a recording.")) } }
            .onAppear { store.refreshTakes() }
        }
    }
}

private struct PlaybackMetadata: Decodable {
    var videoRotationDegrees: Int?
    var videoPixelSize: [Int]?
    var videoOrientation: String?
    var originSelected: Bool?
    var rigidAxisLength: Double?
}
private struct PlaybackMarker: Decodable { let id: Int; let arTimestamp: Double; let markerToOrigin: [Float] }
private struct PlaybackMarkers: Decodable { let observations: [PlaybackMarker]; let tagSizeMeters: Double }
private struct PlaybackRigid: Decodable { let samples: [RigidSample]; let cubeEdgeMeters: Double }
private struct TimedPose { let time: Double; let matrix: simd_float4x4 }
private func matrix(_ a: [Float]) -> simd_float4x4? {
    guard a.count == 16, a.allSatisfy({ $0.isFinite }) else { return nil }
    return simd_float4x4(columns: (SIMD4(a[0],a[1],a[2],a[3]), SIMD4(a[4],a[5],a[6],a[7]), SIMD4(a[8],a[9],a[10],a[11]), SIMD4(a[12],a[13],a[14],a[15])))
}
private func bracket<T>(_ a: [T], _ t: Double, _ time: (T)->Double) -> (Int,Int) {
    var lo = 0, hi = a.count
    while lo < hi { let mid = (lo+hi)/2; if time(a[mid]) < t { lo = mid+1 } else { hi = mid } }
    return (max(0,lo-1), min(a.count-1,lo))
}
private func pose(_ a: [TimedPose], _ t: Double, gap: Double) -> simd_float4x4? {
    guard !a.isEmpty else { return nil }
    let (i,j) = bracket(a,t,{$0.time}); let x = a[i], y = a[j]
    if abs(x.time-t) < 0.00001 { return x.matrix }; if abs(y.time-t) < 0.00001 { return y.matrix }
    guard i != j, t >= x.time, t <= y.time, y.time-x.time <= gap else { return nil }
    let f = Float((t-x.time)/(y.time-x.time))
    let q = simd_slerp(simd_quatf(x.matrix),simd_quatf(y.matrix),f)
    var m = simd_float4x4(q); m.columns.3 = x.matrix.columns.3*(1-f)+y.matrix.columns.3*f; return m
}
private final class PlaybackData: ObservableObject {
    let player: AVPlayer
    let folder: URL
    let cameras: [TrackSample]
    let cameraPoses: [TimedPose]
    let markers: [Int:[TimedPose]]
    let rigid: [TimedPose]
    let edge: Float
    let tagSize: Float
    let axisLength: Float
    let angle: Int
    let width: CGFloat
    let height: CGFloat
    let first: Double
    let originSelected: Bool
    @Published var time: Double = 0
    @Published var duration: Double = 0
    @Published var playing = false
    @Published var hasAudio = false
    @Published var muted = true
    func toggleMute() { muted.toggle(); player.isMuted = muted; if !muted { try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback); try? AVAudioSession.sharedInstance().setActive(true) } }
    private var observer: Any?
    init(folder: URL) {
        self.folder = folder
        func load<T: Decodable>(_ name: String, _ type: T.Type) -> T? { guard let data = try? Data(contentsOf: folder.appendingPathComponent(name)) else { return nil }; return try? JSONDecoder().decode(type,from:data) }
        let c = load("tracking.json",TrackFile.self)?.samples.sorted { $0.arTimestamp < $1.arTimestamp } ?? []
        cameras = c
        cameraPoses = c.compactMap { s in matrix(s.cameraToOrigin).map { TimedPose(time:s.arTimestamp,matrix:$0) } }
        let m = load("markers.json",PlaybackMarkers.self)
        markers = Dictionary(grouping: m?.observations ?? [],by:{$0.id}).mapValues { $0.compactMap { s in matrix(s.markerToOrigin).map { TimedPose(time:s.arTimestamp,matrix:$0) } }.sorted { $0.time < $1.time } }
        let r = load("rigid.json",PlaybackRigid.self)
        rigid = (r?.samples ?? []).compactMap { s in matrix(s.rigidToOrigin).map { TimedPose(time:s.arTimestamp,matrix:$0) } }.sorted { $0.time < $1.time }
        edge = Float(r?.cubeEdgeMeters ?? 0.09); tagSize = Float(m?.tagSizeMeters ?? 0.0889)
        let meta = load("metadata.json",PlaybackMetadata.self)
        axisLength = Float(meta?.rigidAxisLength ?? 1.0)
        angle = meta?.videoRotationDegrees ?? (meta?.videoOrientation == "landscape" ? 0 : 90)
        let dims = meta?.videoPixelSize ?? [1080,1920]
        width = CGFloat(dims.first ?? 1080); height = CGFloat(dims.last ?? 1920)
        first = load("video_timestamps.json",[Double].self)?.first ?? c.first?.arTimestamp ?? 0
        originSelected = meta?.originSelected ?? true
        player = AVPlayer(url: folder.appendingPathComponent("video.mov"))
        player.isMuted = true
        Task { @MainActor [weak self] in
            guard let self, let asset = self.player.currentItem?.asset else { return }
            self.hasAudio = ((try? await asset.loadTracks(withMediaType: .audio)) ?? []).isEmpty == false
        }
        observer = player.addPeriodicTimeObserver(forInterval: CMTime(value:1,timescale:60),queue:.main) { [weak self] t in
            guard let self else { return }; self.time = t.seconds.isFinite ? t.seconds : 0
            let d = self.player.currentItem?.duration.seconds ?? 0; self.duration = d.isFinite ? max(0,d) : 0
            self.playing = self.player.rate != 0
        }
    }
    deinit { if let observer { player.removeTimeObserver(observer) } }
    func draw(_ ctx: GraphicsContext, _ size: CGSize, origin: Bool, tags: Bool, cube: Bool, axis: Bool) {
        let t = first + time
        guard !cameras.isEmpty, let cam = pose(cameraPoses,t,gap:0.15) else { return }
        let (i,j) = bracket(cameras,t,{$0.arTimestamp}); let k = abs(cameras[i].arTimestamp-t) < abs(cameras[j].arTimestamp-t) ? cameras[i] : cameras[j]
        let inv = simd_inverse(cam)
        let iw = CGFloat(k.imageWidth), ih = CGFloat(k.imageHeight)
        guard iw > 0, ih > 0, width > 0, height > 0 else { return }
        let rw = angle % 180 == 0 ? iw : ih, rh = angle % 180 == 0 ? ih : iw
        let crop = max(width/rw,height/rh), fit = min(size.width/width,size.height/height)
        func project(_ v: SIMD4<Float>) -> CGPoint? {
            let p = inv*v; guard p.z < -0.01 else { return nil }
            let u = CGFloat(k.fx*p.x / -p.z+k.cx), v = CGFloat(k.cy-k.fy*p.y / -p.z)
            let xy: CGPoint
            switch angle { case 90: xy = CGPoint(x:ih-v,y:u); case 180: xy = CGPoint(x:iw-u,y:ih-v); case 270: xy = CGPoint(x:v,y:iw-u); default: xy = CGPoint(x:u,y:v) }
            return CGPoint(x:(xy.x*crop-(rw*crop-width)/2)*fit+(size.width-width*fit)/2,y:(xy.y*crop-(rh*crop-height)/2)*fit+(size.height-height*fit)/2)
        }
        func line(_ m: simd_float4x4,_ a: SIMD3<Float>,_ b: SIMD3<Float>,_ color: Color) {
            var aa = a, bb = b
            let localToCamera: simd_float4x4 = simd_mul(inv, m)
            let pa: SIMD4<Float> = simd_mul(localToCamera, SIMD4<Float>(a.x, a.y, a.z, 1))
            let pb: SIMD4<Float> = simd_mul(localToCamera, SIMD4<Float>(b.x, b.y, b.z, 1))
            let near: Float = -0.02
            if pa.z >= near && pb.z >= near { return }
            if pa.z >= near { aa = a + (b-a)*((near-pa.z)/(pb.z-pa.z)) }
            if pb.z >= near { bb = b + (a-b)*((near-pb.z)/(pa.z-pb.z)) }
            guard let x = project(m*SIMD4(aa.x,aa.y,aa.z,1)), let y = project(m*SIMD4(bb.x,bb.y,bb.z,1)) else { return }
            var path = Path(); path.move(to:x); path.addLine(to:y); ctx.stroke(path,with:.color(color),style:StrokeStyle(lineWidth:2,lineCap:.round))
        }
        func axes(_ m: simd_float4x4,_ length: Float) { line(m,.zero,SIMD3(length,0,0),.red); line(m,.zero,SIMD3(0,length,0),.green); line(m,.zero,SIMD3(0,0,length),.blue) }
        let coral = Color(red:1,green:0.35,blue:0.43)
        if origin && originSelected { axes(matrix_identity_float4x4,0.28) }
        if tags { for (id, track) in markers { if let m = pose(track,t,gap:0.15) { axes(m,0.065); let h = tagSize/2; let p:[SIMD3<Float>] = [SIMD3(-h,-h,0),SIMD3(h,-h,0),SIMD3(h,h,0),SIMD3(-h,h,0)]; for n in 0..<4 { line(m,p[n],p[(n+1)%4],coral) }; if let pt = project(m.columns.3) { ctx.draw(Text("TAG \(id)").font(.caption2).foregroundColor(.white),at:CGPoint(x:pt.x,y:pt.y-14)) } } } }
        if cube, let m = pose(rigid,t,gap:0.15) { let h = edge/2; let p:[SIMD3<Float>] = [SIMD3(-h,-h,-h),SIMD3(h,-h,-h),SIMD3(h,h,-h),SIMD3(-h,h,-h),SIMD3(-h,-h,h),SIMD3(h,-h,h),SIMD3(h,h,h),SIMD3(-h,h,h)]; for (a,b) in [(0,1),(1,2),(2,3),(3,0),(4,5),(5,6),(6,7),(7,4),(0,4),(1,5),(2,6),(3,7)] { line(m,p[a],p[b],coral) }; axes(m,edge); if axis { line(m,SIMD3(0,0,-axisLength/2),SIMD3(0,0,axisLength/2),Color(red:0.65,green:0.78,blue:1)) } }
    }
}
private struct TakePlayback: View {
    @StateObject private var data: PlaybackData
    @State private var origin = true
    @State private var tags = false
    @State private var cube = true
    @State private var axis = true
    init(folder: URL) { _data = StateObject(wrappedValue:PlaybackData(folder:folder)) }
    var body: some View {
        VStack(spacing: 8) {
            ZStack { PlayerSurface(player:data.player); Canvas { ctx,size in data.draw(ctx,size,origin:origin,tags:tags,cube:cube,axis:axis) }.allowsHitTesting(false) }.clipped()
            HStack { Button { if data.playing { data.player.pause() } else { if data.time >= data.duration-0.05 { data.player.seek(to:.zero) }; data.player.play() } } label: { Image(systemName:data.playing ? "pause.fill":"play.fill").frame(width:32) }; Slider(value:Binding(get:{min(data.time,max(data.duration,0.01))},set:{ data.time=$0; data.player.seek(to:CMTime(seconds:$0,preferredTimescale:60000),toleranceBefore:.zero,toleranceAfter:.zero) }),in:0...max(data.duration,0.01)); Text(String(format:"%.1fs",data.time)).font(.caption.monospacedDigit()) }
            HStack { Toggle("Origin",isOn:$origin); Toggle("Tags",isOn:$tags).disabled(data.markers.isEmpty); Toggle("Cube",isOn:$cube).disabled(data.rigid.isEmpty); Toggle("Z Axis",isOn:$axis).disabled(data.rigid.isEmpty || !cube) }.toggleStyle(.button).font(.caption)
            Text("Replay overlays · short gaps interpolated, longer gaps hidden").font(.caption2).foregroundStyle(.secondary)
        }.padding(10).navigationTitle(data.folder.lastPathComponent).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItemGroup(placement:.topBarTrailing) { Button { data.toggleMute() } label: { Image(systemName: data.muted ? "speaker.slash.fill" : "speaker.wave.2.fill") }.disabled(!data.hasAudio).accessibilityLabel(data.hasAudio ? (data.muted ? "Unmute" : "Mute") : "No recorded audio"); ShareLink(item:data.folder,preview:SharePreview(data.folder.lastPathComponent)) { Image(systemName:"square.and.arrow.up") } } }
            .onDisappear { data.player.pause(); try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
    }
}
private struct PlayerSurface: UIViewRepresentable {
    let player: AVPlayer
    final class Surface: UIView { override class var layerClass: AnyClass { AVPlayerLayer.self } }
    func makeUIView(context:Context)->Surface { let v=Surface(); let l=v.layer as! AVPlayerLayer; l.player=player; l.videoGravity = .resizeAspect; v.backgroundColor = .black; return v }
    func updateUIView(_ v:Surface,context:Context) { (v.layer as! AVPlayerLayer).player=player }
}
