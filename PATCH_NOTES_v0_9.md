# McTrack v0.9 — Tracking modes and AprilTag responsiveness

- Camera (default): AprilTag detection skipped entirely.
- Tags: independent AprilTag detection and marker export.
- Rigid: future placeholder; no tag detection or fusion yet.
- Mode cycling is locked during recording; no background refinement UI yet.
- Detector attempts up to 30 scans/sec (not a guarantee of 30 successful detections).
- Removed additional `decision_margin < 15` rejection; raw decision margin remains available in observations.
- Live marker preview hides absent markers rather than retaining stale positions.
- Increased dot-grid radial feather and opacity for a more visible fade.
- All camera recording, tracking, and Blender import logic otherwise retained.

**Build status:** Source-level changes only. Xcode/GitHub Actions iOS build and on-device behavior have not been tested in this environment.

**Next:** Test fast lateral tag movements, track stability, recording/import and whether scan throughput affects recording. `quad_decimate=2` remains unchanged pending measured performance.
