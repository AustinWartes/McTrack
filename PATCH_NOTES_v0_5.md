# McTrack v0.5 candidate fixes

- Fixed vertical reveal inversion (ground plane UV V axis).
- Recenter 5 m dot plane when reticle moves >1.5 m from grid center, snapped to 5 cm steps.
- Blender importer: use MOVIE_CLIP background with bpy.data.movieclips.load, rather than invalid MOVIE enum.
- Blender importer: create McTrack Scene Controller Empty and parent animated camera.
- Apply portrait camera local roll correction of -90 degrees; **verify orientation with a real take**. If the video appears rotated the other way, change sign in `portrait_correction`.

**Not compiled or tested on iPhone or Blender.** Confirm portrait correction and framing against an actual recording. Full pixel-accurate intrinsics and lens shift calibration still pending.
