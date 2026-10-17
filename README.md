# niri-tablet setup

This repository contains a portable installer for a Niri-based tablet setup with touchscreen gestures, an on-screen keyboard toggle, and rotation helpers.

## Files

- `setup.sh` — bootstraps dependencies, builds Niri from upstream, applies tablet patches, installs the binary, and links a gesture configuration.
- `gestures.kdl` — the default touchscreen gesture configuration.
- `scripts/` — helper utilities for OSK toggle and screen rotation.
- `pkg/` — place the niri-tablet patch files here before running the installer.

## Quick usage

```bash
chmod +x setup.sh
./setup.sh
```

The script expects patch files in `pkg/` named like `0001-...patch` so they can be applied with `git am` or `git apply`.
