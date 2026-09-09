class_name VegetationGenerator
extends RefCounted

## Deterministic scatter generator. Rendering remains catalog scene
## instantiation for now; a MultiMesh adapter can consume these placements
## later, which is why `max_instances` exists as a backstop.
##
## Four models stack to make the result read as a stand of plants rather than a
## lattice of props:
##   1. Bridson variable-radius Poisson-disk sampling -- blue noise, so there is
##      a guaranteed minimum gap and no visible grid.
##   2. Lewis-Shedler thinning against an fBm field -- density varies across the
##      region, carving clearings and groves instead of uniform soup.
##   3. A reverse-J (de Liocourt) size law -- stem count falls off with trunk
##      size the way an uneven-aged stand does, so giants stay rare.
##   4. A Thomas cluster process for undergrowth -- grass and bushes grow in
##      clumps around a parent, which blue noise alone never produces.

const GENERATOR_VERSION := "2.0"
const PROFILE_PATH := "res://data/vegetation/%s.tres"
const FALLBACK_PROFILE := "temperate_sparse"
const FAMILIES := ["tree", "bush", "grass", "rock"]
## Families that clump and that fill the gaps the canopy leaves open.
const UNDERGROWTH := ["bush", "grass"]
## Bridson's k: candidates tried around an active point before it is retired.
const CANDIDATE_TRIES := 12
const SEED_TRIES := 96
const MAX_RESEEDS := 48
const INDEX_CELL_M := 4.0
## Clear floor kept around anything that blocks, so a stand can never pack
## itself into a wall. Derived from MapNavigationCompiler's 0.45m character
## clearance plus enough margin for its 1m reachability grid to sample the gap.
const WALK_GAP_M := 1.05
## How far apart a clearing pushes its scatter, relative to the profile's normal
## spacing. Rejection alone could not open a clearing: Bridson simply retries a
## rejected candidate until one lands, so the field has to widen the exclusion
## radius instead of gambling on acceptance.
const CLEARING_SPREAD := 2.5

static var _profile_cache := {}


## A uniform-grid neighbour index. Anything larger than one cell falls back to a
## linear list, which keeps hills and wall runs from inflating the cell size.
class SpatialIndex:
	extends RefCounted

	var _cell := 1.0
	var _cells := {}
	var _oversized: Array[Dictionary] = []

	func _init(cell_size: float) -> void:
		_cell = maxf(cell_size, 0.5)

	func add(point: Vector2, radius: float) -> void:
		if radius > _cell:
			_oversized.append({"point": point, "radius": radius})
			return
		var key := Vector2i(floori(point.x / _cell), floori(point.y / _cell))
		if not _cells.has(key):
			_cells[key] = []
		_cells[key].append({"point": point, "radius": radius})

	func conflicts(point: Vector2, radius: float) -> bool:
		for item in _oversized:
			if point.distance_to(item.point) < radius + float(item.radius):
				return true
		var base := Vector2i(floori(point.x / _cell), floori(point.y / _cell))
		var span := ceili((radius + _cell) / _cell)
		for x_offset in range(-span, span + 1):
			for z_offset in range(-span, span + 1):
				for item in _cells.get(base + Vector2i(x_offset, z_offset), []):
					if point.distance_to(item.point) < radius + float(item.radius):
						return true
		return false


