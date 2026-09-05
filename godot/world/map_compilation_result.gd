class_name MapCompilationResult
extends RefCounted

var root: Node3D
var terrain: TerrainProvider
var placements: Array[Dictionary] = []
var paths: Array[Dictionary] = []
var bridges: Array[Dictionary] = []
var errors: Array[MapValidationError] = []
var navigation: MapNavigationCompiler


func is_valid() -> bool:
	return errors.is_empty()


func error_dicts() -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for error in errors:
		output.append(error.as_dict())
	return output
