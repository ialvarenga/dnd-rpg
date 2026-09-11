class_name TestCombatDepth
extends RefCounted

static func run() -> Dictionary:
	var failures: Array[String] = []
	_test_masteries_and_nick(failures)
	_test_push_block_and_fall(failures)
	_test_high_ground_and_weighted_movement(failures)
	_test_ground_point_radius(failures)
	_test_explosive_barrel(failures)
	_test_stealth_surprise_and_ai_determinism(failures)
	_test_tactical_ai_choices(failures)
	return {"name": "unit/test_combat_depth", "failures": failures}


static func _battle(source_definition: StringName, target_definition: StringName = &"raider", seed: int = 42) -> BattleState:
	var definitions := DefinitionLibrary.get_default()
	var state := BattleState.new()
	state.phase = &"combat"
	state.rng_seed = seed
	state.rng_state = seed
	state.initiative_order = [1, 2]
	state.active_combatant_ids = [1, 2]
	state.actors[1] = ActorState.from_definition(definitions.get_actor(source_definition), 1, &"heroes", Vector3.ZERO)
	state.actors[2] = ActorState.from_definition(definitions.get_actor(target_definition), 2, &"enemies", Vector3.RIGHT)
	return state


static func _test_masteries_and_nick(failures: Array[String]) -> void:
	var sap_state := _battle(&"knight")
	TestHelpers.guarantee_hits(sap_state.actors[1])
	var sap := Command.create(&"basic_attack", 1)
	sap.target_id = 2
	var sap_result := Resolver.resolve(sap_state, sap, FakeNavProvider.new(), FakeLosProvider.new())
	_expect(_has_mastery(sap_result, &"sap") and _has_event(sap_result, &"condition_added"), "Longsword Sap did not apply through mastery data", failures)

	var vex_state := _battle(&"archer")
	TestHelpers.guarantee_hits(vex_state.actors[1])
	var vex := Command.create(&"ranged_attack", 1)
	vex.target_id = 2
	var vex_result := Resolver.resolve(vex_state, vex, FakeNavProvider.new(), FakeLosProvider.new())
	_expect(_has_mastery(vex_result, &"vex"), "Shortbow Vex did not trigger", failures)

	var nick_state := _battle(&"bandit_raider")
	TestHelpers.guarantee_hits(nick_state.actors[1])
	var nick := Command.create(&"basic_attack", 1)
	nick.target_id = 2
	var nick_result := Resolver.resolve(nick_state, nick, FakeNavProvider.new(), FakeLosProvider.new())
	var attacks := nick_result.events.filter(func(event: Event): return event.type == &"attack_rolled")
	_expect(attacks.size() == 2 and _has_mastery(nick_result, &"nick"), "Nick did not fold one offhand Light attack into the Attack action", failures)
	if attacks.size() == 2:
		_expect(attacks[1].data.get("weapon_id") == &"dagger" and int(attacks[1].data.get("ability_modifier", 99)) == 1, "Nick attack did not use the authored dagger profile", failures)
	var nick_damage := nick_result.events.filter(func(event: Event): return event.type == &"damage_taken")
	if nick_damage.size() == 2:
		_expect(int(nick_damage[1].data.get("amount", 99)) <= 4, "Nick offhand damage incorrectly added the ability modifier", failures)

	var graze_state := _battle(&"bandit_raider", &"knight", 1)
	var grazer := graze_state.actors[1] as ActorState
	grazer.equipment_slots.erase(&"offhand")
	grazer.strength = 1
	grazer.dexterity = 1
	grazer.proficiency_bonus = 0
	var graze := Command.create(&"basic_attack", 1)
	graze.target_id = 2
	var graze_result := Resolver.resolve(graze_state, graze, FakeNavProvider.new(), FakeLosProvider.new())
	_expect(_has_mastery(graze_result, &"graze"), "Enemy scimitar Graze did not trigger on a miss", failures)

	var topple_state := _battle(&"bandit_chieftain")
	TestHelpers.guarantee_hits(topple_state.actors[1])
	var target := topple_state.actors[2] as ActorState
	target.constitution = 1
	target.saving_throw_proficiencies.clear()
	var topple := Command.create(&"basic_attack", 1)
	topple.target_id = 2
	var topple_result := Resolver.resolve(topple_state, topple, FakeNavProvider.new(), FakeLosProvider.new())
	_expect(_has_mastery(topple_result, &"topple") and topple_result.events.any(func(event: Event): return event.type == &"condition_added" and event.data.get("condition") == &"prone"), "Toppling Club did not force its Constitution save and Prone", failures)


