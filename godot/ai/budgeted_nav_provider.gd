class_name BudgetedNavProvider
extends NavProvider

## Pure decorator used only while evaluating AI candidates. It deliberately
## depends on the NavProvider port, never on a Godot navigation adapter.

var source: NavProvider
var budget: AIQueryBudget


func _init(source_provider: NavProvider, query_budget: AIQueryBudget) -> void:
	source = source_provider
	budget = query_budget


func find_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	if not budget.consume_navigation_query():
		return PackedVector3Array()
	return source.find_path(from, to)


func path_cost(path: PackedVector3Array) -> float:
	return source.path_cost(path)


func clamp_path(path: PackedVector3Array, budget: float) -> PackedVector3Array:
	return source.clamp_path(path, budget)


func project_push(from: Vector3, direction: Vector3, distance: float) -> Dictionary:
	if not budget.consume_navigation_query():
		return {"landing_position": from, "blocked": true, "fell": false, "fall_distance": 0.0}
	return source.project_push(from, direction, distance)


func is_reachable(from: Vector3, to: Vector3) -> bool:
	if not budget.consume_navigation_query():
		return false
	return source.is_reachable(from, to)


func snap_to_navmesh(pos: Vector3) -> Vector3:
	return source.snap_to_navmesh(pos)


func surface_point(pos: Vector3) -> Vector3:
	return source.surface_point(pos)


func jump_between(from: Vector3, to: Vector3) -> Dictionary:
	return source.jump_between(from, to)


## Keeps the shared query budget: the Strength-scoped view counts against the
## same allowance as this decorator.
func for_jumper(strength: int) -> NavProvider:
	var scoped: NavProvider = source.for_jumper(strength)
	return self if scoped == source else BudgetedNavProvider.new(scoped, budget)
