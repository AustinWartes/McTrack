# McTrack v0.9.2 — luminous glass / AprilTag preview

- Separate skipped detector scans from completed scans with zero detections; 31Hz tolerance for nominal 30Hz source.
- Preserve last known marker gizmo indefinitely until mode change, at 48% opacity after 0.2 seconds without a new observation. No interpolated or fabricated recording samples.
- Clear marker preview on mode changes.
- Add glowing tag-boundary brackets, high-intensity coral ground dot halos, subtle connecting grid lines, and glowing origin reticle.
- Add a four-corner framed wordmark, SwiftUI ultraThinMaterial controls, coral active mode and settings glow, and restrained record-button halo.
- Preserve existing ARKit camera tracking, capture, file export, Blender importer, and surface-selection behavior.

NOTE: No local Xcode build available. Compile and install via GitHub Actions as usual. No manual white balance/exposure controls or offline refinement are included.
