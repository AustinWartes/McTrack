# v0.8.1 AprilTag build configuration fix

Fixes duplicate CMakeLists.txt and README.md outputs caused by XcodeGen treating the entire AprilTag repository as app resources. The GitHub Actions workflow now explicitly registers only root/common AprilTag C library files as compilation inputs, excluding demos and tests. No app behavior changed. This has not been compiled against Xcode in this environment.
