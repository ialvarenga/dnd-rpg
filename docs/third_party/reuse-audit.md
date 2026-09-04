# Reuse audit

## A1 — Tactical Slash camera inspection

| Field | Record |
| --- | --- |
| Repository | https://github.com/sion-rgb/tactical-slash |
| Inspected commit | `8bf8d835cb7afa7cb3f4d893b0966c6b4e9b7727` |
| License verified | MIT License, copyright 2026 Sion RGB (`LICENSE` at the inspected commit) |
| Inspected file | `scripts/camera/camera_controller.gd` |
| Result | No source code copied or adapted. |

The camera was suitable as a behavioral reference: target focus, target yaw,
target zoom, exponential smoothing, and world-relative panning. It was not a
low-coupling transplant because it extends `Camera3D` directly and is coupled
to Tactical Slash's input/controller flow. A local Godot 4.6 implementation
instead uses the planned `CameraRig -> Pivot -> Camera3D` hierarchy in
`godot/view/tactical_camera_rig.gd`. It contains no Tactical Slash source and
therefore does not introduce a copied-code attribution requirement.
