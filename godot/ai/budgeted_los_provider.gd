class_name BudgetedLosProvider
extends LosProvider

## Pure decorator used only while evaluating AI candidates. A denied query is
## treated as no line of sight; EnemyAI discards incomplete candidates rather
## than allowing a budget exhaustion to make a risky command look legal.

var source: LosProvider
var budget: AIQueryBudget


func _init(source_provider: LosProvider, query_budget: AIQueryBudget) -> void:
	source = source_provider
	budget = query_budget


func has_line_of_sight(from: Vector3, to: Vector3) -> bool:
	return cover_between(from, to) != COVER_TOTAL


func cover_between(from: Vector3, to: Vector3) -> StringName:
	if not budget.consume_line_of_sight_query():
		return COVER_TOTAL
	return source.cover_between(from, to)
