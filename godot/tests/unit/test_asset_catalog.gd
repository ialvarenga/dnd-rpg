class_name TestAssetCatalog
extends RefCounted

## A10 minimal-art scaffold: proves AssetCatalog.dress() is a no-op while a
## prop id has no sourced art (today's real state -- see
## docs/third_party/assets.csv) and swaps in real art once a manifest entry
## points at a loadable scene, without depending on any real art actually
## being downloaded yet.

const FAKE_ART_PATH := "res://tests/fakes/fake_art_prop.tscn"


## Ids in MANIFEST that have no scene path yet -- see docs/third_party/assets.csv.
const UNSOURCED_IDS: Array[StringName] = [&"floor_generic", &"door_wood_01"]


static func run() -> Dictionary:
	var failures: Array[String] = []
	_test_has_art_false_for_unsourced_entries(failures)
	_test_has_art_true_for_sourced_entries(failures)
	_test_has_art_false_for_unknown_id(failures)
	_test_has_art_true_for_loadable_scene_path(failures)
	_test_has_art_false_for_scene_path_that_does_not_resolve(failures)
	_test_dress_is_noop_without_art_on_wrapper_anchor(failures)
	_test_dress_is_noop_without_art_on_mesh_anchor(failures)
	_test_dress_swaps_wrapper_anchor_mesh_child_for_art(failures)
	_test_dress_swaps_mesh_anchor_itself_for_art(failures)
	_test_dress_positions_art_at_the_given_offset(failures)
	_test_dress_rotates_art_by_the_given_yaw(failures)
	_test_catalog_and_audit_csv_ids_match(failures)
	return {"name": "unit/test_asset_catalog", "failures": failures}


static func _test_has_art_false_for_unsourced_entries(failures: Array[String]) -> void:
	for id in UNSOURCED_IDS:
		_expect(not AssetCatalog.has_art(id), "MANIFEST entry '%s' should have no sourced art yet" % id, failures)


static func _test_has_art_true_for_sourced_entries(failures: Array[String]) -> void:
	for id in AssetCatalog.MANIFEST:
		if UNSOURCED_IDS.has(id):
			continue
		_expect(AssetCatalog.has_art(id), "MANIFEST entry '%s' should resolve to real art" % id, failures)


static func _test_has_art_false_for_unknown_id(failures: Array[String]) -> void:
	_expect(not AssetCatalog.has_art(&"does_not_exist"), "unknown id should never report art", failures)


static func _test_has_art_true_for_loadable_scene_path(failures: Array[String]) -> void:
	var manifest := {&"fake_prop": FAKE_ART_PATH}
	_expect(AssetCatalog.has_art(&"fake_prop", manifest), "has_art should be true for a loadable scene path", failures)


static func _test_has_art_false_for_scene_path_that_does_not_resolve(failures: Array[String]) -> void:
	var manifest := {&"fake_prop": "res://tests/fakes/does_not_exist.tscn"}
	_expect(not AssetCatalog.has_art(&"fake_prop", manifest), "has_art should be false for a scene path that does not resolve", failures)


static func _test_dress_is_noop_without_art_on_wrapper_anchor(failures: Array[String]) -> void:
	var anchor := Node3D.new()
	var mesh_child := MeshInstance3D.new()
	mesh_child.name = "Mesh"
	anchor.add_child(mesh_child)
	AssetCatalog.dress(anchor, &"floor_generic")
	_expect(anchor.get_child_count() == 1 and anchor.get_child(0) == mesh_child, "dress() should not touch a wrapper anchor when no art is sourced", failures)
	anchor.free()


static func _test_dress_is_noop_without_art_on_mesh_anchor(failures: Array[String]) -> void:
	var anchor := MeshInstance3D.new()
	var original_mesh := BoxMesh.new()
	anchor.mesh = original_mesh
	AssetCatalog.dress(anchor, &"door_wood_01")
	_expect(anchor.mesh == original_mesh, "dress() should not clear a mesh anchor's own mesh when no art is sourced", failures)
	anchor.free()


