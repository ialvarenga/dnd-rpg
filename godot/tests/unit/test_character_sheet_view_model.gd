class_name TestCharacterSheetViewModel
extends RefCounted

static func run() -> Dictionary:
	var failures: Array[String] = []
	var definitions := DefinitionLibrary.get_default()
	var state := TestHelpers.make_battle()
	var knight := ActorState.from_definition(definitions.get_actor(&"knight"), 1, &"heroes", Vector3.ZERO)
	state.actors[1] = knight
	var before := state.stable_snapshot()
	var view := CharacterSheetViewModel.for_actor(state, 1, definitions)
	_expect(not view.is_empty() and before == state.stable_snapshot(), "sheet projection must be pure", failures)
	var strength: Dictionary = view["stats"]["abilities"][0]
	_expect(strength["score"] == 14 and strength["modifier_text"] == "+2" and strength["save_text"] == "+4" and strength["save_proficient"], "knight strength/save was projected incorrectly", failures)
	_expect(view["equipment"]["combat"]["attack"] == "+4" and view["equipment"]["combat"]["damage"] == "1d8 + 2 slashing", "combat summary did not use resolver equipment math", failures)
	_expect(view["inventory"]["stacks"].size() == 1 and view["inventory"]["display_slots"] == 20, "inventory did not produce presentational stacks", failures)
	knight.inventory = [&"healing_potion", &"dagger", &"healing_potion", &"unknown_thing"]
	var stacks := CharacterSheetViewModel.inventory_stacks(state, 1, definitions)
	_expect(stacks.size() == 3 and stacks[0]["count"] == 2 and stacks[1]["kind"] == "Weapon" and stacks[2]["name"] == "Unknown Thing", "inventory stacking or unknown fallback is incorrect", failures)
	_expect(CharacterSheetViewModel.for_actor(state, 404, definitions).is_empty(), "unknown actor should produce an empty sheet", failures)
	return {"name": "unit/test_character_sheet_view_model", "failures": failures}


static func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
