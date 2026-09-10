class_name TestAttackMath
extends RefCounted

## E0: attack bonus, damage, and AC are derived from ability scores,
## proficiency, and equipment by the one AttackMath implementation that
## Resolver, EnemyAI, and the HUD all consume.

static func run() -> Dictionary:
	var failures: Array[String] = []
	_test_strength_weapon_profile(failures)
	_test_finesse_uses_better_ability(failures)
	_test_ranged_weapon_uses_dexterity(failures)
	_test_proficiency_by_category_or_weapon_id(failures)
	_test_magic_bonus(failures)
	_test_unarmed_strike(failures)
	_test_armor_categories(failures)
	_test_shipping_stat_blocks(failures)
	_test_hit_and_critical_probability(failures)
	_test_roll_mode_sources(failures)
	_test_expected_outcome_counts_every_face(failures)
	_test_resolver_rolls_derived_damage(failures)
	_test_resolver_and_hud_agree_with_attack_math(failures)
	return {"name": "unit/test_attack_math", "failures": failures}


static func _test_strength_weapon_profile(failures: Array[String]) -> void:
	var defs := DefinitionLibrary.get_default()
	var knight := _actor_from(&"knight")
	var profile := AttackMath.weapon_profile(knight, defs)
	_expect(profile["weapon_id"] == &"longsword" and profile["attack_ability"] == &"strength", "a longsword should attack with Strength", failures)
	_expect(int(profile["ability_modifier"]) == 2 and bool(profile["proficient"]) and int(profile["proficiency_bonus"]) == 2, "the knight should add Strength +2 and proficiency +2", failures)
	_expect(int(profile["attack_bonus"]) == 4, "the knight's longsword attack should be +4", failures)
	_expect(int(profile["damage_dice_count"]) == 1 and int(profile["damage_die"]) == 8 and int(profile["damage_modifier"]) == 2, "the knight's longsword should deal 1d8 + 2", failures)
	_expect(profile["damage_type"] == &"slashing", "the longsword should deal slashing damage", failures)


static func _test_finesse_uses_better_ability(failures: Array[String]) -> void:
	var defs := DefinitionLibrary.get_default()
	var raider := _actor_from(&"raider")
	var dagger := AttackMath.weapon_profile(raider, defs)
	_expect(dagger["attack_ability"] == &"dexterity" and int(dagger["attack_bonus"]) == 4 and int(dagger["damage_modifier"]) == 2, "a finesse dagger should use the raider's better Dexterity (+4, 1d4 + 2)", failures)
	var chieftain := _actor_from(&"bandit_chieftain")
	var scimitar := AttackMath.weapon_profile(chieftain, defs)
	_expect(scimitar["attack_ability"] == &"strength" and int(scimitar["attack_bonus"]) == 4 and int(scimitar["damage_modifier"]) == 2, "a finesse scimitar should use the chieftain's better Strength (+4, 1d6 + 2)", failures)
	var clumsy := _actor_from(&"raider")
	clumsy.equipment_slots[&"weapon"] = &"longsword"
	_expect(AttackMath.weapon_profile(clumsy, defs)["attack_ability"] == &"strength", "a weapon without Finesse must use Strength even when Dexterity is better", failures)


static func _test_ranged_weapon_uses_dexterity(failures: Array[String]) -> void:
	var defs := DefinitionLibrary.get_default()
	var archer := _actor_from(&"archer")
	archer.strength = 20
	var profile := AttackMath.weapon_profile(archer, defs)
	_expect(profile["attack_ability"] == &"dexterity" and int(profile["attack_bonus"]) == 4 and int(profile["damage_modifier"]) == 2, "a shortbow should always attack with Dexterity (+4, 1d6 + 2)", failures)


static func _test_proficiency_by_category_or_weapon_id(failures: Array[String]) -> void:
	var defs := DefinitionLibrary.get_default()
	var knight := _actor_from(&"knight")
	knight.weapon_proficiencies = [&"simple"]
	var untrained := AttackMath.weapon_profile(knight, defs)
	_expect(not bool(untrained["proficient"]) and int(untrained["proficiency_bonus"]) == 0 and int(untrained["attack_bonus"]) == 2, "a martial weapon without martial training should add no proficiency", failures)
	knight.weapon_proficiencies = [&"longsword"]
	_expect(int(AttackMath.weapon_profile(knight, defs)["attack_bonus"]) == 4, "proficiency granted by the weapon's own id should apply", failures)


