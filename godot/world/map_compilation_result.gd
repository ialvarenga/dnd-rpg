class_name MapCompilationResult
extends RefCounted

var root: Node3D
var terrain: TerrainProvider
var placements: Array[Dictionary] = []
var paths: Array[Dictionary] = []
var bridges: Array[Dictionary] = []
var errors: Array[MapValidationError] = []
var warnings: Array[MapValidationWarning] = []
var scorecard: Dictionary = {}
var navigation: MapNavigationCompiler
var music: Dictionary = {}


func is_valid() -> bool:
	return errors.is_empty()


func error_dicts() -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for error in errors:
		output.append(error.as_dict())
	return output


func warning_dicts() -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for warning in warnings:
		output.append(warning.as_dict())
	return output
