class_name TestPathPreviewRenderer
extends RefCounted

const PathPreviewRendererScript = preload("res://view/path_preview_renderer.gd")


static func run() -> Dictionary:
	var failures: Array[String] = []
	var original := PackedVector3Array([
		Vector3.ZERO,
		Vector3(5.0, 0.0, 0.0),
		Vector3(5.0, 0.0, 5.0),
	])
	var rebased := PathPreviewRendererScript.rebase_path(original, Vector3(2.0, 0.0, 0.0))
	_expect(rebased[0] == Vector3(2.0, 0.0, 0.0), "rebased preview did not start at the live character position", failures)
	_expect(rebased[rebased.size() - 1] == original[original.size() - 1], "rebased preview changed its destination", failures)

	var advanced := PathPreviewRendererScript.rebase_path(original, Vector3(5.0, 0.0, 2.0))
	_expect(not advanced.has(Vector3(5.0, 0.0, 0.0)), "rebased preview retained an already-travelled waypoint", failures)
	var smoothed := PathPreviewRendererScript.smooth_path(rebased)
	_expect(smoothed.size() > rebased.size(), "rounded preview did not add curve samples", failures)
	_expect(smoothed[0] == rebased[0] and smoothed[smoothed.size() - 1] == rebased[rebased.size() - 1], "rounded preview changed an endpoint", failures)
	_expect(original == PackedVector3Array([Vector3.ZERO, Vector3(5.0, 0.0, 0.0), Vector3(5.0, 0.0, 5.0)]), "preview rendering mutated the navigation path", failures)
	return {"name": "unit/test_path_preview_renderer", "failures": failures}


static func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
