# McTrack v0.7 groundwork (NOT AprilTag detector release)

- Completed takes renamed `Take_001_MM-DD-YY_hh-mm-AM` using local time. Persistent numbering via UserDefaults.
- Explicit Files sharing keys in XcodeGen project settings; in-app Files location and launcher.
- Added capture clock, stabilization, and lens-source descriptions to metadata.
- Blender importer v0.4 supports future `markers.json` observations containing `id`, `elapsedSeconds`, and column-major `markerToOrigin` matrices.
- Does NOT contain AprilTag 3 C detector or live tracking. This requires vendor integration and iOS build verification.
- ARKit intrinsic calibration, especially principal-point shifts and sensor crop, remains unverified. No fabricated stabilization correction or fake 24mm lens value.
- Existing working camera pipeline and UI retained.