static func _test_push_block_and_fall(failures: Array[String]) -> void:
	var state := _battle(&"knight")
	var source := state.actors[1] as ActorState
	var target := state.actors[2] as ActorState
	source.strength = 30
	target.strength = 1
	target.dexterity = 1
	var push := Command.create(&"shove", 1)
	push.target_id = 2
	push.metadata["mode"] = &"push"
	var nav := FakeNavProvider.new()
	nav.set_push_result(target.position, Vector3.RIGHT, 3.0, {"landing_position": Vector3(4, -4, 0), "blocked": false, "fell": true, "fall_distance": 4.0})
	var result := Resolver.resolve(state, push, nav, FakeLosProvider.new())
	_expect(_has_event(result, &"forced_movement") and _has_event(result, &"fall_started"), "Shove Push did not emit displacement and fall outcomes", failures)
	_expect(not _has_event(result, &"movement_spent"), "forced movement consumed the target's movement", failures)
	var blocked_nav := FakeNavProvider.new()
	blocked_nav.set_push_result(target.position, Vector3.RIGHT, 3.0, {"landing_position": target.position, "blocked": true, "fell": false, "fall_distance": 0.0})
	var blocked := Resolver.resolve(state, push, blocked_nav, FakeLosProvider.new())
	_expect(_has_event(blocked, &"forced_movement_blocked"), "wall-blocked Shove did not report a structured blocked outcome", failures)
	var invalid := Command.create(&"shove", 1)
	invalid.target_id = 2
	_expect(_reason(Resolver.resolve(state, invalid, nav, FakeLosProvider.new())) == &"invalid_ability_mode", "Shove accepted a command without Push/Prone metadata", failures)


static func _test_high_ground_and_weighted_movement(failures: Array[String]) -> void:
	var state := _battle(&"archer")
	var attacker := state.actors[1] as ActorState
	var target := state.actors[2] as ActorState
	attacker.position.y = 3.0
	var evaluation := AttackMath.evaluate(state, attacker, target, DefinitionLibrary.get_default(), LosProvider.COVER_NONE, true, 24.0)
	_expect(evaluation.elevation_modifier == 2 and evaluation.elevation_source == &"high_ground", "shared attack math omitted the +2 high-ground source", failures)
	attacker.position.y = -3.0
	evaluation = AttackMath.evaluate(state, attacker, target, DefinitionLibrary.get_default(), LosProvider.COVER_NONE, true, 24.0)
	_expect(evaluation.elevation_modifier == -2, "shared attack math omitted the -2 low-ground modifier", failures)
	var move_state := _battle(&"knight")
	(move_state.actors[1] as ActorState).movement_remaining = 9.0
	var move := Command.create(&"move", 1)
	move.target_pos = Vector3(6, 0, 0)
	var weighted_nav := FakeNavProvider.new()
	weighted_nav.cost_multiplier = 2.0
	var move_result := Resolver.resolve(move_state, move, weighted_nav, FakeLosProvider.new())
	var segment := _event(move_result, &"movement_segment")
	_expect(segment != null and float(segment.data.get("path_cost", 0.0)) <= 9.001 and float(segment.data.get("requested_path_cost", 0.0)) == 12.0, "weighted terrain was not used for budget clamping and preview cost", failures)


