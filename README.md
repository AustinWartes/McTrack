# McTrack v0.2 (iPhone prototype)

This is a **development prototype**, not a verified production build. It has not yet been compiled against the iOS SDK in this environment. GitHub Actions is the first compilation test.

## What's new

- ARKit horizontal-plane raycast and circular reticle with fading ground dots
- Tap the live camera preview to set the floor/origin
- Solid positive XYZ axes and dashed negative axes, with Reset Origin
- Save takes automatically in `On My iPhone > McTrack > Takes` (enable Files app visibility via Info.plist)
- Portrait H.264 `.mov` video, microphone AAC audio (when permission granted), JSON camera tracking and metadata
- In-app Saved Takes list, no automatic share sheet
- McTrack name and a replaceable icon

## Windows build and installation

1. Replace your existing GitHub repository source files with the contents of this folder, preserving `.github` and the project root layout.
2. Commit and push to `main` using GitHub Desktop.
3. GitHub Actions runs `Build unsigned iOS app` and produces an unsigned IPA artifact.
4. Download the artifact, extract the IPA, and use Sideloadly to install it on your iPhone as before.
5. Trust the developer profile in iOS Settings > General > VPN & Device Management if needed.

## Custom app icon

Replace `VFXTracker/Assets.xcassets/AppIcon.appiconset/AppIcon.png` with your own **1024 x 1024 pixel PNG**. Use RGB, opaque/no alpha channel, no pre-rounded corners. Keep the filename `AppIcon.png`. Commit and push again to rebuild.

## First tests

1. Launch the app and grant camera **and microphone** access.
2. Scan a well-lit textured floor; a circular reticle should appear near screen center.
3. Tap the camera view to set the origin. Move around to confirm the XYZ gizmo remains fixed to the floor.
4. Record a short take, stop, and wait for `Take saved`.
5. Open the iOS **Files** app > **On My iPhone** > **McTrack** > **Takes**. Each take should contain `video.mov`, `tracking.json`, and `metadata.json`.
6. Play the MOV and check video orientation, audio, and sync. If audio is absent, check microphone permission and `metadata.json`'s `audioStatus`.
7. Inspect `tracking.json` to verify samples contain `cameraToOrigin`, timestamp, tracking state, and camera intrinsics.

## Known limitations / items requiring on-device validation

- This version is untested against Xcode/iOS and may need build fixes.
- ARKit frame buffers are sensor-oriented. The app rotates and center-crops them into a portrait 1080 x 1920 MOV. **A future Blender importer must adjust camera intrinsics for the exact rotation/crop**. This version preserves original intrinsics and raw image dimensions, but does not yet export crop-adjusted intrinsics.
- ARKit frame timestamps and microphone capture PTS should be based on the device host clock, but AV synchronization needs on-device validation, especially at take start/stop.
- Frame encoding can drop frames under load. Tracking data is collected from ARKit frames, not guaranteed one sample per encoded video frame.
- Horizontal plane raycasts may initially use estimated geometry. For accurate floor placement, wait for stable tracking and a well-observed floor.
- The Saved Takes sheet is a simple list; the Files app is the primary way to manage/copy take folders.
- There is no Blender importer or AprilTag prop tracking yet.

## v0.4 floor visualization

- Flat unlit textured reticle, with opaque coral rings and white center.
- Stationary world-space 5 m dot grid, revealed with a radial shader centered at the moving placement reticle. No sphere dots or torus shadow.
- Raycast updates target approximately 30 Hz, up from ~11 Hz. Actual refresh varies with ARKit and device load.
- Existing recording and output mode controls remain unchanged.

## Blender preview importer

Install `BlenderAddon/mctrack_import.py` via Blender Preferences > Add-ons > Install from Disk, enable it, then File > Import > McTrack Take. It accepts a ZIP containing `tracking.json`, `metadata.json`, and `video.mov` or a direct `tracking.json` path with neighboring files. This is a **preview** importer. Camera animation and video background are included, but the exact optical intrinsics-to-portrait-crop calibration, principal point, and video-to-pose timing still require a calibration test before pixel-accurate VFX use. Blender's camera background display is not a compositing node setup.

To make a take ZIP on Windows, compress the contents of a `Take_...` folder together, ensuring `tracking.json`, `metadata.json`, and `video.mov` are present. Do not delete originals. In-app ZIP packaging can be added next.

## Five-face AprilTag cube plan

Use five unique IDs from the same `tagStandard41h12` family, one on the top and one on each of four sides. The bottom stays unmarked for the handle. Measure physical cube side length and printed tag black/white border size. The AprilTag 3 C detector will be added to the iOS project in a subsequent version; this revision does not yet include marker tracking.
