class_name TestEquipment
extends RefCounted

## Fase C2: proves ActorDefinition/ItemDefinition content (Knight, Longsword,
## Leather Armor) is real, ordered, and independent per built ActorState;
## that Equipment aggregates attack/damage/armor modifiers at resolver read
## time; and that an actor with no equipment aggregates back to exactly its
## own base fields, so pre-C2 actors behave identically.

static func run() -> Dictionary:
	var failures: Array[String] = []
	_test_default_library_has_ordered_knight_content(failures)
	_test_from_definition_builds_independent_actor(failures)
	_test_equipment_aggregates_over_base_stats(failures)
	_test_no_equipment_aggregates_to_base_stats(failures)
	_test_resolver_attack_uses_equipment_aggregation(failures)
	_test_actor_content_serialization_round_trip(failures)
	return {"name": "unit/test_equipment", "failures": failures}


static func _test_default_library_has_ordered_knight_content(failures: Array[String]) -> void:
	var defs := DefinitionLibrary.get_default()
	_expect(defs.has_actor(&"knight"), "default library is missing the knight ActorDefinition", failures)
	_expect(defs.has_item(&"longsword"), "default library is missing the longsword ItemDefinition", failures)
	_expect(defs.has_item(&"leather_armor"), "default library is missing the leather_armor ItemDefinition", failures)
	_expect(defs.has_item(&"dagger"), "default library is missing the dagger ItemDefinition", failures)
	_expect(defs.ordered_actor_ids() == [&"knight", &"raider", &"archer", &"bandit_scout", &"bandit_raider", &"bandit_chieftain"], "ordered_actor_ids did not match the fixed actor manifest order", failures)
	_expect(defs.ordered_item_ids() == [&"longsword", &"leather_armor", &"dagger", &"healing_potion", &"shortbow", &"chainmail"], "ordered_item_ids did not match the fixed item manifest order", failures)
	var shortbow := defs.get_item(&"shortbow")
	_expect(shortbow != null and shortbow.is_ranged_weapon and shortbow.damage_type == &"piercing", "shortbow content is missing its ranged or piercing metadata", failures)
	_expect(is_equal_approx(shortbow.normal_range_meters, 24.0) and is_equal_approx(shortbow.long_range_meters, 96.0), "shortbow range bands do not match the authored metric conversion", failures)


static func _test_from_definition_builds_independent_actor(failures: Array[String]) -> void:
	var knight := DefinitionLibrary.get_default().get_actor(&"knight")
	var actor := ActorState.from_definition(knight, 7, &"heroes", Vector3(1, 0, 2))
	_expect(actor.id == 7 and actor.side == &"heroes" and actor.position == Vector3(1, 0, 2), "from_definition did not apply the requested id/side/position", failures)
	_expect(actor.hp == knight.max_hp and actor.max_hp == knight.max_hp, "from_definition did not start the actor at full HP", failures)
	_expect(is_equal_approx(actor.movement_remaining, knight.movement_speed), "from_definition did not start movement_remaining at full movement_speed", failures)
	_expect(actor.ability_ids == knight.ability_ids, "from_definition did not copy the definition's ability_ids", failures)
	_expect(actor.equipment_slots == knight.equipment_slots, "from_definition did not copy the definition's equipment_slots", failures)
	_expect(actor.definition_id == &"knight", "from_definition did not stamp definition_id", failures)

	# Mutating the built actor must never reach back into the shared, cached
	# ActorDefinition resource -- a second actor built from the same
	# definition must not see the first actor's changes.
	actor.ability_ids.append(&"extra_ability")
	actor.equipment_slots[&"weapon"] = &"changed"
	actor.inventory.append(&"looted_item")
	var second_actor := ActorState.from_definition(knight, 8, &"heroes", Vector3.ZERO)
	_expect(not second_actor.ability_ids.has(&"extra_ability"), "actors built from the same ActorDefinition shared a mutable ability_ids array", failures)
	_expect(second_actor.equipment_slots.get(&"weapon") == &"longsword", "actors built from the same ActorDefinition shared a mutable equipment_slots dictionary", failures)
	_expect(second_actor.inventory == [&"healing_potion"], "actors built from the same ActorDefinition shared a mutable inventory array", failures)