static func _test_ground_point_radius(failures: Array[String]) -> void:
	var state := _battle(&"knight")
	var source := state.actors[1] as ActorState
	var target := state.actors[2] as ActorState
	target.position = Vector3(4, 0, 0)
	var outside := target.clone()
	outside.id = 3
	outside.position = Vector3(7, 0, 0)
	state.actors[3] = outside
	state.active_combatant_ids.append(3)
	var ability := AbilityDefinition.new()
	ability.id = &"test_ground_blast"
	ability.costs_action = true
	ability.targeting = &"ground_point"
	ability.target_range_meters = 10.0
	ability.target_radius_meters = 2.0
	var effect := AbilityEffect.new()
	effect.type = &"area_damage"
	effect.damage_die = 4
	effect.damage_dice_count = 1
	effect.damage_type = &"fire"
	effect.save_abilities = [&"dexterity"]
	effect.half_damage_on_save = true
	ability.effects = [effect]
	var definitions := _definitions_with_ability(ability)
	source.ability_ids.append(ability.id)
	var command := Command.create(ability.id, source.id)
	command.target_pos = Vector3(4, 0, 0)
	var result := Resolver.resolve(state, command, FakeNavProvider.new(), FakeLosProvider.new(), definitions)
	var saves := result.events.filter(func(event: Event): return event.type == &"d20_test_rolled")
	_expect(_has_event(result, &"explosion_triggered") and saves.size() == 1 and saves[0].data.actor_id == target.id, "ground-point radius did not affect exactly the actors inside the previewed radius", failures)
	var invalid := Command.create(ability.id, source.id)
	invalid.target_pos = Vector3(INF, 0, 0)
	_expect(_reason(Resolver.resolve(state, invalid, FakeNavProvider.new(), FakeLosProvider.new(), definitions)) == &"invalid_target_point", "ground-point action accepted a non-finite point", failures)
	var blocked_los := FakeLosProvider.new()
	blocked_los.block(source.position, command.target_pos)
	_expect(_reason(Resolver.resolve(state, command, FakeNavProvider.new(), blocked_los, definitions)) == &"no_line_of_sight", "ground-point action ignored total cover", failures)


## Explosive barrels are generic interactable-targeting area_damage content:
## any future ability (e.g. throwing a lit bomb) can trigger one. There is no
## shipped player action that detonates a barrel directly yet, so this test
## builds its own throwaway ability rather than relying on authored content.
static func _test_explosive_barrel(failures: Array[String]) -> void:
	var state := _battle(&"knight")
	(state.actors[1] as ActorState).position = Vector3.ZERO
	(state.actors[2] as ActorState).position = Vector3(5, 0, 0)
	var third := (state.actors[2] as ActorState).clone()
	third.id = 3
	third.position = Vector3(6, 0, 0)
	state.actors[3] = third
	state.active_combatant_ids.append(3)
	var barrel := InteractableState.new()
	barrel.id = "powder_barrel"
	barrel.type = &"explosive_barrel"
	barrel.state = &"closed"
	barrel.position = Vector3(5, 0, 0)
	barrel.tags = [&"explosive", &"area"]
	barrel.blast_radius_meters = 3.5
	barrel.blast_damage_die = 4
	barrel.blast_damage_dice_count = 3
	state.interactables[barrel.id] = barrel
	var ability := AbilityDefinition.new()
	ability.id = &"test_detonate_interactable"
	ability.costs_action = true
	ability.targeting = &"interactable"
	ability.target_range_meters = 24.0
	ability.target_radius_meters = 3.5
	var effect := AbilityEffect.new()
	effect.type = &"area_damage"
	effect.save_abilities = [&"dexterity"]
	effect.save_dc_base = 10
	effect.save_dc_ability = &"dexterity"
	effect.damage_die = 6
	effect.damage_dice_count = 2
	effect.damage_type = &"fire"
	effect.half_damage_on_save = true
	ability.effects = [effect]
	var definitions := _definitions_with_ability(ability)
	(state.actors[1] as ActorState).ability_ids.append(ability.id)
	var command := Command.create(ability.id, 1)
	command.target_interactable_id = barrel.id
	var result := Resolver.resolve(state, command, FakeNavProvider.new(), FakeLosProvider.new(), definitions)
	var saves := result.events.filter(func(event: Event): return event.type == &"d20_test_rolled")
	_expect(_has_event(result, &"explosion_triggered") and _has_event(result, &"interactable_destroyed"), "explosive barrel did not emit explosion and destruction", failures)
	var explosion := _event(result, &"explosion_triggered")
	_expect(explosion != null and explosion.data.damage_die == 4 and explosion.data.damage_dice_count == 3 and explosion.data.damage_rolls.size() == 3, "barrel-authored damage dice did not override the generic detonation fallback", failures)
	_expect(saves.size() == 2 and saves[0].data.actor_id == 2 and saves[1].data.actor_id == 3, "area targets did not resolve in stable actor-id order", failures)
	_expect(result.events.filter(func(event: Event): return event.type == &"damage_taken").size() == 2, "DEX-save-for-half area damage did not resolve every target", failures)
	TestHelpers.apply_result(state, result)
	var interactable_snapshot: Dictionary = state.stable_snapshot().interactables[0]
	_expect(interactable_snapshot.destroyed and interactable_snapshot.blast_damage_die == 4, "stable replay snapshot omitted destroyed/barrel-authoring state", failures)


