class_name TestEquipment
extends RefCounted

## Fase C2: proves ActorDefinition/ItemDefinition content (Knight, Longsword,
## Leather Armor) is real, ordered, and independent per built ActorState;
## that Equipment resolves slots to items; and that resolver attacks read the
## statistics AttackMath derives from that equipment.

static func run() -> Dictionary:
	var failures: Array[String] = []
	_test_default_library_has_ordered_knight_content(failures)
	_test_from_definition_builds_independent_actor(failures)
	_test_equipment_resolves_slots_to_items(failures)
	_test_resolver_attack_uses_derived_statistics(failures)
	_test_actor_content_serialization_round_trip(failures)
	_test_weapon_presentation_follows_the_wielded_item(failures)
	return {"name": "unit/test_equipment", "failures": failures}


## The bow, its hand, and its arrow belong to the shortbow, so only its wielder
## (the archer stat block) shows them; melee weapons stay in the right hand
## with nothing to shoot.
static func _test_weapon_presentation_follows_the_wielded_item(failures: Array[String]) -> void:
	var defs := DefinitionLibrary.get_default()
	var archer := ActorState.from_definition(defs.get_actor(&"archer"), 3, &"enemies", Vector3.ZERO)
	var bow := Equipment.weapon(archer, defs)
	_expect(bow != null and bow.id == &"shortbow", "the archer should wield the shortbow", failures)
	if bow != null:
		_expect(bow.held_bone == &"handslot.l", "the bow should be held in the off (left) hand", failures)
		# KayKit authors the bow with its string away from the hand's palm side.
		_expect(bow.held_rotation_degrees == Vector3(0, 0, 180), "the bow should be rolled so its string faces the archer", failures)
		_expect(ResourceLoader.exists(bow.held_model_path) and ResourceLoader.exists(bow.projectile_model_path), "the shortbow's held bow and arrow models should exist", failures)
	for item_id in [&"longsword", &"scimitar", &"dagger"]:
		var item := defs.get_item(item_id)
		_expect(item.held_bone == &"handslot.r" and item.projectile_model_path.is_empty() and ResourceLoader.exists(item.held_model_path), "%s should be held in the right hand with no projectile" % item_id, failures)


static func _test_default_library_has_ordered_knight_content(failures: Array[String]) -> void:
	var defs := DefinitionLibrary.get_default()
	_expect(defs.has_actor(&"knight"), "default library is missing the knight ActorDefinition", failures)
	_expect(defs.has_item(&"longsword"), "default library is missing the longsword ItemDefinition", failures)
	_expect(defs.has_item(&"leather_armor"), "default library is missing the leather_armor ItemDefinition", failures)
	_expect(defs.has_item(&"dagger"), "default library is missing the dagger ItemDefinition", failures)
	_expect(defs.ordered_actor_ids() == [&"knight", &"raider", &"archer", &"bandit_scout", &"bandit_raider", &"bandit_chieftain"], "ordered_actor_ids did not match the fixed actor manifest order", failures)
	_expect(defs.ordered_item_ids() == [&"longsword", &"leather_armor", &"dagger", &"healing_potion", &"shortbow", &"chainmail", &"scimitar", &"studded_leather", &"toppling_club"], "ordered_item_ids did not match the fixed item manifest order", failures)
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
	_expect(actor.weapon_proficiencies == knight.weapon_proficiencies, "from_definition did not copy the definition's weapon_proficiencies", failures)
	_expect(actor.definition_id == &"knight", "from_definition did not stamp definition_id", failures)

	# Mutating the built actor must never reach back into the shared, cached
	# ActorDefinition resource -- a second actor built from the same
	# definition must not see the first actor's changes.
	actor.ability_ids.append(&"extra_ability")
	actor.equipment_slots[&"weapon"] = &"changed"
	actor.inventory.append(&"looted_item")
	actor.weapon_proficiencies.clear()
	var second_actor := ActorState.from_definition(knight, 8, &"heroes", Vector3.ZERO)
	_expect(not second_actor.ability_ids.has(&"extra_ability"), "actors built from the same ActorDefinition shared a mutable ability_ids array", failures)
	_expect(second_actor.equipment_slots.get(&"weapon") == &"longsword", "actors built from the same ActorDefinition shared a mutable equipment_slots dictionary", failures)
	_expect(second_actor.inventory == [&"healing_potion"], "actors built from the same ActorDefinition shared a mutable inventory array", failures)
	_expect(second_actor.weapon_proficiencies.has(&"martial"), "actors built from the same ActorDefinition shared a mutable weapon_proficiencies array", failures)


