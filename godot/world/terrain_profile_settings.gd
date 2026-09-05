class_name TerrainProfileSettings
extends Resource

## Data-only tuning for the deterministic terrain generator. Feature sizes are
## measured in world metres so terrain detail does not stretch with map bounds.

@export var amplitude_m := 0.0
@export var feature_size_m := 48.0
@export_range(1, 8, 1) var octaves := 1
@export_range(1.0, 4.0, 0.05) var lacunarity := 2.0
@export_range(0.05, 1.0, 0.05) var persistence := 0.5
@export var warp_amplitude_m := 0.0
@export var hard_slope_deg := 35.0
