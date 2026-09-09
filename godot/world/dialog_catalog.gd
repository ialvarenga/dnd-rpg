class_name DialogCatalog
extends RefCounted

## Read-only index over a MapSpec's `dialogs` array, built once at map load the
## same way AssetCatalog indexes art. Nothing here resolves a conversation --
## DialogSession walks the graph and the Resolver owns every roll and state
## change; this only makes "which node is `greeting` in `emberwatch_toll`" an
## O(1) lookup instead of a scan, and normalises the authored dictionaries so
## the walker never has to defend against missing keys.

var _dialogs: Dictionary = {}


## Accepts the raw parsed MapSpec. Malformed entries are skipped rather than
## raising: MapCompiler._validate_dialog_references already rejects a spec whose
## dialog references do not resolve, so anything reaching here is authored.
func configure(spec: Dictionary) -> void:
	_dialogs.clear()
	for raw_dialog in spec.get("dialogs", []):
		var dialog_id := StringName(str(raw_dialog.get("id", "")))
		if dialog_id == &"":
			continue
		var nodes: Dictionary = {}
		for raw_node in raw_dialog.get("nodes", []):
			var node_id := StringName(str(raw_node.get("id", "")))
			if node_id == &"":
				continue
			nodes[node_id] = {
				"id": node_id,
				"speaker": str(raw_node.get("speaker", "")),
				"text": str(raw_node.get("text", "")),
				"options": _normalized_options(raw_node.get("options", [])),
			}
		_dialogs[dialog_id] = {
			"id": dialog_id,
			"root": StringName(str(raw_dialog.get("root", ""))),
			"nodes": nodes,
		}


func has_dialog(dialog_id: StringName) -> bool:
	return _dialogs.has(dialog_id)


func root_node_id(dialog_id: StringName) -> StringName:
	return _dialogs.get(dialog_id, {}).get("root", &"")


## The node dictionary, or an empty one when either id is unknown. Callers treat
## empty as "the conversation is over" rather than as an error.
func node(dialog_id: StringName, node_id: StringName) -> Dictionary:
	return _dialogs.get(dialog_id, {}).get("nodes", {}).get(node_id, {})


func _normalized_options(raw_options: Array) -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	for raw_option in raw_options:
		options.append({
			"text": str(raw_option.get("text", "")),
			"check": _normalized_check(raw_option.get("check", {})),
			"outcome": _normalized_outcome(raw_option.get("outcome", {})),
			"failure_outcome": _normalized_outcome(raw_option.get("failure_outcome", {})),
		})
	return options


## An empty dictionary means "no roll": the option is taken unconditionally.
func _normalized_check(raw_check: Dictionary) -> Dictionary:
	if raw_check.is_empty():
		return {}
	var ability := StringName(str(raw_check.get("ability", "")))
	var skill := StringName(str(raw_check.get("skill", "")))
	return {
		"ability": ability,
		"skill": skill,
		"dc": int(raw_check.get("dc", 10)),
		"proficient": bool(raw_check.get("proficient", false)),
	}


func _normalized_outcome(raw_outcome: Dictionary) -> Dictionary:
	return {
		"next": StringName(str(raw_outcome.get("next", ""))),
		"effect": StringName(str(raw_outcome.get("effect", "none"))),
	}