static func _test_magic_bonus(failures: Array[String]) -> void:
	var defs := DefinitionLibrary.new()
	var sword := ItemDefinition.new()
	sword.id = &"longsword_plus_one"
	sword.slot = &"weapon"
	sword.weapon_category = &"martial"
	sword.damage_die = 8
	sword.magic_bonus = 1
	defs.add_item(sword)
	var plate := ItemDefinition.new()
	plate.id = &"plate_plus_one"
	plate.slot = &"armor"
	plate.armor_category = &"heavy"
	plate.base_armor_class = 18
	plate.magic_bonus = 1
	defs.add_item(plate)
	var actor := _actor_from(&"knight")
	actor.equipment_slots = {&"weapon": sword.id, &"armor": plate.id}
	var profile := AttackMath.weapon_profile(actor, defs)
	_expect(int(profile["magic_bonus"]) == 1 and int(profile["attack_bonus"]) == 5 and int(profile["damage_modifier"]) == 3, "a +1 weapon should add 1 to both attack and damage", failures)
	_expect(int(AttackMath.armor_class(actor, defs)["total"]) == 19, "+1 plate should add 1 to its base AC", failures)


static func _test_unarmed_strike(failures: Array[String]) -> void:
	var actor := ActorState.new()
	actor.strength = 16
	var profile := AttackMath.weapon_profile(actor, DefinitionLibrary.get_default())
	_expect(profile["weapon_id"] == &"" and bool(profile["proficient"]) and int(profile["attack_bonus"]) == 5, "an unarmed strike should be proficient: Strength +3 plus proficiency +2", failures)
	_expect(int(profile["damage_dice_count"]) == 0 and int(profile["damage_modifier"]) == 4 and profile["damage_type"] == &"bludgeoning", "an unarmed strike should deal 1 + Strength bludgeoning damage with no die", failures)
	_expect(AttackMath.damage_dice_count(profile, true) == 0, "a critical unarmed strike has no dice to double", failures)
	actor.strength = 1
	_expect(AttackMath.damage_total([], int(AttackMath.weapon_profile(actor, DefinitionLibrary.get_default())["damage_modifier"])) == 1, "every hit should deal at least 1 damage", failures)


static func _test_armor_categories(failures: Array[String]) -> void:
	var defs := DefinitionLibrary.new()
	var breastplate := ItemDefinition.new()
	breastplate.id = &"breastplate"
	breastplate.slot = &"armor"
	breastplate.armor_category = &"medium"
	breastplate.base_armor_class = 14
	defs.add_item(breastplate)
	for item_id in [&"leather_armor", &"chainmail"]:
		defs.add_item(DefinitionLibrary.get_default().get_item(item_id))
	var actor := ActorState.new()
	actor.dexterity = 18
	_expect(int(AttackMath.armor_class(actor, defs)["total"]) == 14, "unarmored AC should be 10 + Dexterity", failures)
	actor.equipment_slots = {&"armor": &"leather_armor"}
	_expect(int(AttackMath.armor_class(actor, defs)["total"]) == 15, "light armor should add the full Dexterity modifier", failures)
	actor.equipment_slots = {&"armor": &"breastplate"}
	var medium := AttackMath.armor_class(actor, defs)
	_expect(int(medium["total"]) == 16 and int(medium["dexterity_bonus"]) == 2, "medium armor should cap Dexterity at +2", failures)
	actor.equipment_slots = {&"armor": &"chainmail"}
	_expect(int(AttackMath.armor_class(actor, defs)["total"]) == 16, "heavy armor should ignore a high Dexterity", failures)
	actor.dexterity = 6
	_expect(int(AttackMath.armor_class(actor, defs)["total"]) == 16, "heavy armor should ignore a low Dexterity too", failures)
	actor.equipment_slots = {&"armor": &"leather_armor"}
	_expect(int(AttackMath.armor_class(actor, defs)["total"]) == 9, "light armor should subtract a negative Dexterity modifier", failures)


## Pins the shipped balance so a content edit that silently moves an enemy's
## numbers fails here instead of in a playtest.
static func _test_shipping_stat_blocks(failures: Array[String]) -> void:
	var defs := DefinitionLibrary.get_default()
	var expected := {
		&"knight": [16, 4, 8, 2], &"raider": [12, 4, 4, 2], &"archer": [12, 4, 6, 2],
		&"bandit_scout": [12, 4, 4, 2], &"bandit_raider": [12, 3, 4, 1], &"bandit_chieftain": [13, 4, 6, 2],
	}
	for actor_id in expected:
		var actor := _actor_from(actor_id)
		var profile := AttackMath.weapon_profile(actor, defs)
		var actual := [int(AttackMath.armor_class(actor, defs)["total"]), int(profile["attack_bonus"]), int(profile["damage_die"]), int(profile["damage_modifier"])]
		_expect(actual == expected[actor_id], "%s derived [AC, attack, die, damage modifier] %s instead of %s" % [actor_id, actual, expected[actor_id]], failures)


