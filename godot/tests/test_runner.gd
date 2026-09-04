extends SceneTree

func _init() -> void:
	var failure_count := 0
	var suites := [TestSimulation, TestReplay, TestHeadlessContract]
	for suite in suites:
		var report: Dictionary = suite.run()
		var failures: Array = report["failures"]
		if failures.is_empty():
			print("PASS %s" % report["name"])
		else:
			for failure in failures:
				push_error("FAIL %s: %s" % [report["name"], failure])
			failure_count += failures.size()
	if failure_count == 0:
		print("All headless tests passed.")
		quit(0)
	else:
		print("%d headless test failure(s)." % failure_count)
		quit(1)
