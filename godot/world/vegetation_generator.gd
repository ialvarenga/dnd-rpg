class_name VegetationGenerator
extends RefCounted

## B6 placement-only generator. Rendering remains catalog scene instantiation
## for now; a MultiMesh adapter can consume these deterministic placements later.

const GENERATOR_VERSION := "1.0"


func generate(region: Dictionary, map_seed: int, terrain: TerrainProvider, reserved: Array[Dictionary] = []) -> Array[Dictionary]:
	var vegetation: Dictionary = region.get("vegetation", {})
	if vegetation.get("profile", "none") == "none" or not terrain.is_initialized:
		return []
	var polygon := _to_polygon(region.get("polygon", []))
	if polygon.size() < 3:
		return []
	var profile := String(vegetation.get("profile", "temperate_sparse"))
	var density := float(vegetation.get("density", 0.5))
	var candidates := AssetCatalog.find_matching(&"vegetation", PackedStringArray(["temperate"]))
	if candidates.is_empty():
		return []
	var rng := RandomNumberGenerator.new()
	rng.seed = derive_seed(map_seed, String(region.get("id", "")), GENERATOR_VERSION)
	var spacing := lerpf(8.0, 3.5, clampf(density, 0.0, 1.0))
	if profile == "temperate_dense":
		spacing *= 0.75
	var placed: Array[Dictionary] = []
	var rect := _polygon_rect(polygon)
	for xi in range(floori(rect.position.x / spacing), ceili(rect.end.x / spacing)):
		for zi in range(floori(rect.position.y / spacing), ceili(rect.end.y / spacing)):
			var point := Vector2(float(xi) * spacing + rng.randf_range(-spacing * 0.35, spacing * 0.35), float(zi) * spacing + rng.randf_range(-spacing * 0.35, spacing * 0.35))
			if not _point_in_polygon(point, polygon) or not terrain.is_query_in_bounds(point.x, point.y):
				continue
			var definition: AssetDefinition = candidates[rng.randi_range(0, candidates.size() - 1)]
			if not definition.permits_slope(terrain.slope_at(point.x, point.y)) or _conflicts(point, definition.footprint_radius, reserved, placed):
				continue
			placed.append({"id": &"generated_%s_%d" % [region.get("id", "region"), placed.size()], "asset": definition.id, "position": Vector3(point.x, terrain.height_at(point.x, point.y), point.y), "rotation_y": rng.randf_range(0.0, TAU), "radius": definition.footprint_radius, "generated": true})
	return placed


static func derive_seed(map_seed: int, region_id: String, generator_version: String = GENERATOR_VERSION) -> int:
	var value := 216613626
	# Iterating Unicode code points avoids engine-dependent String.hash().
	var input := str(map_seed) + "|" + region_id + "|" + generator_version
	for index in input.length():
		value = int(posmod(value * 16777619 + input.unicode_at(index), 2147483647))
	return value


func _conflicts(point: Vector2, radius: float, reserved: Array[Dictionary], placed: Array[Dictionary]) -> bool:
	for item in reserved + placed:
		var other: Vector2 = item.get("point", Vector2(item.get("position", Vector3.ZERO).x, item.get("position", Vector3.ZERO).z))
		if point.distance_to(other) < radius + float(item.get("radius", 0.0)):
			return true
	return false


func _to_polygon(raw: Array) -> PackedVector2Array:
	var polygon := PackedVector2Array()
	for point in raw:
		if point is Array and point.size() == 2:
			polygon.append(Vector2(float(point[0]), float(point[1])))
	return polygon


func _polygon_rect(polygon: PackedVector2Array) -> Rect2:
	var rect := Rect2(polygon[0], Vector2.ZERO)
	for point in polygon:
		rect = rect.expand(point)
	return rect


func _point_in_polygon(point: Vector2, polygon: PackedVector2Array) -> bool:
	return Geometry2D.is_point_in_polygon(point, polygon)