static func _test_equipment_aggregates_over_base_stats(failures: Array[String]) -> void:
	var defs := DefinitionLibrary.get_default()
	var knight := defs.get_actor(&"knight")
	var actor := ActorState.from_definition(knight, 1, &"heroes", Vector3.ZERO)
	var longsword := defs.get_item(&"longsword")
	var chainmail := defs.get_item(&"chainmail")
	_expect(Equipment.aggregate_attack_bonus(actor, defs) == knight.attack_bonus + longsword.attack_bonus_modifier, "equipped attack_bonus did not add the weapon's modifier", failures)
	_expect(Equipment.aggregate_damage_die(actor, defs) == longsword.damage_die, "equipped damage_die did not use the weapon's die", failures)
	_expect(Equipment.aggregate_damage_modifier(actor, defs) == knight.damage_modifier + longsword.damage_modifier, "equipped damage_modifier did not add the weapon's modifier", failures)
	_expect(Equipment.aggregate_armor_class(actor, defs) == knight.armor_class + chainmail.armor_class_bonus, "equipped armor_class did not add the armor's bonus", failures)


static func _test_no_equipment_aggregates_to_base_stats(failures: Array[String]) -> void:
	var defs := DefinitionLibrary.get_default()
	var actor := ActorState.new()
	actor.attack_bonus = 3
	actor.damage_die = 6
	actor.damage_modifier = 1
	actor.armor_class = 13
	_expect(Equipment.aggregate_attack_bonus(actor, defs) == actor.attack_bonus, "an unequipped actor's aggregated attack_bonus drifted from its base value", failures)
	_expect(Equipment.aggregate_damage_die(actor, defs) == actor.damage_die, "an unequipped actor's aggregated damage_die drifted from its base value", failures)
	_expect(Equipment.aggregate_damage_modifier(actor, defs) == actor.damage_modifier, "an unequipped actor's aggregated damage_modifier drifted from its base value", failures)
	_expect(Equipment.aggregate_armor_class(actor, defs) == actor.armor_class, "an unequipped actor's aggregated armor_class drifted from its base value", failures)


static func _test_resolver_attack_uses_equipment_aggregation(failures: Array[String]) -> void:
	var defs := DefinitionLibrary.get_default()
	var state := TestHelpers.make_battle(42)
	var knight := ActorState.from_definition(defs.get_actor(&"knight"), 1, &"heroes", Vector3.ZERO)
	knight.movement_remaining = knight.movement_speed
	state.actors[1] = knight
	(state.actors[2] as ActorState).armor_class = 1
	var attack := Command.create(&"basic_attack", 1)
	attack.target_id = 2
	var result := Resolver.resolve(state, attack, FakeNavProvider.new(), FakeLosProvider.new())
	var attack_event := result.events[0]
	_expect(attack_event.type == &"attack_rolled", "equipped knight's basic attack did not resolve an attack roll", failures)
	var longsword := defs.get_item(&"longsword")
	var expected_total: int = int(attack_event.data["roll"]) + knight.attack_bonus + longsword.attack_bonus_modifier
	_expect(int(attack_event.data["total"]) == expected_total, "attack_rolled's total did not reflect the equipped weapon's attack_bonus_modifier", failures)


static func _test_actor_content_serialization_round_trip(failures: Array[String]) -> void:
	var knight := DefinitionLibrary.get_default().get_actor(&"knight")
	var actor := ActorState.from_definition(knight, 3, &"heroes", Vector3(2, 0, -1))
	var restored := ActorState.from_dict(_json_dictionary(actor.to_dict()))
	_expect(restored.ability_ids == actor.ability_ids, "ability_ids did not survive a to_dict/from_dict JSON round trip", failures)
	_expect(restored.equipment_slots == actor.equipment_slots, "equipment_slots did not survive a to_dict/from_dict JSON round trip", failures)
	_expect(restored.inventory == actor.inventory, "inventory did not survive a to_dict/from_dict JSON round trip", failures)
	_expect(restored.definition_id == actor.definition_id, "definition_id did not survive a to_dict/from_dict JSON round trip", failures)
	for slot_key in restored.equipment_slots.keys():
		_expect(typeof(slot_key) == TYPE_STRING_NAME, "restored equipment_slots key was not a StringName", failures)
		_expect(typeof(restored.equipment_slots[slot_key]) == TYPE_STRING_NAME, "restored equipment_slots value was not a StringName", failures)


static func _json_dictionary(data: Dictionary) -> Dictionary:
	var parsed: Variant = JSON.parse_string(JSON.stringify(data))
	if parsed is Dictionary:
		return parsed
	return {}


static func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
