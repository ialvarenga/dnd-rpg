class_name MapQualityAnalyzer
extends RefCounted

## Advisory-only tactical quality checks. This reads public TerrainProvider
## queries and compiler data, never the scene tree, so it remains headless and
## deterministic.

const SAMPLE_STEP_M := 2.0
const DEFAULT_BUDGET_PATH := "res://data/quality/default_budget.tres"


func analyze(terrain: TerrainProvider, placements: Array[Dictionary], navigation: MapNavigationCompiler, spec: Dictionary) -> Dictionary:
	var budget := load(DEFAULT_BUDGET_PATH) as MapQualityBudget
	var warnings: Array[MapValidationWarning] = []
	var heights: Array[float] = []
	var steep_count := 0
	var slope_limit := float(terrain.call("navigation_slope_limit")) if terrain.has_method("navigation_slope_limit") else 35.0
	for x in range(0, ceili(terrain.bounds.x), ceili(SAMPLE_STEP_M)):
		for z in range(0, ceili(terrain.bounds.y), ceili(SAMPLE_STEP_M)):
			var point := Vector2(minf(float(x) + SAMPLE_STEP_M * 0.5, terrain.bounds.x), minf(float(z) + SAMPLE_STEP_M * 0.5, terrain.bounds.y))
			heights.append(terrain.height_at(point.x, point.y))
			if terrain.slope_at(point.x, point.y) > slope_limit:
				steep_count += 1
	var mean := 0.0
	for height in heights:
		mean += height
	mean /= maxf(float(heights.size()), 1.0)
	var variance := 0.0
	for height in heights:
		variance += pow(height - mean, 2.0)
	var relief_stdev := sqrt(variance / maxf(float(heights.size()), 1.0))
	var cover_area := 0.0
	for placement in placements:
		var definition := AssetCatalog.get_definition(placement.asset)
		if definition != null and definition.blocks_navigation:
			cover_area += PI * placement.radius * placement.radius
	var map_area := terrain.bounds.x * terrain.bounds.y
	var cover_fraction := clampf(cover_area / maxf(map_area, 0.001), 0.0, 1.0)
	var scorecard := {
		"cover_fraction": cover_fraction,
		"relief_stdev_m": relief_stdev,
		"steep_fraction": float(steep_count) / maxf(float(heights.size()), 1.0),
		"navigation_slope_limit_deg": slope_limit,
	}
	if cover_fraction < budget.minimum_cover_fraction:
		warnings.append(MapValidationWarning.new(&"LOW_COVER", "map has little blocking cover", &"map", {"cover_fraction": cover_fraction}))
	if terrain.profile != &"flat" and relief_stdev < budget.minimum_relief_stdev_m:
		warnings.append(MapValidationWarning.new(&"LOW_RELIEF", "terrain relief is too flat for its selected profile", &"terrain", {"relief_stdev_m": relief_stdev}))
	for objective in spec.get("objectives", []):
		var target := _point(objective.get("position", []))
		var closest := INF
		for spawn in spec.get("spawn_points", []):
			closest = minf(closest, _point(spawn.get("position", [])).distance_to(target))
		if closest < budget.minimum_objective_distance_m:
			warnings.append(MapValidationWarning.new(&"OBJECTIVE_TOO_CLOSE", "objective is very close to a spawn", StringName(objective.get("id", "")), {"distance_m": closest}))
	for spawn in spec.get("spawn_points", []):
		var point := _point(spawn.get("position", []))
		for placement in placements:
			if point.distance_to(Vector2(placement.position.x, placement.position.z)) < placement.radius + budget.actor_radius_m:
				warnings.append(MapValidationWarning.new(&"LOW_SPAWN_CLEARANCE", "spawn clearance does not include the player radius", StringName(spawn.get("id", "")), {"placement_id": placement.id}))
	return {"warnings": warnings, "scorecard": scorecard}


func _point(raw: Array) -> Vector2:
	return Vector2(float(raw[0]), float(raw[1])) if raw.size() == 2 else Vector2(INF, INF)