static func _test_stealth_surprise_and_ai_determinism(failures: Array[String]) -> void:
	var state := _battle(&"knight")
	state.phase = &"exploration"
	state.initiative_order.clear()
	var hero := state.actors[1] as ActorState
	hero.dexterity = 30
	hero.skill_proficiencies = [&"stealth"]
	var sneak := Resolver.resolve(state, Command.create(&"sneak", 1), FakeNavProvider.new(), FakeLosProvider.new())
	TestHelpers.apply_result(state, sneak)
	_expect(hero.sneaking and hero.hidden_from.has(2) and _has_event(sneak, &"stealth_rolled"), "Sneak did not authoritatively establish hidden/detected state", failures)
	var stealth_snapshot: Dictionary = state.stable_snapshot().actors[0]
	_expect(stealth_snapshot.sneaking and stealth_snapshot.stealth_total == hero.stealth_total and stealth_snapshot.hidden_from == [2], "stable replay snapshot omitted stealth/detection state", failures)
	var opening := Command.create(&"basic_attack", 1)
	opening.target_id = 2
	opening.metadata = {"encounter_id": "test", "participant_actor_ids": [1, 2]}
	var opening_result := Resolver.resolve(state, opening, FakeNavProvider.new(), FakeLosProvider.new())
	var initiative := _event(opening_result, &"initiative_established")
	var attack := _event(opening_result, &"attack_rolled")
	_expect(_has_event(opening_result, &"combat_started") and _has_event(opening_result, &"exploration_attack_opened"), "exploration attack did not begin and open the encounter", failures)
	_expect(initiative != null and initiative.data.initiative_rolls.any(func(entry: Dictionary): return entry.actor_id == 2 and entry.disadvantage), "surprised defender did not roll initiative with Disadvantage", failures)
	_expect(attack != null and attack.data.advantage and attack.data.advantage_sources.any(func(source: Dictionary): return source.source == &"hidden_attacker"), "hidden opening attacker did not receive first-attack Advantage", failures)

	var skip_state := _battle(&"knight")
	skip_state.initiative_order = [1, 2]
	skip_state.current_turn_index = 0
	skip_state.skip_round_one_actor_ids = [2]
	var skipped := Resolver.resolve(skip_state, Command.create(&"end_turn", 1), FakeNavProvider.new(), FakeLosProvider.new())
	var next_turn := _event(skipped, &"turn_started")
	_expect(_has_event(skipped, &"surprise_turn_skipped") and next_turn != null and next_turn.data.actor_id == 1 and next_turn.data.round_number == 2, "explicit skip-round-one variant did not skip the surprised turn and advance the round", failures)

	var ai_state := _battle(&"knight", &"bandit_scout")
	ai_state.current_turn_index = 1
	var enemy := ai_state.actors[2] as ActorState
	enemy.hp = 1
	enemy.morale = 0
	var first := EnemyAI.new().choose_command(ai_state, 2, FakeNavProvider.new(), FakeLosProvider.new())
	var changed_rng := ai_state.clone()
	changed_rng.rng_state = 999999
	var second := EnemyAI.new().choose_command(changed_rng, 2, FakeNavProvider.new(), FakeLosProvider.new())
	_expect(first != null and second != null and first.type == &"surrender" and second.type == first.type, "morale choice changed with rng_state or failed to surrender", failures)


