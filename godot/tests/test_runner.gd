extends SceneTree

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failure_count := 0
	var suites := [TestSimulation, TestDefinitions, TestEnemyAI, TestReplay, TestSaveGame, TestReplayLog, TestHeadlessContract, TestSaveLoadService, TestPrototypeLocomotion]
	for suite in suites:
		var report: Dictionary = suite.run()
		var failures: Array = report["failures"]
		if failures.is_empty():
			print("PASS %s" % report["name"])
		else:
			for failure in failures:
				push_error("FAIL %s: %s" % [report["name"], failure])
			failure_count += failures.size()
	var runtime_suite := TestArenaRuntime.new()
	root.add_child(runtime_suite)
	var runtime_report: Dictionary = await runtime_suite.run()
	runtime_suite.queue_free()
	var runtime_failures: Array = runtime_report["failures"]
	if runtime_failures.is_empty():
		print("PASS %s" % runtime_report["name"])
	else:
		for failure in runtime_failures:
			push_error("FAIL %s: %s" % [runtime_report["name"], failure])
		failure_count += runtime_failures.size()
	if failure_count == 0:
		print("All headless tests passed.")
		quit(0)
	else:
		print("%d headless test failure(s)." % failure_count)
		quit(1)