func generate(region: Dictionary, map_seed: int, terrain: TerrainProvider, reserved: Array[Dictionary] = []) -> Array[Dictionary]:
	var vegetation: Dictionary = region.get("vegetation", {})
	var profile := String(vegetation.get("profile", "none"))
	if profile == "none" or not terrain.is_initialized:
		return []
	var polygon := _to_polygon(region.get("polygon", []))
	if polygon.size() < 3:
		return []
	var candidates := AssetCatalog.find_matching(&"vegetation", PackedStringArray(["temperate"]))
	if candidates.is_empty():
		return []
	var settings := load_profile(profile)
	var families := _group_by_family(candidates, settings.size_lambda)
	if families.is_empty():
		return []
	var region_id := String(region.get("id", "region"))
	var seed_value := derive_seed(map_seed, region_id, GENERATOR_VERSION)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	# Authored density still sets the baseline gap; the profile decides how much
	# of a canopy radius neighbours are allowed to interlock on top of that.
	var density := clampf(float(vegetation.get("density", 0.5)), 0.0, 1.0)
	var spacing_scale := lerpf(1.6, 0.75, density) * (1.0 - settings.canopy_overlap)
	# A cap that simply stops the fill would leave the rest of the polygon bare,
	# because Bridson grows outward from its seeds. Coarsen the whole stand
	# instead: for a disc process the count scales with 1/spacing squared, so
	# this lands near the cap while still covering the region.
	var spacing_boost := 1.0
	var estimate := 0.22 * _polygon_area(polygon) / pow(maxf(_mean_spacing(families, settings, spacing_scale), 0.1), 2.0)
	if estimate > float(settings.max_instances):
		spacing_boost = sqrt(estimate / float(settings.max_instances))
	var canopy_noise := _density_field(seed_value, settings)
	var undergrowth_noise := _density_field(seed_value + 7919, settings)
	var placed_index := SpatialIndex.new(INDEX_CELL_M)
	var reserved_index := SpatialIndex.new(INDEX_CELL_M)
	for item in reserved:
		reserved_index.add(_item_point(item), float(item.get("radius", 0.0)))
	var context := {
		"polygon": polygon, "rect": _polygon_rect(polygon), "terrain": terrain, "rng": rng,
		"settings": settings, "families": families, "spacing_scale": spacing_scale, "spacing_boost": spacing_boost,
		"canopy_noise": canopy_noise, "undergrowth_noise": undergrowth_noise,
		"placed_index": placed_index, "reserved_index": reserved_index,
		"region_id": region_id, "placed": [] as Array[Dictionary],
	}
	var active: Array[Dictionary] = []
	var reseeds := 0
	while context.placed.size() < settings.max_instances and reseeds < MAX_RESEEDS:
		if active.is_empty():
			var seeded := _seed_point(context)
			if seeded.is_empty():
				break
			active.append(seeded)
			reseeds += 1
			continue
		var index := rng.randi_range(0, active.size() - 1)
		var parent: Dictionary = active[index]
		var grown := false
		for _attempt in CANDIDATE_TRIES:
			var child := _grow_from(context, parent)
			if child.is_empty():
				continue
			active.append(child)
			grown = true
			break
		if not grown:
			active.remove_at(index)
	return context.placed


## Bridson's dart throwing, with the annulus sized from both radii so a sapling
## can tuck in where a full canopy could not.
func _grow_from(context: Dictionary, parent: Dictionary) -> Dictionary:
	var rng: RandomNumberGenerator = context.rng
	var choice := _pick_asset(context, "")
	if choice.is_empty():
		return {}
	var gap: float = parent.spacing + choice.spacing
	var angle := rng.randf() * TAU
	var distance := lerpf(gap, gap * 2.0, rng.randf())
	var point: Vector2 = parent.point + Vector2(cos(angle), sin(angle)) * distance
	return _try_place(context, point, choice)


func _seed_point(context: Dictionary) -> Dictionary:
	var rng: RandomNumberGenerator = context.rng
	var rect: Rect2 = context.rect
	for _attempt in SEED_TRIES:
		var point := Vector2(rng.randf_range(rect.position.x, rect.end.x), rng.randf_range(rect.position.y, rect.end.y))
		var choice := _pick_asset(context, "")
		if choice.is_empty():
			return {}
		var placement := _try_place(context, point, choice)
		if not placement.is_empty():
			return placement
	return {}