static func _test_hit_and_critical_probability(failures: Array[String]) -> void:
	_expect(is_equal_approx(AttackMath.hit_probability(4, 15, false, false), 0.5), "+4 against AC 15 should hit on 11-20", failures)
	_expect(is_equal_approx(AttackMath.hit_probability(4, 15, true, false), 0.75), "Advantage should hit unless both dice miss", failures)
	_expect(is_equal_approx(AttackMath.hit_probability(4, 15, false, true), 0.25), "Disadvantage should hit only when both dice hit", failures)
	_expect(is_equal_approx(AttackMath.hit_probability(100, 5, false, false), 0.95), "a natural 1 should always miss", failures)
	_expect(is_equal_approx(AttackMath.hit_probability(-100, 30, false, false), 0.05), "a natural 20 should always hit", failures)
	_expect(is_equal_approx(AttackMath.critical_probability(false, false), 0.05) and is_equal_approx(AttackMath.critical_probability(true, false), 0.0975), "critical chance should follow the roll mode", failures)
	_expect(not AttackMath.is_hit(1, 100, 5) and AttackMath.is_hit(20, -100, 30) and AttackMath.is_hit(11, 4, 15) and not AttackMath.is_hit(10, 4, 15), "is_hit should compare the total against AC with natural 1/20 overrides", failures)
	_expect(AttackMath.cover_bonus(LosProvider.COVER_NONE) == 0 and AttackMath.cover_bonus(LosProvider.COVER_HALF) == 2 and AttackMath.cover_bonus(LosProvider.COVER_THREE_QUARTERS) == 5, "cover should add +2 (half) or +5 (three-quarters) AC", failures)


static func _test_roll_mode_sources(failures: Array[String]) -> void:
	var defs := DefinitionLibrary.get_default()
	var state := TestHelpers.make_battle()
	var hero: ActorState = state.actors[1]
	var enemy: ActorState = state.actors[2]
	enemy.add_condition(&"prone")
	var prone_target := AttackMath.roll_mode(hero, enemy, defs, false, 1.5, false)
	_expect(prone_target["advantage"] and prone_target["advantage_sources"] == [{"source": &"prone", "actor_id": enemy.id}], "a close melee attack against a prone target should have Advantage from the target's Prone", failures)
	hero.add_condition(&"poisoned")
	var cancelled := AttackMath.roll_mode(hero, enemy, defs, false, 1.5, false)
	_expect(not cancelled["advantage"] and not cancelled["disadvantage"], "Advantage and Disadvantage should cancel", failures)
	_expect(cancelled["disadvantage_sources"] == [{"source": &"poisoned", "actor_id": hero.id}] and not (cancelled["advantage_sources"] as Array).is_empty(), "cancelled roll modes should still report both sources", failures)
	hero.remove_condition(&"poisoned")
	enemy.remove_condition(&"prone")
	enemy.position = Vector3(30.0, 0.0, 0.0)
	var long_shot := AttackMath.roll_mode(hero, enemy, defs, true, 24.0, true)
	var sources: Array = long_shot["disadvantage_sources"]
	_expect(long_shot["disadvantage"] and sources.size() == 2 and sources[0]["source"] == AttackMath.SOURCE_LONG_RANGE and sources[1]["source"] == AttackMath.SOURCE_THREATENED, "a threatened long-range shot should list both Disadvantage sources", failures)
	enemy.position = Vector3(1.0, 0.0, 0.0)
	_expect(AttackMath.is_threatened(state, hero), "an adjacent conscious hostile should threaten", failures)
	enemy.add_condition(&"unconscious")
	_expect(not AttackMath.is_threatened(state, hero), "an unconscious hostile should not threaten", failures)


static func _test_expected_outcome_counts_every_face(failures: Array[String]) -> void:
	var unarmed := {
		"hit_probability": 0.5, "critical_probability": 0.05,
		"damage_dice_count": 0, "damage_die": 0, "damage_modifier": 4,
	}
	var flat := AttackMath.expected_outcome(unarmed, 4)
	_expect(is_equal_approx(float(flat["expected_damage"]), 2.0) and is_equal_approx(float(flat["kill_probability"]), 0.5), "a flat 4-damage attack should average 4 x hit chance and kill 4 HP whenever it hits", failures)
	var dagger := {
		"hit_probability": 0.5, "critical_probability": 0.05,
		"damage_dice_count": 1, "damage_die": 4, "damage_modifier": 0,
	}
	var rolled := AttackMath.expected_outcome(dagger, 4)
	# Normal hit (0.45): 1d4 averages 2.5, reaches 4 on one face. Critical
	# (0.05): 2d4 averages 5, reaches 4 on 13 of 16 pairs.
	_expect(is_equal_approx(float(rolled["expected_damage"]), 0.45 * 2.5 + 0.05 * 5.0), "expected damage should weight normal and critical dice", failures)
	_expect(is_equal_approx(float(rolled["kill_probability"]), 0.45 * 0.25 + 0.05 * 13.0 / 16.0), "kill probability should count every die face", failures)


