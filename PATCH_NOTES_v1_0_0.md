# v1.0.0 release candidate
- Custom inline settings: EV compensation and automatic/manual white balance, rigid dimensions and axis length. Camera settings depend on ARKit device support; verify on device.
- Light material UI; original target/grid/logo unchanged.
- New calibration coordinate system: unpaired top normal defines Z, plane fit estimates center, consistent opposite face spacing can correct effective detector tag size using measured cube edge. Recalibrate once after upgrade. Calibration scale correction assumes a five-face cube with known physical edge.
- Confidence/angle-weighted consensus fusion; no temporal smoothing or synthetic samples.
- Extended blue axis, no depth occlusion; existing cube edge depth rendering retained.
- Blender per-take Camera, AprilTags and Rigid Body collections; raw tags hidden in rigid mode, mesh render disabled.
- Validation: Swift syntax parse and Python bytecode compile only. No iOS SDK or Blender runtime available here.
