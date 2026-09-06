class_name TestInteractables
extends RefCounted

## Fase A9: door/chest/lever interactables resolved through the same
## Command -> Resolver -> Event -> apply pipeline as every other command.

static func run() -> Dictionary:
	var failures: Array[String] = []
	_test_exploration_interact_is_free_and_ignores_turn_order(failures)
	_test_combat_interact_requires_current_actor(failures)
	_test_combat_interact_costs_action_and_blocks_second_use(failures)
	_test_door_toggles_open_and_closed(failures)
	_test_chest_is_one_way(failures)
	_test_chest_loot_is_authoritative_and_idempotent(failures)
	_test_lever_toggles_on_and_off(failures)
	_test_out_of_range_is_rejected_without_mutation(failures)
	_test_unknown_interactable_is_rejected(failures)
	_test_resolve_does_not_mutate_input(failures)
	_test_apply_changes_only_event_fields(failures)
	_test_serialization_round_trip(failures)
	_test_equal_inputs_produce_equal_resolution(failures)
	return {"name": "unit/test_interactables", "failures": failures}


static func _make_state(phase: StringName = &"exploration") -> BattleState:
	var state := TestHelpers.make_battle()
	state.phase = phase
	return state


static func _add_door(state: BattleState, id: String = "door_north", initial_state: StringName = &"closed") -> InteractableState:
	var door := InteractableState.new()
	door.id = id
	door.type = &"door"
	door.state = initial_state
	door.position = Vector3(1.5, 0.0, 0.0)
	door.interact_range = 2.0
	state.interactables[door.id] = door
	return door


static func _add_chest(state: BattleState, id: String = "chest_a") -> InteractableState:
	var chest := InteractableState.new()
	chest.id = id
	chest.type = &"chest"
	chest.state = &"closed"
	chest.position = Vector3(1.5, 0.0, 0.0)
	chest.interact_range = 2.0
	state.interactables[chest.id] = chest
	return chest


static func _add_lever(state: BattleState, id: String = "lever_a") -> InteractableState:
	var lever := InteractableState.new()
	lever.id = id
	lever.type = &"lever"
	lever.state = &"off"
	lever.position = Vector3(1.5, 0.0, 0.0)
	lever.interact_range = 2.0
	state.interactables[lever.id] = lever
	return lever


static func _interact_command(actor_id: int, interactable_id: String) -> Command:
	var command := Command.create(&"interact", actor_id)
	command.target_interactable_id = interactable_id
	return command


static func _test_exploration_interact_is_free_and_ignores_turn_order(failures: Array[String]) -> void:
	var state := _make_state(&"exploration")
	state.current_turn_index = 0 # actor 1's turn, but exploration should not care.
	_add_door(state)
	var command := _interact_command(2, "door_north")
	var result := Resolver.resolve(state, command, FakeNavProvider.new(), FakeLosProvider.new())
	_expect(result.events.size() == 1, "exploration interact should not spend an action", failures)
	if result.events.size() == 1:
		_expect(result.events[0].type == &"interaction_completed", "exploration interact did not resolve to interaction_completed", failures)
		_expect(result.events[0].data["previous_state"] == &"closed" and result.events[0].data["new_state"] == &"open", "door did not toggle closed -> open", failures)
	TestHelpers.apply_result(state, result)
	_expect((state.interactables["door_north"] as InteractableState).state == &"open", "apply() did not open the door", failures)
	_expect((state.actors[2] as ActorState).action_available, "exploration interact should not spend actor 2's action", failures)


static func _test_combat_interact_requires_current_actor(failures: Array[String]) -> void:
	var state := _make_state(&"combat")
	state.current_turn_index = 0 # actor 1's turn
	_add_door(state)
	var command := _interact_command(2, "door_north")
	var result := Resolver.resolve(state, command, FakeNavProvider.new(), FakeLosProvider.new())
	_expect(result.events.size() == 1 and result.events[0].type == &"command_rejected" and result.events[0].data["reason"] == &"not_current_actor", "off-turn combat interact was not rejected", failures)