## A critical weapon hit rolls two damage dice; an unarmed hit rolls none.
static func _test_resolver_rolls_derived_damage(failures: Array[String]) -> void:
	var critical_seed := -1
	for seed in range(1, 5000):
		if int(Dice.roll_die(seed, 20)["value"]) == 20:
			critical_seed = seed
			break
	_expect(critical_seed > 0, "no seed produced a natural 20", failures)
	if critical_seed < 0:
		return
	var state := TestHelpers.make_battle(critical_seed)
	var attack := Command.create(&"basic_attack", 1)
	attack.target_id = 2
	var result := Resolver.resolve(state, attack, FakeNavProvider.new(), FakeLosProvider.new())
	var d20 := Dice.roll_die(critical_seed, 20)
	var dice := Dice.roll_dice(int(d20["next_rng_state"]), 2, 6)
	var damage := _event(result, &"damage_taken")
	_expect(_event(result, &"attack_rolled").data["critical"] and damage != null and int(damage.data["amount"]) == int(dice["total"]) + 3, "a critical scimitar hit should deal 2d6 + 3", failures)
	_expect(result.next_rng_state == int(dice["next_rng_state"]), "a critical hit should consume exactly the d20 and two damage dice", failures)

	var unarmed_state := TestHelpers.make_battle(critical_seed)
	TestHelpers.set_fixed_damage(unarmed_state.actors[1] as ActorState, 7)
	var unarmed := Resolver.resolve(unarmed_state, attack, FakeNavProvider.new(), FakeLosProvider.new())
	var unarmed_damage := _event(unarmed, &"damage_taken")
	_expect(unarmed_damage != null and int(unarmed_damage.data["amount"]) == 7 and unarmed_damage.data["damage_type"] == &"bludgeoning", "a critical unarmed strike should still deal exactly 1 + Strength bludgeoning", failures)
	_expect(unarmed.next_rng_state == int(d20["next_rng_state"]), "an unarmed strike should roll no damage dice", failures)


static func _test_resolver_and_hud_agree_with_attack_math(failures: Array[String]) -> void:
	var defs := DefinitionLibrary.get_default()
	var state := TestHelpers.make_battle(42)
	var knight := _actor_from(&"knight")
	state.actors[1] = knight
	(state.actors[2] as ActorState).add_condition(&"dodging")
	var los := FakeLosProvider.new()
	los.set_cover(knight.position, (state.actors[2] as ActorState).position, LosProvider.COVER_HALF)
	var expected := AttackMath.evaluate(state, knight, state.actors[2], defs, LosProvider.COVER_HALF, false, 1.5)
	var attack := Command.create(&"basic_attack", 1)
	attack.target_id = 2
	var rolled := _event(Resolver.resolve(state, attack, FakeNavProvider.new(), los), &"attack_rolled")
	for key in ["attack_bonus", "armor_class", "cover_bonus", "advantage", "disadvantage", "disadvantage_sources"]:
		_expect(rolled != null and rolled.data[key] == expected[key], "attack_rolled %s drifted from AttackMath.evaluate" % key, failures)
	_expect(int(expected["armor_class"]) == 12 and expected["disadvantage"], "the dodging enemy behind half cover should be AC 12 at Disadvantage", failures)
	var tooltip := String(HudViewModel.for_actor(state, 1, defs)["action_availability"][0]["tooltip"])
	_expect(tooltip.contains("Attack +%d (Str +2, Prof +2)" % int(expected["attack_bonus"])), "the attack tooltip should show AttackMath's bonus and its parts, got: %s" % tooltip, failures)
	_expect(int(HudViewModel.for_actor(state, 1, defs)["armor_class"]) == 16, "the HUD should show the knight's derived chainmail AC", failures)


static func _actor_from(actor_id: StringName) -> ActorState:
	return ActorState.from_definition(DefinitionLibrary.get_default().get_actor(actor_id), 1, &"heroes", Vector3.ZERO)


static func _event(result: ResolutionResult, event_type: StringName) -> Event:
	for event in result.events:
		if event.type == event_type:
			return event
	return null


static func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
