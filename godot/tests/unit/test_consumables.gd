class_name TestConsumables
extends RefCounted

static func run() -> Dictionary:
	var failures: Array[String] = []
	_test_dice_sequence(failures)
	_test_potion_heals_consumes_and_advances_rng(failures)
	_test_potion_clamps_and_removes_one_matching_item(failures)
	_test_missing_item_agrees_with_availability(failures)
	_test_effective_abilities_and_snapshot(failures)
	_test_content_manifest_and_ai(failures)
	return {"name": "unit/test_consumables", "failures": failures}


static func _test_dice_sequence(failures: Array[String]) -> void:
	var multi := Dice.roll_dice(81, 3, 4)
	var state := 81
	var values: Array[int] = []
	for _index in range(3):
		var single := Dice.roll_die(state, 4)
		values.append(int(single["value"]))
		state = int(single["next_rng_state"])
	_expect(multi["values"] == values and multi["next_rng_state"] == state, "roll_dice did not exactly match repeated roll_die calls", failures)


static func _test_potion_heals_consumes_and_advances_rng(failures: Array[String]) -> void:
	var state := _potion_state(10)
	var expected := Dice.roll_dice(state.rng_state, 2, 4)
	var result := Resolver.resolve(state, Command.create(&"quaff_healing_potion", 1), FakeNavProvider.new(), FakeLosProvider.new())
	_expect(_event_types(result) == [&"action_spent", &"healing_received", &"item_consumed"], "potion did not emit action, healing, then consumption events", failures)
	_expect(result.next_rng_state == expected["next_rng_state"], "potion multi-die healing did not advance RNG deterministically", failures)
	TestHelpers.apply_result(state, result)
	_expect(state.actors[1].hp == mini(20, 10 + int(expected["total"]) + 2), "potion did not apply its data-authored 2d4+2 healing", failures)
	_expect((state.actors[1] as ActorState).inventory.is_empty(), "potion did not consume its carried inventory entry", failures)


static func _test_potion_clamps_and_removes_one_matching_item(failures: Array[String]) -> void:
	var state := _potion_state(19)
	var actor: ActorState = state.actors[1]
	actor.inventory = [&"healing_potion", &"healing_potion"]
	var result := Resolver.resolve(state, Command.create(&"quaff_healing_potion", 1), FakeNavProvider.new(), FakeLosProvider.new())
	TestHelpers.apply_result(state, result)
	_expect(actor.hp == actor.max_hp, "healing_received did not clamp HP to max_hp", failures)
	_expect(actor.inventory == [&"healing_potion"], "item_consumed did not remove exactly one matching inventory entry", failures)


static func _test_missing_item_agrees_with_availability(failures: Array[String]) -> void:
	var state := _potion_state(5)
	(state.actors[1] as ActorState).inventory.clear()
	var availability := ActionAvailability.evaluate(state, 1, &"quaff_healing_potion")
	var result := Resolver.resolve(state, Command.create(&"quaff_healing_potion", 1), FakeNavProvider.new(), FakeLosProvider.new())
	_expect(not availability["available"] and availability["reason"] == RejectionReason.ITEM_NOT_IN_INVENTORY, "availability did not expose missing consumable inventory", failures)
	_expect(result.events[0].data["reason"] == availability["reason"], "Resolver and ActionAvailability diverged on missing consumable inventory", failures)


static func _test_effective_abilities_and_snapshot(failures: Array[String]) -> void:
	var state := _potion_state(5)
	var actor: ActorState = state.actors[1]
	actor.ability_ids = [&"dash"]
	var ids := ActionAvailability.effective_ability_ids(actor, DefinitionLibrary.get_default())
	_expect(ids == [&"dash", &"quaff_healing_potion"], "effective ability ids did not append the carried item's use ability", failures)
	_expect(state.stable_snapshot()["actors"][0]["inventory"] == [&"healing_potion"], "stable snapshot omitted mutable inventory", failures)


static func _test_content_manifest_and_ai(failures: Array[String]) -> void:
	var defs := DefinitionLibrary.get_default()
	_expect(defs.ordered_ability_ids().has(&"quaff_healing_potion") and defs.ordered_item_ids().has(&"healing_potion"), "fixed content manifests omitted healing-potion resources", failures)
	var state := _potion_state(1)
	var enemy: ActorState = state.actors[2]
	enemy.inventory = [&"healing_potion"]
	enemy.hp = 1
	state.initiative_order = [2, 1]
	state.current_turn_index = 0
	var command := EnemyAI.new().choose_command(state, 2, FakeNavProvider.new(), FakeLosProvider.new(), AIQueryBudget.new())
	_expect(command != null and command.type == &"quaff_healing_potion", "AI did not prioritize a healing consumable at critical HP", failures)


static func _potion_state(hp: int) -> BattleState:
	var state := TestHelpers.make_battle(41)
	var actor: ActorState = state.actors[1]
	actor.hp = hp
	actor.max_hp = 20
	actor.inventory = [&"healing_potion"]
	return state


static func _event_types(result: ResolutionResult) -> Array[StringName]:
	var types: Array[StringName] = []
	for event in result.events:
		types.append(event.type)
	return types


static func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
