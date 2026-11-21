# McTrack v0.6 (preview)

- Ground-grid dots: 28% lower peak alpha and slightly smaller reveal radius.
- Blender camera: flipped local roll 180 degrees from v0.5; needs on-device take verification.
- Blender camera: millimeter lens mode, intrinsics-derived focal length keyframed for every tracked frame. Uses a virtual 36 mm filmback, not a claim about the physical iPhone sensor.
- Blender camera: quaternion animation to avoid Euler discontinuities.
- Blender ZIP import: extracts next to the ZIP in `<zip-name>_extracted`, not system temp.
- Existing origin controller and MOV background retained.

AprilTag detection is **not yet implemented**. This release does not pretend to track markers. The next milestone is to integrate the native AprilTag 3 C detector and verify camera-relative tag pose using real printed marker dimensions.

Note: uncompiled Swift/untested Blender runtime. Test first on a short recording.
