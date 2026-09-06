class_name TestDefinitions
extends RefCounted

const AbilityTargetingRules = preload("res://sim/ability_targeting.gd")

## A7: proves abilities/conditions are actually resolved from data (not
## hardcoded ids), that unknown definition ids are rejected deterministically,
## and that BattleState carries a content_version.

static func run() -> Dictionary:
	var failures: Array[String] = []
	_test_dash_resolved_from_default_definition(failures)
	_test_dash_effect_magnitude_comes_from_definition_data(failures)
	_test_poisoned_resolved_from_default_definition(failures)
	_test_poisoned_modifier_comes_from_definition_data(failures)
	_test_unknown_ability_definition_is_rejected_deterministically(failures)
	_test_unknown_condition_id_is_ignored_safely(failures)
	_test_definition_library_ignores_definitions_with_missing_id(failures)
	_test_content_version_round_trip(failures)
	_test_consumable_metadata_defaults_clone_and_resource_round_trip(failures)
	_test_perform_attack_effect_checks_and_spends_full_ability_cost(failures)
	_test_attack_targeting_range_uses_ability_data(failures)
	return {"name": "unit/test_definitions", "failures": failures}


static func _test_dash_resolved_from_default_definition(failures: Array[String]) -> void:
	var state := TestHelpers.make_battle()
	var hero: ActorState = state.actors[1]
	var result := Resolver.resolve(state, Command.create(&"dash", 1), FakeNavProvider.new(), FakeLosProvider.new())
	_expect(result.events.size() == 2 and result.events[0].type == &"action_spent" and result.events[1].type == &"movement_gained", "dash did not resolve action/movement events from its definition", failures)
	_expect(is_equal_approx(float(result.events[1].data["amount"]), hero.movement_speed), "dash's default definition did not grant a full movement_speed of movement", failures)


static func _test_dash_effect_magnitude_comes_from_definition_data(failures: Array[String]) -> void:
	# A custom library with a "dash" whose multiplier is data-authored to 2.0
	# proves the resolver reads the amount from the definition instead of a
	# hardcoded "+movement_speed" branch keyed on the ability id.
	var custom := DefinitionLibrary.new()
	custom.add_ability(_make_ability(&"dash", true, [_make_effect(&"add_base_movement", 2.0)]))
	var state := TestHelpers.make_battle()
	var hero: ActorState = state.actors[1]
	var result := Resolver.resolve(state, Command.create(&"dash", 1), FakeNavProvider.new(), FakeLosProvider.new(), custom)
	_expect(is_equal_approx(float(result.events[1].data["amount"]), hero.movement_speed * 2.0), "dash did not use the injected definition's multiplier", failures)


static func _test_poisoned_resolved_from_default_definition(failures: Array[String]) -> void:
	var state := TestHelpers.make_battle()
	(state.actors[1] as ActorState).conditions.append(&"poisoned")
	var attack := Command.create(&"attack", 1)
	attack.target_id = 2
	var result := Resolver.resolve(state, attack, FakeNavProvider.new(), FakeLosProvider.new())
	var rolls: Array = result.events[0].data["rolls"]
	_expect(result.events[0].data["disadvantage"] and rolls.size() == 2, "poisoned's default definition did not apply attack-roll disadvantage", failures)


static func _test_poisoned_modifier_comes_from_definition_data(failures: Array[String]) -> void:
	# A custom library redefines "poisoned" WITHOUT the disadvantage modifier.
	# If the resolver still branched on the literal id this would still show
	# disadvantage; reading the definition means it must not.
	var custom := DefinitionLibrary.new()
	var condition := ConditionDefinition.new()
	condition.id = &"poisoned"
	condition.attack_roll_disadvantage = false
	custom.add_condition(condition)
	custom.add_ability(_make_ability(&"basic_attack", true, [_make_attack_effect()]))
	var state := TestHelpers.make_battle()
	(state.actors[1] as ActorState).conditions.append(&"poisoned")
	var attack := Command.create(&"attack", 1)
	attack.target_id = 2
	var result := Resolver.resolve(state, attack, FakeNavProvider.new(), FakeLosProvider.new(), custom)
	var rolls: Array = result.events[0].data["rolls"]
	_expect(not result.events[0].data["disadvantage"] and rolls.size() == 1, "poisoned kept disadvantage even though the injected definition removed it", failures)