static func _test_equipment_resolves_slots_to_items(failures: Array[String]) -> void:
	var defs := DefinitionLibrary.get_default()
	var actor := ActorState.from_definition(defs.get_actor(&"knight"), 1, &"heroes", Vector3.ZERO)
	_expect(Equipment.weapon(actor, defs) == defs.get_item(&"longsword"), "the knight's weapon slot did not resolve to the longsword", failures)
	_expect(Equipment.armor(actor, defs) == defs.get_item(&"chainmail"), "the knight's armor slot did not resolve to the chainmail", failures)
	var unequipped := ActorState.new()
	_expect(Equipment.weapon(unequipped, defs) == null and Equipment.armor(unequipped, defs) == null, "an empty slot should resolve to no item", failures)
	_expect(not Equipment.is_ranged_weapon(unequipped, defs) and is_equal_approx(Equipment.normal_range(unequipped, defs, 1.5), 1.5), "an unarmed actor should fall back to the ability's own range", failures)


static func _test_resolver_attack_uses_derived_statistics(failures: Array[String]) -> void:
	var defs := DefinitionLibrary.get_default()
	var state := TestHelpers.make_battle(42)
	var knight := ActorState.from_definition(defs.get_actor(&"knight"), 1, &"heroes", Vector3.ZERO)
	state.actors[1] = knight
	var attack := Command.create(&"basic_attack", 1)
	attack.target_id = 2
	var result := Resolver.resolve(state, attack, FakeNavProvider.new(), FakeLosProvider.new())
	var attack_event := result.events[0]
	_expect(attack_event.type == &"attack_rolled", "equipped knight's basic attack did not resolve an attack roll", failures)
	# Strength 14 (+2) with a proficient martial longsword (+2).
	_expect(int(attack_event.data["attack_bonus"]) == 4 and int(attack_event.data["total"]) == int(attack_event.data["roll"]) + 4, "attack_rolled did not use the derived +4 longsword bonus", failures)
	_expect(attack_event.data["weapon_id"] == &"longsword" and attack_event.data["attack_ability"] == &"strength", "attack_rolled did not name the weapon and ability behind its bonus", failures)
	_expect(int(attack_event.data["ability_modifier"]) == 2 and int(attack_event.data["proficiency_bonus"]) == 2 and int(attack_event.data["magic_bonus"]) == 0, "attack_rolled did not expose the parts of its bonus", failures)
	# The make_battle enemy is unarmored with Dexterity 10.
	_expect(int(attack_event.data["armor_class"]) == 10 and int(attack_event.data["target_armor_class"]) == 10, "attack_rolled did not use the target's derived AC", failures)


static func _test_actor_content_serialization_round_trip(failures: Array[String]) -> void:
	var archer := DefinitionLibrary.get_default().get_actor(&"archer")
	var actor := ActorState.from_definition(archer, 3, &"heroes", Vector3(2, 0, -1))
	var restored := ActorState.from_dict(_json_dictionary(actor.to_dict()))
	_expect(restored.ability_ids == actor.ability_ids, "ability_ids did not survive a to_dict/from_dict JSON round trip", failures)
	_expect(restored.equipment_slots == actor.equipment_slots, "equipment_slots did not survive a to_dict/from_dict JSON round trip", failures)
	_expect(restored.inventory == actor.inventory, "inventory did not survive a to_dict/from_dict JSON round trip", failures)
	_expect(restored.definition_id == actor.definition_id, "definition_id did not survive a to_dict/from_dict JSON round trip", failures)
	_expect(restored.weapon_proficiencies == [&"simple", &"martial"], "weapon_proficiencies did not survive a to_dict/from_dict JSON round trip", failures)
	_expect(restored.saving_throw_proficiencies == [&"dexterity"], "saving_throw_proficiencies did not survive a to_dict/from_dict JSON round trip", failures)
	_expect(restored.saving_throw_modifier(&"dexterity") == actor.saving_throw_modifier(&"dexterity"), "a restored actor lost its saving throw proficiency", failures)
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