static func _test_combat_interact_costs_action_and_blocks_second_use(failures: Array[String]) -> void:
	var state := _make_state(&"combat")
	state.current_turn_index = 0 # actor 1's turn
	_add_door(state)
	var first := Resolver.resolve(state, _interact_command(1, "door_north"), FakeNavProvider.new(), FakeLosProvider.new())
	_expect(first.events.size() == 2, "combat interact should spend an action alongside the interaction", failures)
	if first.events.size() == 2:
		_expect(first.events[0].type == &"action_spent", "combat interact did not spend an action first", failures)
		_expect(first.events[1].type == &"interaction_completed", "combat interact did not resolve to interaction_completed", failures)
	TestHelpers.apply_result(state, first)
	_expect(not (state.actors[1] as ActorState).action_available, "apply() did not spend the actor's action", failures)
	_expect((state.interactables["door_north"] as InteractableState).state == &"open", "apply() did not open the door", failures)

	var second := Resolver.resolve(state, _interact_command(1, "door_north"), FakeNavProvider.new(), FakeLosProvider.new())
	_expect(second.events.size() == 1 and second.events[0].type == &"command_rejected" and second.events[0].data["reason"] == &"action_unavailable", "a second interact with no action left was not rejected", failures)


static func _test_door_toggles_open_and_closed(failures: Array[String]) -> void:
	var state := _make_state(&"exploration")
	_add_door(state)
	TestHelpers.apply_result(state, Resolver.resolve(state, _interact_command(1, "door_north"), FakeNavProvider.new(), FakeLosProvider.new()))
	_expect((state.interactables["door_north"] as InteractableState).state == &"open", "door did not open", failures)
	TestHelpers.apply_result(state, Resolver.resolve(state, _interact_command(1, "door_north"), FakeNavProvider.new(), FakeLosProvider.new()))
	_expect((state.interactables["door_north"] as InteractableState).state == &"closed", "door did not close again", failures)


static func _test_chest_is_one_way(failures: Array[String]) -> void:
	var state := _make_state(&"exploration")
	_add_chest(state)
	TestHelpers.apply_result(state, Resolver.resolve(state, _interact_command(1, "chest_a"), FakeNavProvider.new(), FakeLosProvider.new()))
	_expect((state.interactables["chest_a"] as InteractableState).state == &"open", "chest did not open", failures)
	var second := Resolver.resolve(state, _interact_command(1, "chest_a"), FakeNavProvider.new(), FakeLosProvider.new())
	_expect(second.events.size() == 1 and second.events[0].type == &"command_rejected" and second.events[0].data["reason"] == &"invalid_interactable_state", "re-opening an already-open chest should be rejected", failures)


static func _test_chest_loot_is_authoritative_and_idempotent(failures: Array[String]) -> void:
	var state := _make_state(&"exploration")
	var chest := _add_chest(state)
	chest.contents.append(&"healing_potion")
	chest.contents.append(&"healing_potion")
	var before := JSON.stringify(state.stable_snapshot()).md5_text()
	var first := Resolver.resolve(state, _interact_command(1, "chest_a"), FakeNavProvider.new(), FakeLosProvider.new())
	_expect(JSON.stringify(state.stable_snapshot()).md5_text() == before, "loot resolution mutated BattleState before apply", failures)
	_expect(first.events.size() == 2 and first.events[0].type == &"interaction_completed" and first.events[1].type == &"items_looted", "opening a stocked chest did not emit ordered loot events", failures)
	if first.events.size() == 2:
		_expect(first.events[1].data["item_ids"] == [&"healing_potion", &"healing_potion"], "items_looted did not preserve ordered chest contents", failures)
	TestHelpers.apply_result(state, first)
	_expect((state.actors[1] as ActorState).inventory == [&"healing_potion", &"healing_potion"], "items_looted did not append every item to inventory", failures)
	_expect((state.interactables["chest_a"] as InteractableState).contents.is_empty(), "items_looted did not clear chest contents", failures)
	var second := Resolver.resolve(state, _interact_command(1, "chest_a"), FakeNavProvider.new(), FakeLosProvider.new())
	_expect(second.events.size() == 1 and second.events[0].type == &"command_rejected", "opened chest could loot its contents twice", failures)


static func _test_lever_toggles_on_and_off(failures: Array[String]) -> void:
	var state := _make_state(&"exploration")
	_add_lever(state)
	TestHelpers.apply_result(state, Resolver.resolve(state, _interact_command(1, "lever_a"), FakeNavProvider.new(), FakeLosProvider.new()))
	_expect((state.interactables["lever_a"] as InteractableState).state == &"on", "lever did not flip on", failures)
	TestHelpers.apply_result(state, Resolver.resolve(state, _interact_command(1, "lever_a"), FakeNavProvider.new(), FakeLosProvider.new()))
	_expect((state.interactables["lever_a"] as InteractableState).state == &"off", "lever did not flip off", failures)


