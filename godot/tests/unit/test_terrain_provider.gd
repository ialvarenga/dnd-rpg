class_name TestTerrainProvider
extends RefCounted

## B4 contract tests: FlatTerrainProvider is deterministic test support, not a
## procedural terrain generator or map compiler.

const TerrainProviderScript = preload("res://world/terrain_provider.gd")
const FlatTerrainProviderScript = preload("res://tests/fakes/flat_terrain_provider.gd")


static func run() -> Dictionary:
	var failures: Array[String] = []
	_test_provider_can_be_extended_and_initialized(failures)
	_test_flat_provider_queries_are_deterministic(failures)
	_test_navigation_export_is_explicitly_deferred(failures)
	_test_invalid_input_and_queries_fail_clearly(failures)
	return {"name": "unit/test_terrain_provider", "failures": failures}


static func _test_provider_can_be_extended_and_initialized(failures: Array[String]) -> void:
	var provider := FlatTerrainProviderScript.new()
	_expect(provider.get_script().get_base_script() == TerrainProviderScript, "flat support provider does not extend TerrainProvider", failures)
	_expect(provider.generate(&"rolling_hills", 918273, Vector2(64.0, 48.0)), "valid MapSpec terrain input was rejected", failures)
	_expect(provider.profile == &"rolling_hills", "provider did not retain terrain profile", failures)
	_expect(provider.seed == 918273, "provider did not retain terrain seed", failures)
	_expect(provider.bounds == Vector2(64.0, 48.0), "provider did not retain width/height bounds", failures)


static func _test_flat_provider_queries_are_deterministic(failures: Array[String]) -> void:
	var provider := FlatTerrainProviderScript.new()
	provider.generate(&"flat", 7, Vector2(10.0, 20.0))
	_expect(is_zero_approx(provider.height_at(0.0, 0.0)), "flat provider height at southwest corner is not zero", failures)
	_expect(is_zero_approx(provider.height_at(10.0, 20.0)), "flat provider height at northeast corner is not zero", failures)
	_expect(provider.normal_at(3.5, 7.25) == Vector3.UP, "flat provider normal is not Vector3.UP", failures)
	_expect(is_zero_approx(provider.slope_at(3.5, 7.25)), "flat provider slope is not zero degrees", failures)


static func _test_navigation_export_is_explicitly_deferred(failures: Array[String]) -> void:
	var provider := FlatTerrainProviderScript.new()
	provider.generate(&"valley", 1, Vector2(8.0, 8.0))
	_expect(provider.export_navigation_geometry().is_empty(), "B4 support provider must defer navigation geometry", failures)


static func _test_invalid_input_and_queries_fail_clearly(failures: Array[String]) -> void:
	var provider := FlatTerrainProviderScript.new()
	_expect(not provider.generate(&"mountain", 1, Vector2(8.0, 8.0)), "unsupported profile was accepted", failures)
	_expect(not provider.generate(&"flat", -1, Vector2(8.0, 8.0)), "negative seed was accepted", failures)
	_expect(not provider.generate(&"flat", TerrainProviderScript.MAX_SEED + 1, Vector2(8.0, 8.0)), "seed above the MapSpec maximum was accepted", failures)
	_expect(not provider.generate(&"flat", 1, Vector2(0.0, 8.0)), "zero-width bounds were accepted", failures)
	_expect(not provider.generate(&"flat", 1, Vector2(TerrainProviderScript.MAX_BOUND_M + 0.1, 8.0)), "bounds above the MapSpec maximum were accepted", failures)
	_expect(is_nan(provider.height_at(0.0, 0.0)), "uninitialized height query did not return NAN", failures)
	_expect(provider.generate(&"flat", 1, Vector2(8.0, 8.0)), "valid terrain input was rejected after invalid attempts", failures)
	_expect(is_nan(provider.height_at(-0.1, 0.0)), "out-of-bounds height query did not return NAN", failures)
	_expect(is_nan(provider.slope_at(8.1, 0.0)), "out-of-bounds slope query did not return NAN", failures)
	var normal := provider.normal_at(0.0, 8.1)
	_expect(is_nan(normal.x) and is_nan(normal.y) and is_nan(normal.z), "out-of-bounds normal query did not return NAN vector", failures)


static func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