static func _test_unknown_ability_definition_is_rejected_deterministically(failures: Array[String]) -> void:
	var empty_library := DefinitionLibrary.new()
	var state := TestHelpers.make_battle()
	var before_hash := JSON.stringify(state.stable_snapshot()).md5_text()
	var first := Resolver.resolve(state, Command.create(&"dash", 1), FakeNavProvider.new(), FakeLosProvider.new(), empty_library)
	var second := Resolver.resolve(state, Command.create(&"dash", 1), FakeNavProvider.new(), FakeLosProvider.new(), empty_library)
	_expect(first.events.size() == 1 and first.events[0].type == &"command_rejected" and first.events[0].data["reason"] == &"unknown_ability_definition", "missing ability definition was not rejected deterministically", failures)
	_expect(TestHelpers.event_log_entry(first) == TestHelpers.event_log_entry(second), "missing ability definition rejection was not deterministic across identical calls", failures)
	_expect(JSON.stringify(state.stable_snapshot()).md5_text() == before_hash, "unknown ability definition rejection mutated BattleState", failures)

	var unknown_attack_state := TestHelpers.make_battle()
	var attack := Command.create(&"attack", 1)
	attack.target_id = 2
	var attack_rejection := Resolver.resolve(unknown_attack_state, attack, FakeNavProvider.new(), FakeLosProvider.new(), empty_library)
	_expect(attack_rejection.events[0].data["reason"] == &"unknown_ability_definition", "missing basic_attack definition was not rejected deterministically", failures)


static func _test_unknown_condition_id_is_ignored_safely(failures: Array[String]) -> void:
	var state := TestHelpers.make_battle()
	var enemy: ActorState = state.actors[2]
	enemy.conditions.append(&"not_a_real_condition")
	_expect(enemy.is_alive() and enemy.is_conscious() and not enemy.is_prone(), "an unrecognized condition id changed actor eligibility", failures)
	var attack := Command.create(&"attack", 1)
	attack.target_id = 2
	var result := Resolver.resolve(state, attack, FakeNavProvider.new(), FakeLosProvider.new())
	_expect(not result.events[0].data["advantage"] and not result.events[0].data["disadvantage"], "an unrecognized condition id affected attack-roll modifiers", failures)


static func _test_definition_library_ignores_definitions_with_missing_id(failures: Array[String]) -> void:
	var library := DefinitionLibrary.new()
	library.add_ability(_make_ability(&"", true, []))
	library.add_condition(ConditionDefinition.new())
	_expect(library.abilities.is_empty() and library.conditions.is_empty(), "DefinitionLibrary stored a definition with an empty stable id", failures)


static func _test_content_version_round_trip(failures: Array[String]) -> void:
	var state := TestHelpers.make_battle()
	_expect(state.content_version == DefinitionLibrary.CONTENT_VERSION, "BattleState did not default to the current content_version", failures)
	var restored := BattleState.from_dict(_json_dictionary(state.to_dict()))
	_expect(restored.content_version == state.content_version, "content_version did not survive a to_dict/from_dict round trip", failures)
	var default_library := DefinitionLibrary.get_default()
	_expect(default_library.is_compatible_content_version(state.content_version), "default library rejected its own content_version", failures)
	_expect(not default_library.is_compatible_content_version(state.content_version + 1), "default library accepted a mismatched content_version", failures)


static func _test_consumable_metadata_defaults_clone_and_resource_round_trip(failures: Array[String]) -> void:
	var default_effect := AbilityEffect.new()
	var default_item := ItemDefinition.new()
	_expect(default_effect.heal_die == 0 and default_effect.heal_dice_count == 1 and default_effect.heal_modifier == 0 and default_effect.consumes_item_id == &"", "consumable effect metadata did not preserve backwards-compatible defaults", failures)
	_expect(default_item.use_ability_id == &"", "item use_ability_id did not default to non-consumable", failures)

	var effect := AbilityEffect.new()
	effect.type = &"heal"
	effect.heal_die = 4
	effect.heal_dice_count = 2
	effect.heal_modifier = 2
	effect.consumes_item_id = &"healing_potion"
	var item := ItemDefinition.new()
	item.id = &"healing_potion"
	item.display_name = "Healing Potion"
	item.use_ability_id = &"quaff_healing_potion"
	var effect_clone := effect.duplicate(true) as AbilityEffect
	var item_clone := item.duplicate(true) as ItemDefinition
	_expect(_has_consumable_effect_metadata(effect_clone, effect), "consumable effect metadata did not survive Resource cloning", failures)
	_expect(item_clone != null and item_clone.use_ability_id == item.use_ability_id, "item use_ability_id did not survive Resource cloning", failures)

	var ability := _make_ability(&"quaff_healing_potion", true, [effect])
	var ability_path := "user://test_consumable_ability_definition.tres"
	var item_path := "user://test_consumable_item_definition.tres"
	var ability_save_error := ResourceSaver.save(ability, ability_path)
	var item_save_error := ResourceSaver.save(item, item_path)
	var restored_ability := load(ability_path) as AbilityDefinition
	var restored_item := load(item_path) as ItemDefinition
	_expect(ability_save_error == OK and restored_ability != null and restored_ability.effects.size() == 1, "consumable ability definition did not serialize as a valid resource", failures)
	if restored_ability != null and restored_ability.effects.size() == 1:
		_expect(_has_consumable_effect_metadata(restored_ability.effects[0], effect), "consumable effect metadata did not survive resource serialization", failures)
	_expect(item_save_error == OK and restored_item != null and restored_item.use_ability_id == item.use_ability_id, "item use_ability_id did not survive resource serialization", failures)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ability_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(item_path))


