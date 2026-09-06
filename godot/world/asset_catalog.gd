class_name AssetCatalog
extends RefCounted

## The sole mapping from stable compiler asset IDs to Godot resources. MapSpec
## and compiler code must pass an ID such as `tree_oak_01`, never a res:// path.

const DEFINITION_PATHS: Array[String] = [
	"res://data/assets/floor_dirt_large.tres", "res://data/assets/floor_tile_small.tres",
	"res://data/assets/bridge_wood_01.tres",
	"res://data/assets/wall_dungeon_01.tres", "res://data/assets/wall_run_dungeon_01.tres",
	"res://data/assets/wall_doorway_dungeon_01.tres",
	"res://data/assets/barrier_dungeon_01.tres", "res://data/assets/chest_wood_01.tres",
	"res://data/assets/barrel_large_01.tres", "res://data/assets/crates_stacked_01.tres",
	"res://data/assets/torch_lit_01.tres", "res://data/assets/tree_oak_01.tres",
	"res://data/assets/tree_oak_02.tres", "res://data/assets/rock_large_01.tres",
	"res://data/assets/bush_01.tres", "res://data/assets/grass_01.tres",
	"res://data/assets/character_knight_01.tres",
	"res://data/assets/character_rogue_01.tres", "res://data/assets/character_ranger_01.tres",
	"res://data/assets/character_barbarian_01.tres", "res://data/assets/character_mage_01.tres",
	"res://data/assets/character_druid_01.tres", "res://data/assets/character_engineer_01.tres",
]

static var _definitions_by_id: Dictionary[StringName, AssetDefinition] = {}
static var _catalog_loaded := false


static func get_definition(id: StringName) -> AssetDefinition:
	_ensure_loaded()
	return _definitions_by_id.get(id)


static func all_definitions() -> Array[AssetDefinition]:
	_ensure_loaded()
	var definitions: Array[AssetDefinition] = []
	for definition in _definitions_by_id.values():
		definitions.append(definition)
	return definitions


## Tags compose as an AND query: a forest generator can ask for both `tree`
## and `temperate` without knowing anything about scene paths or file layout.
static func find_matching(asset_type: StringName = &"", required_tags := PackedStringArray()) -> Array[AssetDefinition]:
	var matches: Array[AssetDefinition] = []
	for definition in all_definitions():
		if not definition.is_usable():
			continue
		if asset_type != &"" and definition.asset_type != asset_type:
			continue
		if definition.supports_tags(required_tags):
			matches.append(definition)
	return matches


static func can_place(id: StringName, slope_deg: float) -> bool:
	var definition := get_definition(id)
	return definition != null and definition.is_usable() and definition.permits_slope(slope_deg)


static func instantiate(id: StringName) -> Node3D:
	var definition := get_definition(id)
	if definition == null or not definition.is_usable():
		return null
	var packed_scene := load(definition.scene_path) as PackedScene
	return packed_scene.instantiate() if packed_scene != null else null


## Presentation adapter retained for the hand-authored test arena. It resolves
## the same ID-only catalog that the future map compiler uses, then replaces
## only greybox visuals while preserving collision and game-state nodes.
static func dress(anchor: Node3D, id: StringName) -> void:
	var definition := get_definition(id)
	if definition == null:
		return
	var art := instantiate(id)
	if art == null:
		return
	if anchor is MeshInstance3D:
		(anchor as MeshInstance3D).mesh = null
	for child in anchor.get_children():
		if child is MeshInstance3D:
			anchor.remove_child(child)
			child.queue_free()
	art.position = definition.display_offset
	art.rotation.y = definition.display_rotation_y
	anchor.add_child(art)


static func _ensure_loaded() -> void:
	if _catalog_loaded:
		return
	for definition_path in DEFINITION_PATHS:
		var definition := load(definition_path) as AssetDefinition
		if definition == null:
			push_error("Asset catalog definition could not load: %s" % definition_path)
			continue
		if definition.id == &"" or _definitions_by_id.has(definition.id):
			push_error("Asset catalog has an empty or duplicate id at: %s" % definition_path)
			continue
		_definitions_by_id[definition.id] = definition
	_catalog_loaded = true