static func _test_tactical_ai_choices(failures: Array[String]) -> void:
	var focus := _battle(&"knight", &"bandit_raider")
	focus.current_turn_index = 1
	var enemy := focus.actors[2] as ActorState
	enemy.position = Vector3.ZERO
	var first_hero := focus.actors[1] as ActorState
	first_hero.position = Vector3.LEFT
	var vulnerable := first_hero.clone()
	vulnerable.id = 3
	vulnerable.hp = 2
	vulnerable.position = Vector3.RIGHT
	focus.actors[3] = vulnerable
	focus.active_combatant_ids.append(3)
	var focus_command := EnemyAI.new().choose_command(focus, 2, FakeNavProvider.new(), FakeLosProvider.new(), AIQueryBudget.new())
	_expect(focus_command != null and focus_command.type == &"basic_attack" and focus_command.target_id == 3, "AI did not focus the highest kill-probability target", failures)

	var protection := focus.clone()
	(protection.actors[1] as ActorState).hp = 2
	(protection.actors[3] as ActorState).hp = (protection.actors[3] as ActorState).max_hp
	var leader := enemy.clone()
	leader.id = 4
	leader.position = Vector3(3, 0, 0)
	leader.ai_tags = [&"leader"]
	protection.actors[4] = leader
	protection.active_combatant_ids.append(4)
	var protect_command := EnemyAI.new().choose_command(protection, 2, FakeNavProvider.new(), FakeLosProvider.new(), AIQueryBudget.new())
	_expect(protect_command != null and protect_command.target_id == 3, "protector ignored an enemy threatening its leader", failures)

	var cover := _battle(&"knight", &"archer")
	cover.current_turn_index = 1
	var archer := cover.actors[2] as ActorState
	archer.position = Vector3.ZERO
	archer.action_available = false
	(cover.actors[1] as ActorState).position = Vector3(10, 0, 0)
	var cover_los := FakeLosProvider.new()
	var cover_ai := EnemyAI.new()
	for destination in cover_ai._ranged_cover_destinations(archer, cover.actors[1]):
		cover_los.set_cover(destination, (cover.actors[1] as ActorState).position, LosProvider.COVER_HALF)
	var cover_command := cover_ai.choose_command(cover, 2, FakeNavProvider.new(), cover_los, AIQueryBudget.new())
	_expect(cover_command != null and cover_command.type == &"move" and cover_command.metadata.get("tactic") == &"cover_seek", "ranged AI did not seek the bounded cover candidate", failures)

	# Friendly-fire-aware area targeting (EnemyAI always reads
	# DefinitionLibrary.get_default(), so this needs a real authored
	# interactable-targeting ability, not a test-only one) is untested until
	# a shipped ability actually triggers explosive interactables -- e.g. a
	# thrown bomb. _test_explosive_barrel covers the underlying Resolver
	# mechanics generically in the meantime.

	var flee := _battle(&"knight", &"bandit_scout")
	flee.current_turn_index = 1
	var coward := flee.actors[2] as ActorState
	coward.position = Vector3.ZERO
	coward.hp = maxi(2, coward.max_hp / 2)
	coward.morale = 20
	(flee.actors[1] as ActorState).position = Vector3(8, 0, 0)
	var flee_command := EnemyAI.new().choose_command(flee, 2, FakeNavProvider.new(), FakeLosProvider.new(), AIQueryBudget.new())
	_expect(flee_command != null and flee_command.type == &"move" and flee_command.metadata.get("tactic") == &"flee", "low-morale AI did not flee before reaching surrender threshold", failures)


static func _event(result: ResolutionResult, type: StringName) -> Event:
	for event in result.events:
		if event.type == type:
			return event
	return null


static func _definitions_with_ability(ability: AbilityDefinition) -> DefinitionLibrary:
	var default := DefinitionLibrary.get_default()
	var definitions := DefinitionLibrary.new()
	definitions.abilities = default.abilities.duplicate()
	definitions.conditions = default.conditions.duplicate()
	definitions.items = default.items.duplicate()
	definitions.actors = default.actors.duplicate()
	definitions.add_ability(ability)
	return definitions


static func _has_event(result: ResolutionResult, type: StringName) -> bool:
	return _event(result, type) != null


static func _has_mastery(result: ResolutionResult, mastery: StringName) -> bool:
	return result.events.any(func(event: Event): return event.type == &"mastery_triggered" and event.data.get("mastery") == mastery)


static func _reason(result: ResolutionResult) -> StringName:
	var rejection := _event(result, &"command_rejected")
	return rejection.data.get("reason", &"") if rejection != null else &""


static func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
