# v0.9.4 — Gradient Stroke and Color Correction

- Removed the offset white secondary strokes on glass capsules, rounded panels, and wordmark brackets. Replaced them with a single coral-to-bright-coral gradient stroke.
- Tightened logo bracket stroke and added a subtle coral glow to the wordmark text.
- Tracking mode label now uses white text with a coral icon.
- Reduced grid dot radius from 6.1 to 4.5 texture pixels and replaced near-white centers with luminous light-coral centers; maintained saturated coral outer falloff.
- Reverted added halo sleeves on 3D gizmo/tag geometry, keeping the base tracking visualization.
- Camera tracking, AprilTag detector, capture, and Blender import remain unchanged.

Build must be verified with GitHub Actions; Swift and iPhone appearance are not validated locally.
