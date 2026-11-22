# v0.8.2 build fix

Exclude apriltag_pywrap.c and Python bindings from the iOS source list. This addresses the missing Python.h error from the v0.8.1 GitHub Actions build. iOS compilation remains unverified until GitHub Actions completes.
