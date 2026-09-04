class_name AIQueryBudget
extends RefCounted

## Bounds speculative navigation and line-of-sight work performed by utility AI.
## A caller owns one budget for an enemy turn and passes it to each incremental
## decision, so a long turn cannot turn into unbounded engine adapter queries.

var max_navigation_queries: int
var max_line_of_sight_queries: int
var navigation_queries: int = 0
var line_of_sight_queries: int = 0
var navigation_denials: int = 0
var line_of_sight_denials: int = 0


func _init(navigation_limit: int = 6, line_of_sight_limit: int = 8) -> void:
	max_navigation_queries = maxi(0, navigation_limit)
	max_line_of_sight_queries = maxi(0, line_of_sight_limit)


func consume_navigation_query() -> bool:
	if navigation_queries >= max_navigation_queries:
		navigation_denials += 1
		return false
	navigation_queries += 1
	return true


func consume_line_of_sight_query() -> bool:
	if line_of_sight_queries >= max_line_of_sight_queries:
		line_of_sight_denials += 1
		return false
	line_of_sight_queries += 1
	return true


func remaining_navigation_queries() -> int:
	return maxi(0, max_navigation_queries - navigation_queries)


func remaining_line_of_sight_queries() -> int:
	return maxi(0, max_line_of_sight_queries - line_of_sight_queries)