static func _test_out_of_range_is_rejected_without_mutation(failures: Array[String]) -> void:
	var state := _make_state(&"exploration")
	var door := _add_door(state)
	door.position = Vector3(50.0, 0.0, 0.0)
	var before := JSON.stringify(state.stable_snapshot()).md5_text()
	var result := Resolver.resolve(state, _interact_command(1, "door_north"), FakeNavProvider.new(), FakeLosProvider.new())
	_expect(result.events.size() == 1 and result.events[0].type == &"command_rejected" and result.events[0].data["reason"] == &"out_of_range", "far-away interact was not rejected as out_of_range", failures)
	_expect(JSON.stringify(state.stable_snapshot()).md5_text() == before, "out_of_range rejection mutated state", failures)


static func _test_unknown_interactable_is_rejected(failures: Array[String]) -> void:
	var state := _make_state(&"exploration")
	var result := Resolver.resolve(state, _interact_command(1, "does_not_exist"), FakeNavProvider.new(), FakeLosProvider.new())
	_expect(result.events.size() == 1 and result.events[0].type == &"command_rejected" and result.events[0].data["reason"] == &"unknown_interactable", "unknown interactable id was not rejected", failures)


static func _test_resolve_does_not_mutate_input(failures: Array[String]) -> void:
	var state := _make_state(&"combat")
	state.current_turn_index = 0
	_add_door(state)
	var before := JSON.stringify(state.stable_snapshot()).md5_text()
	Resolver.resolve(state, _interact_command(1, "door_north"), FakeNavProvider.new(), FakeLosProvider.new())
	_expect(JSON.stringify(state.stable_snapshot()).md5_text() == before, "resolve() mutated BattleState for an interact command", failures)


static func _test_apply_changes_only_event_fields(failures: Array[String]) -> void:
	var state := _make_state(&"exploration")
	_add_door(state)
	var untouched_actor_hp: int = (state.actors[1] as ActorState).hp
	var result := Resolver.resolve(state, _interact_command(1, "door_north"), FakeNavProvider.new(), FakeLosProvider.new())
	TestHelpers.apply_result(state, result)
	_expect((state.actors[1] as ActorState).hp == untouched_actor_hp, "apply() of interaction_completed changed unrelated actor fields", failures)
	_expect((state.interactables["door_north"] as InteractableState).type == &"door", "apply() should not touch the interactable's type", failures)


static func _test_serialization_round_trip(failures: Array[String]) -> void:
	var state := _make_state(&"exploration")
	var door := _add_door(state)
	door.state = &"open"
	var restored := BattleState.from_dict(state.to_dict())
	_expect(restored.interactables.has("door_north"), "interactables did not round-trip through to_dict/from_dict", failures)
	if restored.interactables.has("door_north"):
		var restored_door: InteractableState = restored.interactables["door_north"]
		_expect(restored_door.type == &"door", "interactable type did not round-trip", failures)
		_expect(restored_door.state == &"open", "interactable state did not round-trip", failures)
		_expect(restored_door.position.is_equal_approx(door.position), "interactable position did not round-trip", failures)
		_expect(is_equal_approx(restored_door.interact_range, door.interact_range), "interactable interact_range did not round-trip", failures)

	var chest := _add_chest(state)
	chest.contents.append(&"healing_potion")
	restored = BattleState.from_dict(state.to_dict())
	_expect((restored.interactables["chest_a"] as InteractableState).contents == [&"healing_potion"], "interactable contents did not round-trip", failures)


static func _test_equal_inputs_produce_equal_resolution(failures: Array[String]) -> void:
	var first_state := _make_state(&"exploration")
	_add_door(first_state)
	var second_state := _make_state(&"exploration")
	_add_door(second_state)
	var command := _interact_command(1, "door_north")
	var first_result := Resolver.resolve(first_state, command, FakeNavProvider.new(), FakeLosProvider.new())
	var second_result := Resolver.resolve(second_state, command, FakeNavProvider.new(), FakeLosProvider.new())
	_expect(
		TestHelpers.event_log_entry(first_result) == TestHelpers.event_log_entry(second_result),
		"equal state and command produced different interact resolutions",
		failures,
	)


static func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