static func _test_dress_swaps_wrapper_anchor_mesh_child_for_art(failures: Array[String]) -> void:
	var anchor := Node3D.new()
	var mesh_child := MeshInstance3D.new()
	mesh_child.name = "Mesh"
	anchor.add_child(mesh_child)
	var manifest := {&"fake_prop": FAKE_ART_PATH}
	AssetCatalog.dress(anchor, &"fake_prop", manifest)
	_expect(not is_instance_valid(mesh_child) or mesh_child.get_parent() != anchor, "dress() did not remove the greybox MeshInstance3D child", failures)
	_expect(anchor.find_child("FakeArtRoot", true, false) != null, "dress() did not add the loaded art scene as a child", failures)
	anchor.free()


static func _test_dress_swaps_mesh_anchor_itself_for_art(failures: Array[String]) -> void:
	var anchor := MeshInstance3D.new()
	anchor.mesh = BoxMesh.new()
	var manifest := {&"fake_prop": FAKE_ART_PATH}
	AssetCatalog.dress(anchor, &"fake_prop", manifest)
	_expect(anchor.mesh == null, "dress() did not clear the mesh anchor's own greybox mesh", failures)
	_expect(anchor.find_child("FakeArtRoot", true, false) != null, "dress() did not add the loaded art scene as a child of the mesh anchor", failures)
	anchor.free()


## Real KayKit art rarely shares the greybox fallback's centered pivot (see
## TestArenaController._dress_arena_props()); dress() must place the
## instantiated art at the caller-given offset instead of always at (0,0,0).
static func _test_dress_positions_art_at_the_given_offset(failures: Array[String]) -> void:
	var anchor := Node3D.new()
	var manifest := {&"fake_prop": FAKE_ART_PATH}
	var offset := Vector3(0, -0.9, 0)
	AssetCatalog.dress(anchor, &"fake_prop", manifest, offset)
	var art := anchor.find_child("FakeArtRoot", true, false)
	_expect(art != null and (art as Node3D).position == offset, "dress() did not place the art at art_offset", failures)
	anchor.free()


## A model authored facing the opposite of the anchor's forward convention
## (e.g. Knight.glb vs. CharacterView's local -Z forward -- see A10's
## backward-walking bug) needs a caller-supplied yaw correction on the art
## itself, independent of art_offset.
static func _test_dress_rotates_art_by_the_given_yaw(failures: Array[String]) -> void:
	var anchor := Node3D.new()
	var manifest := {&"fake_prop": FAKE_ART_PATH}
	AssetCatalog.dress(anchor, &"fake_prop", manifest, Vector3.ZERO, PI)
	var art := anchor.find_child("FakeArtRoot", true, false)
	_expect(art != null and is_equal_approx((art as Node3D).rotation.y, PI), "dress() did not apply art_rotation_y to the art", failures)
	anchor.free()


## Catches the two ways the catalog and the license/audit trail can drift:
## a new prop id with nothing recorded for compliance, or a stale audit row
## left behind after a prop id is renamed or removed.
static func _test_catalog_and_audit_csv_ids_match(failures: Array[String]) -> void:
	var initial_failures := failures.size()
	var csv_ids := _read_audit_csv_ids(failures)
	if failures.size() > initial_failures:
		return
	var catalog_ids: Array = AssetCatalog.MANIFEST.keys()
	for id in catalog_ids:
		_expect(csv_ids.has(String(id)), "docs/third_party/assets.csv is missing a row for catalog id '%s'" % id, failures)
	for id in csv_ids:
		_expect(catalog_ids.has(StringName(id)), "docs/third_party/assets.csv has a row for '%s' with no matching AssetCatalog entry" % id, failures)


static func _read_audit_csv_ids(failures: Array[String]) -> Array:
	var project_dir: String = ProjectSettings.globalize_path("res://")
	var repo_root: String = project_dir.trim_suffix("/").get_base_dir()
	var csv_path := repo_root + "/docs/third_party/assets.csv"
	var file := FileAccess.open(csv_path, FileAccess.READ)
	if file == null:
		failures.append("could not open docs/third_party/assets.csv at %s" % csv_path)
		return []
	var header := file.get_csv_line()
	_expect(
		header == PackedStringArray(["asset", "source", "author", "license", "download_date", "local_path", "modified"]),
		"assets.csv header does not match the documented schema",
		failures,
	)
	var ids: Array = []
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.size() == 1 and row[0] == "":
			continue
		ids.append(row[0])
	file.close()
	return ids


static func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