## One sample: the family and model are already rolled, so this gates on the
## polygon, terrain slope, and both neighbour indices -- with the density field
## widening the exclusion radius wherever the stand should open into a clearing.
func _try_place(context: Dictionary, point: Vector2, choice: Dictionary, allow_clump := true) -> Dictionary:
	var terrain: TerrainProvider = context.terrain
	if point.x < 0.0 or point.y < 0.0 or point.x > terrain.bounds.x or point.y > terrain.bounds.y:
		return {}
	if not _point_in_polygon(point, context.polygon) or not terrain.is_query_in_bounds(point.x, point.y):
		return {}
	var rng: RandomNumberGenerator = context.rng
	var noise: FastNoiseLite = context.undergrowth_noise if choice.family in UNDERGROWTH else context.canopy_noise
	var spacing: float = float(choice.spacing) * lerpf(CLEARING_SPREAD, 1.0, _field_strength(noise, point, context.settings.density_contrast))
	var definition: AssetDefinition = choice.definition
	if not definition.permits_slope(terrain.slope_at(point.x, point.y)):
		return {}
	# Reserved areas -- hills, walls, structures, earlier regions -- are cleared
	# against the full canopy footprint. Only same-region scatter is allowed to
	# interlock, and only by the profile's canopy_overlap.
	if context.reserved_index.conflicts(point, definition.footprint_radius):
		return {}
	if context.placed_index.conflicts(point, spacing):
		return {}
	var placed: Array[Dictionary] = context.placed
	var placement := {
		"id": StringName("generated_%s_%d" % [context.region_id, placed.size()]),
		"asset": definition.id,
		"position": Vector3(point.x, terrain.height_at(point.x, point.y), point.y),
		"rotation_y": rng.randf_range(0.0, TAU),
		"radius": definition.footprint_radius,
		"generated": true,
	}
	placed.append(placement)
	context.placed_index.add(point, spacing)
	if allow_clump and choice.family in UNDERGROWTH:
		_scatter_clump(context, point, choice.family)
	return {"point": point, "spacing": spacing}


## Thomas cluster process: satellites around an undergrowth parent, so grass
## reads as tufts in a clump rather than evenly spread pixels.
func _scatter_clump(context: Dictionary, parent: Vector2, family: String) -> void:
	var settings: VegetationProfileSettings = context.settings
	var rng: RandomNumberGenerator = context.rng
	var placed: Array[Dictionary] = context.placed
	for _child in settings.cluster_children:
		if placed.size() >= settings.max_instances:
			return
		var choice := _pick_asset(context, family)
		if choice.is_empty():
			return
		var offset := Vector2(rng.randfn(0.0, settings.cluster_sigma_m), rng.randfn(0.0, settings.cluster_sigma_m))
		_try_place(context, parent + offset, choice, false)


## Weighted mean spacing across the family mix, used only to predict whether the
## instance cap would bind before any sample is drawn.
func _mean_spacing(families: Dictionary, settings: VegetationProfileSettings, spacing_scale: float) -> float:
	var total := 0.0
	var weighted := 0.0
	for family in families:
		var weight := maxf(float(settings.family_weights.get(family, 0.0)), 0.0)
		if weight <= 0.0:
			continue
		var bucket: Dictionary = families[family]
		var models: Array = bucket.models
		var cumulative: Array = bucket.cumulative
		var sum := 0.0
		var previous := 0.0
		for index in models.size():
			var share: float = float(cumulative[index]) - previous
			previous = float(cumulative[index])
			var model: AssetDefinition = models[index]
			var spacing := maxf(settings.min_spacing_m, model.footprint_radius * spacing_scale)
			if model.blocks_navigation:
				spacing = maxf(spacing, model.blocking_radius() + WALK_GAP_M)
			sum += share * spacing
		weighted += weight * sum / maxf(float(cumulative[cumulative.size() - 1]), 0.001)
		total += weight
	return weighted / maxf(total, 0.001)


func _polygon_area(polygon: PackedVector2Array) -> float:
	var total := 0.0
	for index in polygon.size():
		var here := polygon[index]
		var next := polygon[(index + 1) % polygon.size()]
		total += here.x * next.y - next.x * here.y
	return absf(total) * 0.5


