class_name AssetDefinition
extends Resource

## A compiler-facing description of one reusable world asset. Scene paths stay
## here, at the engine boundary; MapSpec and compiler callers use `id` only.

@export var id: StringName
@export var scene_path: String
@export var asset_type: StringName
@export var tags := PackedStringArray()
@export_range(0.0, 100.0, 0.01, "suffix:m") var footprint_radius := 0.0
@export_range(0.0, 90.0, 0.1, "suffix:°") var placement_max_slope_deg := 90.0
@export var blocks_navigation := false
@export var display_offset := Vector3.ZERO
@export var display_rotation_y := 0.0


func is_usable() -> bool:
	return not scene_path.is_empty() and ResourceLoader.exists(scene_path)


func supports_tags(required_tags: PackedStringArray) -> bool:
	for required_tag in required_tags:
		if not tags.has(required_tag):
			return false
	return true


func permits_slope(slope_deg: float) -> bool:
	return is_finite(slope_deg) and slope_deg >= 0.0 and slope_deg <= placement_max_slope_deg
