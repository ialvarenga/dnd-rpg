# Dependencies

## A0 / A1

| Name | Version / pin | License | Why used | Update strategy |
| --- | --- | --- | --- | --- |
| Godot Engine | 4.6.x | MIT | Runtime and GDScript toolchain | Upgrade deliberately after headless checks pass |

No third-party source code, plugins, assets, or test framework have been
copied or installed in this milestone. The tests use a small local headless
runner to avoid adding a framework before the Reuse Spike. Tactical Slash was
inspected as a MIT-licensed camera reference; the outcome is documented in
`reuse-audit.md` and does not add it as a dependency.
