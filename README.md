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