static func _has_consumable_effect_metadata(candidate: AbilityEffect, expected: AbilityEffect) -> bool:
	return candidate != null and candidate.heal_die == expected.heal_die and candidate.heal_dice_count == expected.heal_dice_count and candidate.heal_modifier == expected.heal_modifier and candidate.consumes_item_id == expected.consumes_item_id


## Fase C2: a perform_attack effect ability that also declares
## costs_bonus_action and movement_cost. Before AbilityCostRules was shared
## between _resolve_ability_command and _resolve_attack_effect, these were
## silently ignored for any ability whose effects included perform_attack --
## checked here to prove the gap is closed for both rejection and spending.
static func _test_perform_attack_effect_checks_and_spends_full_ability_cost(failures: Array[String]) -> void:
	var custom := DefinitionLibrary.new()
	var ability := AbilityDefinition.new()
	ability.id = &"basic_attack"
	ability.costs_action = true
	ability.costs_bonus_action = true
	ability.movement_cost = 3.0
	ability.effects = [_make_attack_effect()]
	custom.add_ability(ability)

	var blocked_state := TestHelpers.make_battle()
	(blocked_state.actors[1] as ActorState).bonus_action_available = false
	var blocked_attack := Command.create(&"attack", 1)
	blocked_attack.target_id = 2
	var blocked_result := Resolver.resolve(blocked_state, blocked_attack, FakeNavProvider.new(), FakeLosProvider.new(), custom)
	_expect(blocked_result.events[0].type == &"command_rejected" and blocked_result.events[0].data["reason"] == &"bonus_action_unavailable", "perform_attack effect ability did not reject an unaffordable declared bonus_action cost", failures)

	var state := TestHelpers.make_battle()
	var hero: ActorState = state.actors[1]
	var attack := Command.create(&"attack", 1)
	attack.target_id = 2
	var result := Resolver.resolve(state, attack, FakeNavProvider.new(), FakeLosProvider.new(), custom)
	var bonus_spent := false
	var movement_spent_amount := -1.0
	for event in result.events:
		if event.type == &"bonus_action_spent":
			bonus_spent = true
		elif event.type == &"movement_spent":
			movement_spent_amount = float(event.data["amount"])
	_expect(bonus_spent, "perform_attack effect ability did not emit bonus_action_spent for a declared costs_bonus_action", failures)
	_expect(is_equal_approx(movement_spent_amount, 3.0), "perform_attack effect ability did not spend its declared movement_cost", failures)
	TestHelpers.apply_result(state, result)
	_expect(not hero.bonus_action_available, "bonus_action_spent event did not actually consume the actor's bonus action", failures)
	_expect(is_equal_approx(hero.movement_remaining, hero.movement_speed - 3.0), "movement_spent event did not actually consume the actor's movement", failures)


static func _test_attack_targeting_range_uses_ability_data(failures: Array[String]) -> void:
	var definitions := DefinitionLibrary.new()
	var short_attack := _make_ability(&"short_attack", true, [_make_attack_effect()])
	var long_effect := _make_attack_effect()
	long_effect.range_meters = 4.0
	var long_attack := _make_ability(&"long_attack", true, [long_effect])
	definitions.add_ability(short_attack)
	definitions.add_ability(long_attack)
	var state := TestHelpers.make_battle()
	var source: ActorState = state.actors[1]
	var target: ActorState = state.actors[2]
	target.position = source.position + Vector3(3.0, 0.0, 0.0)
	_expect(not AbilityTargetingRules.is_target_in_attack_range(source, target, definitions, &"short_attack"), "targeting preview accepted a target beyond the short attack's data-authored range", failures)
	_expect(AbilityTargetingRules.is_target_in_attack_range(source, target, definitions, &"long_attack"), "targeting preview ignored the long attack's data-authored range", failures)
	var long_attack_command := Command.create(&"long_attack", source.id)
	long_attack_command.target_id = target.id
	var result := Resolver.resolve(state, long_attack_command, FakeNavProvider.new(), FakeLosProvider.new(), definitions)
	_expect(not result.events.is_empty() and result.events[0].type == &"attack_rolled", "resolver did not support a data-defined attack type", failures)


static func _make_effect(type: StringName, multiplier: float) -> AbilityEffect:
	var effect := AbilityEffect.new()
	effect.type = type
	effect.multiplier = multiplier
	return effect


static func _make_attack_effect() -> AbilityEffect:
	var effect := AbilityEffect.new()
	effect.type = &"perform_attack"
	effect.range_meters = 1.5
	effect.is_ranged = false
	effect.attack_kind = &"basic"
	return effect


static func _make_ability(id: StringName, costs_action: bool, effects: Array[AbilityEffect]) -> AbilityDefinition:
	var ability := AbilityDefinition.new()
	ability.id = id
	ability.costs_action = costs_action
	ability.effects = effects
	return ability


static func _json_dictionary(data: Dictionary) -> Dictionary:
	var parsed: Variant = JSON.parse_string(JSON.stringify(data))
	if parsed is Dictionary:
		return parsed
	return {}


static func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