## Rolls a family by profile weight, then a model within it by the reverse-J
## size law. Pass a family name to stay inside one family (clump satellites).
func _pick_asset(context: Dictionary, family: String) -> Dictionary:
	var families: Dictionary = context.families
	var rng: RandomNumberGenerator = context.rng
	var chosen := family
	if chosen.is_empty():
		var weights: Dictionary = context.settings.family_weights
		var total := 0.0
		for name in FAMILIES:
			if families.has(name):
				total += maxf(float(weights.get(name, 0.0)), 0.0)
		if total <= 0.0:
			return {}
		var roll := rng.randf() * total
		for name in FAMILIES:
			if not families.has(name):
				continue
			roll -= maxf(float(weights.get(name, 0.0)), 0.0)
			if roll <= 0.0:
				chosen = name
				break
	if not families.has(chosen):
		return {}
	var bucket: Dictionary = families[chosen]
	var models: Array = bucket.models
	var cumulative: Array = bucket.cumulative
	var pick := rng.randf() * float(cumulative[cumulative.size() - 1])
	var selected: AssetDefinition = models[models.size() - 1]
	for index in models.size():
		if pick <= float(cumulative[index]):
			selected = models[index]
			break
	var spacing := maxf(context.settings.min_spacing_m, selected.footprint_radius * float(context.spacing_scale))
	# Foliage may pack as tight as the profile likes because nothing walks into
	# it. Anything that blocks has to leave room to walk past, and because the
	# floor scales with trunk width it also reproduces the way a large canopy
	# suppresses its neighbours.
	if selected.blocks_navigation:
		spacing = maxf(spacing, selected.blocking_radius() + WALK_GAP_M)
	return {"definition": selected, "family": chosen, "spacing": spacing * float(context.spacing_boost)}


## Median-anchored contrast curve: the denser half of the field carries a full
## stand, and everything below it opens out into a clearing.
func _field_strength(noise: FastNoiseLite, point: Vector2, contrast: float) -> float:
	var value := (noise.get_noise_2d(point.x, point.y) + 1.0) * 0.5
	return clampf(pow(clampf(value, 0.0, 1.0) * 2.0, contrast), 0.0, 1.0)


func _density_field(seed_value: int, settings: VegetationProfileSettings) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 3
	noise.frequency = settings.density_noise_frequency
	return noise


## exp(-lambda * r / r_max) per model, stored as a cumulative table so a single
## randf picks one. Negative lambda inverts it into an old-growth stand.
func _group_by_family(candidates: Array[AssetDefinition], size_lambda: float) -> Dictionary:
	var grouped := {}
	for candidate in candidates:
		for family in FAMILIES:
			if candidate.tags.has(family):
				if not grouped.has(family):
					grouped[family] = []
				grouped[family].append(candidate)
				break
	var result := {}
	for family in grouped:
		var models: Array = grouped[family]
		var largest := 0.0
		for model in models:
			largest = maxf(largest, model.footprint_radius)
		var cumulative: Array[float] = []
		var running := 0.0
		for model in models:
			running += exp(-size_lambda * model.footprint_radius / maxf(largest, 0.01))
			cumulative.append(running)
		if running <= 0.0:
			continue
		result[family] = {"models": models, "cumulative": cumulative}
	return result


static func load_profile(profile: String) -> VegetationProfileSettings:
	if _profile_cache.has(profile):
		return _profile_cache[profile]
	var settings := load(PROFILE_PATH % profile) as VegetationProfileSettings
	if settings == null:
		settings = load(PROFILE_PATH % FALLBACK_PROFILE) as VegetationProfileSettings
	_profile_cache[profile] = settings
	return settings


static func derive_seed(map_seed: int, region_id: String, generator_version: String = GENERATOR_VERSION) -> int:
	var value := 216613626
	# Iterating Unicode code points avoids engine-dependent String.hash().
	var input := str(map_seed) + "|" + region_id + "|" + generator_version
	for index in input.length():
		value = int(posmod(value * 16777619 + input.unicode_at(index), 2147483647))
	return value


func _item_point(item: Dictionary) -> Vector2:
	if item.has("point"):
		return item.point
	var position: Vector3 = item.get("position", Vector3.ZERO)
	return Vector2(position.x, position.z)


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
