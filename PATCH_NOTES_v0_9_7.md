# McTrack v0.9.7 — Rigid Cube Prototype + Coral UI

## Prototype workflow
1. Select **Rigid** with the tracking-mode cycle button.
2. Open **Cube Settings**. Set the actual printed tag detection boundary (default **75 mm**) and the outside cube edge length (initial guess **90 mm**; measure your cube).
3. Tap **Calibrate**. Rotate the cube slowly so neighboring tag faces are visible in the **same frame**. The app automatically discovers IDs and collects relative transforms; no manual ID entry.
4. Tap **Finish**. The app requires all five *connected* tag faces with three simultaneous samples per neighboring pair; it will report incomplete calibration if that is not met. For a full five-face model, keep scanning until all five IDs are connected, then finish.
5. Record in Rigid mode. A fused rigid controller is previewed, and `rigid.json` is exported alongside the unchanged `tracking.json` and `markers.json`.
6. Use the bundled Blender importer to create **McTrack Rigid Cube** as a keyframed Empty with an editable cube-size display. Original per-ID tag empties remain available.

## Important prototype limitations
- This is an **initial calibration and pose-fusion prototype**, not a production-quality multi-view optimizer. It estimates cube pose from per-face AprilTag poses, with basic averaging and disagreement rejection; no offline refinement, Kalman filter, or robust global bundle adjustment yet.
- Only observed poses are keyframed. If no configured tag is visible, no rigid sample is produced; the last preview remains visible.
- Calibration learns relative face poses from simultaneous detections, not a moving-cube world trajectory. For a complete cube, ensure the overlap graph connects all five faces.
- Calibration is saved on device and can be replaced by recalibration. Changing tag size or cube dimensions **requires recalibrating** for accurate physical scale and cube-center placement.
- 75 mm must be the tag's detector-corner-to-corner size, not the paper border. Cube outside edge must be measured; it cannot be inferred reliably from tag size alone without assumptions.
- The tag pose coordinate convention and cube-center offset should be validated with an actual cube recording in Blender before relying on centimeter-level measurements.
- iOS compilation and device rendering have **not** been verified here. Swift source was syntax-parsed and Blender importer was Python-compiled.

## Visual
- Replaced grid PNG with a **4096×4096** RGBA texture. Increased grid-line visibility, introduced a small bright peach dot core, and deep red-coral halo. Expanded ground reveal fade for greater visible coverage.
- Rebuilt origin target as a **1024×1024** transparent texture with matching dot/ring glow colors and two rings with bright stroke centers and saturated edges.
- Restored stronger translucent sleeves on origin gizmo, retained pastel tag gizmo colors, and added a small separate rigid-object preview axes.
- Refined logo: white glow on Mc, bracket-matched coral fill for Track, lighter fine edge and stronger coral halo.
