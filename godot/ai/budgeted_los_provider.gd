class_name BudgetedLosProvider
extends LosProvider

## Pure decorator used only while evaluating AI candidates. A denied query is
## treated as no line of sight; EnemyAI discards incomplete candidates rather
## than allowing a budget exhaustion to make a risky command look legal.
##
## One instance lives for one AI decision over one fixed snapshot, so the same
## query always has the same answer: repeating it (Resolver checks sight and
## then cover for one attack; scoring reads that cover again) is answered from
## memory and spends the budget once. Denials are never remembered.

var source: LosProvider
var budget: AIQueryBudget
var _answered: Dictionary = {}


func _init(source_provider: LosProvider, query_budget: AIQueryBudget) -> void:
	source = source_provider
	budget = query_budget


func has_line_of_sight(from: Vector3, to: Vector3) -> bool:
	return cover_between(from, to) != COVER_TOTAL


func cover_between(from: Vector3, to: Vector3) -> StringName:
	var key := [from, to]
	if _answered.has(key):
		return _answered[key]
	if not budget.consume_line_of_sight_query():
		return COVER_TOTAL
	var cover := source.cover_between(from, to)
	_answered[key] = cover
	return cover
