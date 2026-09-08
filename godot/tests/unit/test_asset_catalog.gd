class_name TestAssetCatalog
extends RefCounted

## B1 contract tests: the catalog is data-driven, IDs are the only public
## lookup key, and placement/query policy comes from AssetDefinition resources.


static func run() -> Dictionary:
	var failures: Array[String] = []
	_test_definitions_load_and_have_unique_ids(failures)
	_test_id_lookup_never_accepts_a_resource_path(failures)
	_test_tagged_type_query_is_deterministic(failures)
	_test_placement_respects_asset_slope_policy(failures)
	_test_catalog_assets_are_loadable(failures)
	_test_dress_uses_catalog_metadata(failures)
	_test_catalog_and_audit_csv_ids_match(failures)
	return {"name": "unit/test_asset_catalog", "failures": failures}


static func _test_definitions_load_and_have_unique_ids(failures: Array[String]) -> void:
	var definitions := AssetCatalog.all_definitions()
	_expect(not definitions.is_empty(), "asset catalog has no definitions", failures)
	_expect(definitions.size() == AssetCatalog.DEFINITION_PATHS.size(), "one or more asset definition resources did not load", failures)
	var seen := {}
	for definition in definitions:
		_expect(definition.id != &"", "asset definition has an empty id", failures)
		_expect(not seen.has(definition.id), "asset definition id '%s' is duplicated" % definition.id, failures)
		_expect(definition.asset_type != &"", "asset '%s' has no type" % definition.id, failures)
		_expect(definition.footprint_radius > 0.0, "asset '%s' has no footprint" % definition.id, failures)
		seen[definition.id] = true


static func _test_id_lookup_never_accepts_a_resource_path(failures: Array[String]) -> void:
	_expect(AssetCatalog.get_definition(&"tree_oak_01") != null, "known asset id was not found", failures)
	_expect(AssetCatalog.get_definition(&"res://assets/kaykit_forest/Tree_1_A_Color1.gltf") == null, "catalog must not accept raw resource paths", failures)
	_expect(AssetCatalog.get_definition(&"does_not_exist") == null, "unknown asset id was found", failures)


static func _test_tagged_type_query_is_deterministic(failures: Array[String]) -> void:
	var trees := AssetCatalog.find_matching(&"vegetation", PackedStringArray(["temperate", "tree"]))
	var tree_ids: Array[StringName] = []
	for tree in trees:
		tree_ids.append(tree.id)
	_expect(not tree_ids.is_empty(), "tree query returned no definitions", failures)
	_expect(tree_ids.has(&"tree_oak_01") and tree_ids.has(&"tree_oak_02"), "tree query omitted legacy definitions: %s" % str(tree_ids), failures)
	var sorted_ids := tree_ids.duplicate()
	sorted_ids.sort()
	_expect(tree_ids == sorted_ids, "tree query was not stable and sorted: %s" % str(tree_ids), failures)
	for tree in trees:
		_expect(tree.asset_type == &"vegetation" and tree.tags.has("tree"), "tree query returned a non-tree: %s" % tree.id, failures)


static func _test_placement_respects_asset_slope_policy(failures: Array[String]) -> void:
	_expect(AssetCatalog.can_place(&"tree_oak_01", 27.0), "tree should permit its maximum slope", failures)
	_expect(not AssetCatalog.can_place(&"tree_oak_01", 27.1), "tree should reject slopes over its maximum", failures)
	_expect(not AssetCatalog.can_place(&"tree_oak_01", -1.0), "tree should reject a negative slope", failures)
	_expect(not AssetCatalog.can_place(&"res://assets/kaykit_forest/Tree_1_A_Color1.gltf", 1.0), "placement must require an asset id", failures)


static func _test_catalog_assets_are_loadable(failures: Array[String]) -> void:
	for definition in AssetCatalog.all_definitions():
		_expect(definition.is_usable(), "asset '%s' scene is not loadable: %s" % [definition.id, definition.scene_path], failures)


static func _test_dress_uses_catalog_metadata(failures: Array[String]) -> void:
	var anchor := MeshInstance3D.new()
	anchor.mesh = BoxMesh.new()
	AssetCatalog.dress(anchor, &"character_knight_01")
	_expect(anchor.mesh == null, "dress did not clear the greybox mesh", failures)
	_expect(anchor.get_child_count() == 1, "dress did not instantiate catalog art", failures)
	var art := anchor.get_child(0) as Node3D
	_expect(art != null and art.position == Vector3(0, -0.9, 0), "dress did not apply catalog display offset", failures)
	_expect(art != null and is_equal_approx(art.rotation.y, PI), "dress did not apply catalog display rotation", failures)
	anchor.free()


static func _test_catalog_and_audit_csv_ids_match(failures: Array[String]) -> void:
	var csv_ids := _read_audit_csv_ids(failures)
	var catalog_ids: Array[String] = []
	for definition in AssetCatalog.all_definitions():
		catalog_ids.append(String(definition.id))
	for id in catalog_ids:
		_expect(csv_ids.has(id), "docs/third_party/assets.csv is missing a row for '%s'" % id, failures)
	for id in csv_ids:
		# The audit also records non-placeable audio bundles; only catalogued
		# world assets participate in this bidirectional catalog contract.
		if id.begins_with("sfx_"):
			continue
		_expect(catalog_ids.has(id), "docs/third_party/assets.csv has a row for '%s' with no matching catalog definition" % id, failures)


static func _read_audit_csv_ids(failures: Array[String]) -> Array[String]:
	var project_dir := ProjectSettings.globalize_path("res://")
	var csv_path := project_dir.trim_suffix("/").get_base_dir() + "/docs/third_party/assets.csv"
	var file := FileAccess.open(csv_path, FileAccess.READ)
	if file == null:
		failures.append("could not open docs/third_party/assets.csv at %s" % csv_path)
		return []
	var header := file.get_csv_line()
	_expect(header == PackedStringArray(["asset", "source", "author", "license", "download_date", "local_path", "modified"]), "assets.csv header does not match the documented schema", failures)
	var ids: Array[String] = []
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.size() > 0 and row[0] != "":
			ids.append(row[0])
	file.close()
	return ids


static func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
