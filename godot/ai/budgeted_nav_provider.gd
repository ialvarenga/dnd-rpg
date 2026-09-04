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


func is_reachable(from: Vector3, to: Vector3) -> bool:
	if not budget.consume_navigation_query():
		return false
	return source.is_reachable(from, to)


func snap_to_navmesh(pos: Vector3) -> Vector3:
	return source.snap_to_navmesh(pos)
