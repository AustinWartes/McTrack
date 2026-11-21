# VFX Tracker

Early iPhone prototype for ARKit camera tracking and timestamped transform export.

## Current prototype scope

- Portrait-first ARKit camera preview
- ARKit world tracking (camera position and orientation)
- Visual XYZ reference gizmo
- Record timestamped camera-to-world transforms
- Export JSON through the iOS share sheet

Not included yet: AprilTag prop tracking, video/audio recording, Blender importer, multi-camera support.

## Build from Windows

This repository uses GitHub Actions as a remote macOS build machine because native iOS app builds require Xcode/macOS.

1. Create a GitHub account if you do not already have one.
2. Create a **public** repository named `VFXTracker`.
3. Upload all files from this project folder to the repository root. Keep the `.github` folder.
4. Open the repository's **Actions** tab and enable Actions if GitHub asks.
5. Push/commit the files to the `main` branch. The workflow should start automatically.
6. When the workflow finishes, open the run, scroll to **Artifacts**, and download `VFXTracker-unsigned-IPA`.
7. Extract the ZIP. It contains `VFXTracker-unsigned.ipa`.

## Install on your iPhone from Windows

An unsigned IPA cannot be installed directly. It must be signed with your Apple ID.

1. Install Sideloadly from its official site: https://sideloadly.io/
2. Connect the iPhone to the Windows PC with a data-capable USB cable. Unlock the phone and tap **Trust** if prompted.
3. Open Sideloadly, select your iPhone, and drag `VFXTracker-unsigned.ipa` into the IPA field.
4. Enter your Apple ID when Sideloadly requests it. Use Apple's normal app-specific signing flow; never give your Apple ID password to an unofficial website.
5. Start the sideload. Follow any Apple trust/developer-mode prompts shown on the iPhone.
6. With a free Apple account, personal app signing is temporary and typically needs refreshing about every 7 days. Sideloadly can refresh while the phone is connected. A paid Apple Developer membership avoids that particular short expiration and is needed for normal public App Store distribution.

Apple and Sideloadly requirements can change. Only download Sideloadly from its official site and review its current instructions.

## First test

1. Open the app and allow camera access.
2. Use it in a well-lit room with visible texture and detail. Avoid a blank wall.
3. Move the phone slowly around a small object or room, keeping the phone orientation steady initially.
4. Confirm the tracking status becomes **Tracking: Normal**.
5. Tap **RECORD**, move the phone for 10-20 seconds, then tap **STOP**.
6. Tap the share icon and save the JSON to Files, iCloud Drive, or send it to your PC.
7. Inspect the file: it should contain many samples, each with a 16-value camera transform and elapsed time.

## Important notes

- The first tracking origin is established when the AR session starts. The visual XYZ gizmo is placed 1.5 m in front of the initial camera as a visible reference; it is not the actual world-origin marker.
- ARKit world tracking is visual-inertial tracking, not surveyed motion capture. It can drift or become limited if lighting, texture, or motion conditions are poor.
- This is a development prototype, not a calibrated camera solve. Lens intrinsics, video plate recording, orientation metadata, and Blender import will be added and validated in later milestones.
- The JSON matrix is the ARKit camera transform in column-major order. Do not assume Blender axis conventions match without applying a coordinate conversion in the importer.
