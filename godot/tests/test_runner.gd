extends SceneTree

const TestTerrainProviderScript = preload("res://tests/unit/test_terrain_provider.gd")
const TestMapCompilerScript = preload("res://tests/unit/test_map_compiler.gd")
const TestCharacterAnimatorScript = preload("res://tests/unit/test_character_animator.gd")
const TestArenaRuntimeScript = preload("res://tests/integration/test_arena_runtime.gd")
const TestEventPlayerFeedbackScript = preload("res://tests/integration/test_event_player_feedback.gd")
const TestCompiledMapHealthBarsScript = preload("res://tests/integration/test_compiled_map_health_bars.gd")
const TestHudBindingScript = preload("res://tests/integration/test_hud_binding.gd")
const TestConsumablesScript = preload("res://tests/unit/test_consumables.gd")

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failure_count := 0
	var suites := [TestSimulation, TestDefinitions, TestActionAvailability, TestHudViewModel, TestEquipment, TestInteractables, TestAssetCatalog, TestTerrainProviderScript, TestMapCompilerScript, TestCharacterAnimatorScript, TestEnemyAI, TestConsumablesScript, TestReplay, TestSaveGame, TestReplayLog, TestHeadlessContract, TestSaveLoadService, TestPrototypeLocomotion, TestEncounterSession]
	for suite in suites:
		var report: Dictionary = suite.run()
		var failures: Array = report["failures"]
		if failures.is_empty():
			print("PASS %s" % report["name"])
		else:
			for failure in failures:
				push_error("FAIL %s: %s" % [report["name"], failure])
			failure_count += failures.size()
	for async_suite_script in [TestArenaRuntimeScript, TestEventPlayerFeedbackScript, TestCompiledMapHealthBarsScript, TestHudBindingScript]:
		var async_suite := async_suite_script.new() as Node
		root.add_child(async_suite)
		var async_report: Dictionary = await async_suite.run()
		async_suite.queue_free()
		var async_failures: Array = async_report["failures"]
		if async_failures.is_empty():
			print("PASS %s" % async_report["name"])
		else:
			for failure in async_failures:
				push_error("FAIL %s: %s" % [async_report["name"], failure])
			failure_count += async_failures.size()
	if failure_count == 0:
		print("All headless tests passed.")
		quit(0)
	else:
		print("%d headless test failure(s)." % failure_count)
		quit(1)
