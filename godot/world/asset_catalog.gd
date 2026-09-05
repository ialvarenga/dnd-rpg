class_name AssetCatalog
extends RefCounted

## Fase A10 minimal-art scaffold. Each prop id names a real PackedScene once
## docs/third_party/assets.csv gets a matching row and MANIFEST points at it;
## until then `dress()` no-ops and the greybox mesh already placed in the
## scene (e.g. test_arena.tscn) keeps rendering. Real art can land later by
## editing data here instead of touching arena scenes or sim/ code.
##
## Ids listed here must have a matching row in docs/third_party/assets.csv --
## unit/test_asset_catalog.gd checks both directions so the two never drift.

const MANIFEST: Dictionary = {
	&"floor_generic": "",
	&"wall_generic": "res://assets/kaykit_dungeon/wall_run_5.tscn",
	&"obstacle_tree_a": "res://assets/kaykit_forest/Tree_1_A_Color1.gltf",
	&"obstacle_tree_b": "res://assets/kaykit_forest/Tree_3_A_Color1.gltf",
	&"obstacle_barrier": "res://assets/kaykit_forest/Rock_3_R_Color1.gltf",
	&"door_wood_01": "",
	&"character_hero_placeholder": "res://assets/kaykit_adventurers/Knight.glb",
	&"chest_wood_01": "res://assets/kaykit_dungeon/chest.gltf",
}


static func has_art(id: StringName, manifest: Dictionary = MANIFEST) -> bool:
	var scene_path: String = manifest.get(id, "")
	return scene_path != "" and ResourceLoader.exists(scene_path)


## Swaps `anchor`'s own mesh (when `anchor` is itself a MeshInstance3D) and
## any MeshInstance3D children for the real art scene when `id` resolves to
## one; otherwise leaves `anchor` untouched so the existing greybox mesh
## keeps rendering.
##
## `art_offset` positions the instantiated art relative to `anchor`. It
## exists because the greybox fallback (centered on `anchor`) and real KayKit
## art (usually pivoted at its own base or center) rarely share a pivot
## convention -- callers compute the offset that puts the real art on the
## ground given `anchor`'s existing, collision-driven position.
##
## `art_rotation_y` corrects for art authored facing a different axis than
## the anchor's own forward convention (e.g. CharacterView steers assuming
## local -Z is "forward" -- a model authored facing +Z needs PI here or it
## visibly walks backward while still turning toward the correct heading).
static func dress(anchor: Node3D, id: StringName, manifest: Dictionary = MANIFEST, art_offset: Vector3 = Vector3.ZERO, art_rotation_y: float = 0.0) -> void:
	if not has_art(id, manifest):
		return
	var art: Node3D = (load(manifest[id]) as PackedScene).instantiate()
	if anchor is MeshInstance3D:
		(anchor as MeshInstance3D).mesh = null
	for child in anchor.get_children():
		if child is MeshInstance3D:
			anchor.remove_child(child)
			child.queue_free()
	art.position = art_offset
	art.rotation.y = art_rotation_y
	anchor.add_child(art)
