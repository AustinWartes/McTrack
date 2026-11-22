# McTrack v0.8 AprilTag integration candidate

This is an **untested integration candidate**, not a verified working IPA. Build it using the GitHub Actions workflow, then review compiler output. The workflow downloads the official AprilRobotics/apriltag C library during build. A network connection on the runner is required.

- Recognizes tagStandard41h12 marker IDs; 88.9 mm printed detection-boundary size.
- Estimates 6DoF pose from camera intrinsics and AprilTag 3 estimate_tag_pose.
- Displays per-ID XYZ axes in SceneKit, throttled to approximately 20 Hz.
- Writes timestamped markerToOrigin poses into markers.json for existing Blender importer.
- Preserves v0.7 Files access, naming, camera recording, and floor placement.
- Does not yet fuse multiple tags into a single rigid-body object.

**Validation required**: GitHub iOS compilation, coordinate-axis orientation, physical marker-size measurement, pose stability, recording throughput, and Blender world-space alignment. Source is not validated on an iPhone or against the AprilTag C compiler here. The C source list in project.yml may require adjustment to match the fetched upstream version. Save your working v0.7 before trying this candidate.
