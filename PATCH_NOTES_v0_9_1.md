# McTrack v0.9.1 — preview and UI candidate

- Preserve marker gizmos across short detection gaps (0.45 s), fading stale poses rather than blinking on each unsuccessful scan. Raw observations remain untouched.
- Rebase the pre-origin ground grid when the raycast target changes height (desk vs floor). Placed origins remain fixed.
- Reduce grid reveal radius to 0.67 m and dot size; use softer coral coloring.
- Compact translucent tracking/resolution/FPS strip; tap-to-cycle retained. Salmon McTrack wordmark and gear button. Recording and Files actions retained.
- Disable automatic iOS idle sleep while the camera view is displayed.
- Settings sheet is informational only; manual camera controls are not enabled because ARKit compatibility is not established.

This is an uncompiled iOS build candidate; test with GitHub Actions before installing.
