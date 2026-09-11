class_name JumpLinkCompiler
extends RefCounted

## ADR-009: turns every edge of a `jumpable` hill into one-way navigation links
## (drop down, climb up) between the walkable surfaces on either side of it.
##
## A link's navigation layer encodes the lowest Strength that can take it, so a
## creature routes only across ledges its own JumpRules numbers allow: layer 1
## is walking, bit N (N = 1..30) means "needs Strength N", and the top bit holds
## drops that hurt. Hurtful drops stay available to everyone, but with a large
## enter cost, so a route uses one only when no safe way down exists.

const TerrainScript = preload("res://world/procedural_terrain_provider.gd")
const JumpRulesScript = preload("res://sim/rules/jump_rules.gd")

const WALK_LAYERS := 1
const HARMFUL_DROP_LAYER := 1 << 31
## Metres of "detour" a hurtful drop is worth before routing prefers walking.
const HARMFUL_ENTER_COST := 25.0
## Spacing of link samples along a ledge, and the corner clearance they keep.
const SAMPLE_SPACING_M := 1.5
const CORNER_INSET_M := 0.75
## The takeoff/landing search walks away from the edge until it finds walkable
## navigation surface; the navmesh drops the 2 m cell straddling every ledge.
const SEARCH_STEP_M := 0.25
const MAX_SEARCH_M := 3.0
const TOP_TOLERANCE_M := 0.05
const LOCAL_NORMALS: Array[Vector2] = [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]


## Navigation layers of a creature with this Strength: walking, every ledge its
## Strength allows, and the hurtful-drop layer.
static func layers_for_strength(strength: int) -> int:
	var layers := WALK_LAYERS | HARMFUL_DROP_LAYER
	for required in range(1, clampi(strength, 0, JumpRulesScript.MAX_STRENGTH) + 1):
		layers |= layer_for_required_strength(required)
	return layers


static func layer_for_required_strength(strength: int) -> int:
	return 1 << strength


## `hills`: {id, center: Vector2, rotation_y, size: Vector3 (width, height,
## depth), top: float, navigable: bool}. `surface_at(point: Vector2) -> float`
## returns the walkable navigation height there, or NAN.
##
## Returns link dictionaries: {kind, from, to, layers, enter_cost, hill_id} plus
## `via` on a running climb, whose link starts one run-up before the ledge.
func compile(hills: Array[Dictionary], surface_at: Callable) -> Array[Dictionary]:
	var links: Array[Dictionary] = []
	for hill in hills:
		var center: Vector2 = hill["center"]
		var rotation_y := float(hill["rotation_y"])
		var size: Vector3 = hill["size"]
		var top := float(hill["top"])
		var half := Vector2(size.x, size.z) * 0.5
		for local_normal in LOCAL_NORMALS:
			# A navigable hill's rotated +Z side is its earthen ramp, walked not jumped.
			if bool(hill.get("navigable", false)) and local_normal == Vector2(0, 1):
				continue
			var edge_offset := half.x if local_normal.x != 0.0 else half.y
			var extent := half.y if local_normal.x != 0.0 else half.x
			var tangent := Vector2(local_normal.y, -local_normal.x)
			var normal := TerrainScript.hill_local_to_world(Vector2.ZERO, rotation_y, local_normal)
			var usable := maxf(0.0, extent * 2.0 - CORNER_INSET_M * 2.0)
			var count := floori(usable / SAMPLE_SPACING_M) + 1
			var spacing := 0.0 if count <= 1 else usable / float(count - 1)
			for sample in range(count):
				var along := -extent + CORNER_INSET_M + spacing * float(sample) if count > 1 else 0.0
				var edge := TerrainScript.hill_local_to_world(center, rotation_y, local_normal * edge_offset + tangent * along)
				_append_ledge_links(links, StringName(hill.get("id", "")), edge, normal, top, surface_at)
	return links


func _append_ledge_links(links: Array[Dictionary], hill_id: StringName, edge: Vector2, normal: Vector2, top: float, surface_at: Callable) -> void:
	# A takeoff below this hill's top means a taller overlapping terrace covers
	# this stretch of edge; that terrace emits its own links.
	var takeoff := _search(edge, -normal, surface_at, top, func(height: float) -> bool: return absf(height - top) <= TOP_TOLERANCE_M)
	var landing := _search(edge, normal, surface_at, top, func(height: float) -> bool: return height <= top - JumpRulesScript.STEP_HEIGHT_M)
	if not _found(takeoff) or not _found(landing):
		return
	var drop := takeoff.y - landing.y
	if drop < JumpRulesScript.STEP_HEIGHT_M:
		return
	var safe_strength := JumpRulesScript.min_strength_for_safe_drop(drop)
	if safe_strength > 0:
		links.append(_link(JumpRulesScript.DROP, takeoff, landing, layer_for_required_strength(safe_strength), 0.0, hill_id))
	if safe_strength != 1:
		links.append(_link(JumpRulesScript.DROP, takeoff, landing, HARMFUL_DROP_LAYER, HARMFUL_ENTER_COST, hill_id))
	var standing_strength := JumpRulesScript.min_strength_for_climb(drop, false)
	if standing_strength > 0:
		links.append(_link(JumpRulesScript.CLIMB, landing, takeoff, layer_for_required_strength(standing_strength), 0.0, hill_id))
	var running_strength := JumpRulesScript.min_strength_for_climb(drop, true)
	if running_strength <= 0 or (standing_strength > 0 and running_strength >= standing_strength):
		return
	# SRD: full High Jump needs 10 ft (3 m) of straight movement first. The link
	# starts at the far end of that run-up, which must be level walkable ground.
	var run_up_start := Vector2(landing.x, landing.z) + normal * JumpRulesScript.RUN_UP_M
	var step := 0.5
	var distance := step
	while distance <= JumpRulesScript.RUN_UP_M + 0.001:
		var point := Vector2(landing.x, landing.z) + normal * distance
		var height := float(surface_at.call(point))
		if is_nan(height) or absf(height - landing.y) > JumpRulesScript.STEP_HEIGHT_M:
			return
		distance += step
	var run_up := Vector3(run_up_start.x, float(surface_at.call(run_up_start)), run_up_start.y)
	var running_link := _link(JumpRulesScript.CLIMB, run_up, takeoff, layer_for_required_strength(running_strength), 0.0, hill_id)
	running_link["via"] = landing
	links.append(running_link)


## First walkable surface point from `origin` along `direction` that `accepts`
## its height. Surface above `top` is a taller terrace: nothing can be jumped
## through it, so the search stops there.
func _search(origin: Vector2, direction: Vector2, surface_at: Callable, top: float, accepts: Callable) -> Vector3:
	var distance := SEARCH_STEP_M
	while distance <= MAX_SEARCH_M + 0.001:
		var point := origin + direction * distance
		var height := float(surface_at.call(point))
		if not is_nan(height):
			if height > top + TOP_TOLERANCE_M:
				break
			if bool(accepts.call(height)):
				return Vector3(point.x, height, point.y)
		distance += SEARCH_STEP_M
	return Vector3(INF, INF, INF)


func _found(point: Vector3) -> bool:
	return is_finite(point.x)


func _link(kind: StringName, from: Vector3, to: Vector3, layers: int, enter_cost: float, hill_id: StringName) -> Dictionary:
	return {"kind": kind, "from": from, "to": to, "layers": layers, "enter_cost": enter_cost, "hill_id": hill_id}
