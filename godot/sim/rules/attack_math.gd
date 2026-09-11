class_name AttackMath
extends RefCounted

## The one implementation of attack arithmetic. Resolver resolves attacks with
## it, EnemyAI scores them with it, and the HUD projects it into tooltips and
## the combat log, so every number shown to the player is the number the dice
## are compared against.
##
## Pure: no RNG, no Nodes, no providers. Callers pass in the cover they already
## queried, and Resolver alone rolls the dice this file counts.
##
## Derived statistics follow SRD 5.2.1 (Equipment / Weapons and Armor; Rules
## Glossary / Unarmed Strike):
## - attack bonus = ability modifier + proficiency bonus (if proficient) +
##   magic bonus. Ranged weapons use Dexterity, Finesse weapons the better of
##   Strength and Dexterity, everything else Strength.
## - damage = weapon die + the same ability modifier + magic bonus. An unarmed
##   strike deals 1 + Strength modifier and has no die.
## - armor class = 10 + Dex unarmored; light armor base + Dex; medium armor
##   base + Dex (max +2); heavy armor base only; plus the armor's magic bonus.

const EquipmentRules = preload("res://sim/equipment.gd")

## SRD 5-foot reach as 1.5 m, the distance at which a target counts as close
## and a hostile threatens a ranged attacker.
const MELEE_REACH_METERS := 1.5
const RANGE_EPSILON := 0.0001

const UNARMORED_BASE_ARMOR_CLASS := 10
const MEDIUM_ARMOR_MAX_DEXTERITY_BONUS := 2
const UNARMED_BASE_DAMAGE := 1
const UNARMED_DAMAGE_TYPE := &"bludgeoning"

const CATEGORY_LIGHT := &"light"
const CATEGORY_MEDIUM := &"medium"
const CATEGORY_HEAVY := &"heavy"
const PROPERTY_FINESSE := &"finesse"

## Advantage/disadvantage sources that do not come from a condition.
const SOURCE_LONG_RANGE := &"long_range"
const SOURCE_THREATENED := &"threatened"


## The attacker's side of an attack: which ability drives it and the bonus
## and damage that follow. Keys: weapon_id (&"" for an unarmed strike),
## attack_ability, ability_modifier, proficient, proficiency_bonus (the part
## actually applied), magic_bonus, attack_bonus, damage_dice_count,
## damage_die, damage_modifier, damage_type.
static func weapon_profile(actor: ActorState, defs: DefinitionLibrary) -> Dictionary:
	var weapon := EquipmentRules.weapon(actor, defs)
	if weapon == null:
		var strength_modifier := actor.ability_modifier(&"strength")
		return {
			"weapon_id": &"", "attack_ability": &"strength", "ability_modifier": strength_modifier,
			"proficient": true, "proficiency_bonus": actor.proficiency_bonus, "magic_bonus": 0,
			"attack_bonus": strength_modifier + actor.proficiency_bonus,
			"damage_dice_count": 0, "damage_die": 0,
			"damage_modifier": UNARMED_BASE_DAMAGE + strength_modifier, "damage_type": UNARMED_DAMAGE_TYPE,
		}
	var ability := attack_ability(actor, weapon)
	var ability_modifier := actor.ability_modifier(ability)
	var proficient := is_proficient(actor, weapon)
	var proficiency_bonus := actor.proficiency_bonus if proficient else 0
	return {
		"weapon_id": weapon.id, "attack_ability": ability, "ability_modifier": ability_modifier,
		"proficient": proficient, "proficiency_bonus": proficiency_bonus, "magic_bonus": weapon.magic_bonus,
		"attack_bonus": ability_modifier + proficiency_bonus + weapon.magic_bonus,
		"damage_dice_count": 1, "damage_die": weapon.damage_die,
		"damage_modifier": ability_modifier + weapon.magic_bonus, "damage_type": weapon.damage_type,
	}


static func attack_ability(actor: ActorState, weapon: ItemDefinition) -> StringName:
	if weapon.is_ranged_weapon:
		return &"dexterity"
	if weapon.weapon_properties.has(PROPERTY_FINESSE) and actor.ability_modifier(&"dexterity") > actor.ability_modifier(&"strength"):
		return &"dexterity"
	return &"strength"


## Proficiency is granted by the weapon's category or by its own id, the two
## ways the SRD phrases class weapon training.
static func is_proficient(actor: ActorState, weapon: ItemDefinition) -> bool:
	return actor.weapon_proficiencies.has(weapon.weapon_category) or actor.weapon_proficiencies.has(weapon.id)


## Keys: armor_id (&"" unarmored), armor_category, base, dexterity_bonus (the
## part actually applied), magic_bonus, total. Cover is not included; it
## belongs to one attack, not to the defender (see evaluate).
static func armor_class(actor: ActorState, defs: DefinitionLibrary) -> Dictionary:
	var armor := EquipmentRules.armor(actor, defs)
	var dexterity_modifier := actor.ability_modifier(&"dexterity")
	var base := UNARMORED_BASE_ARMOR_CLASS
	var dexterity_bonus := dexterity_modifier
	var magic_bonus := 0
	if armor != null:
		base = armor.base_armor_class
		magic_bonus = armor.magic_bonus
		match armor.armor_category:
			CATEGORY_MEDIUM: dexterity_bonus = mini(dexterity_modifier, MEDIUM_ARMOR_MAX_DEXTERITY_BONUS)
			CATEGORY_HEAVY: dexterity_bonus = 0
	return {
		"armor_id": armor.id if armor != null else &"",
		"armor_category": armor.armor_category if armor != null else &"",
		"base": base, "dexterity_bonus": dexterity_bonus, "magic_bonus": magic_bonus,
		"total": base + dexterity_bonus + magic_bonus,
	}


static func cover_bonus(cover: StringName) -> int:
	match cover:
		LosProvider.COVER_HALF: return 2
		LosProvider.COVER_THREE_QUARTERS: return 5
	return 0


## True when a conscious hostile combatant stands within reach of `actor`,
## which gives a ranged attack Disadvantage.
static func is_threatened(state: BattleState, actor: ActorState) -> bool:
	for actor_id in state.actors:
		if not state.active_combatant_ids.is_empty() and not state.active_combatant_ids.has(int(actor_id)):
			continue
		var candidate := state.actors[actor_id] as ActorState
		if candidate.id != actor.id and candidate.side != actor.side and candidate.is_conscious() and candidate.position.distance_to(actor.position) <= MELEE_REACH_METERS + RANGE_EPSILON:
			return true
	return false


## Advantage and Disadvantage for one attack, each with the sources that
## caused it. A source is {"source": StringName, "actor_id": int}: a condition
## id with the actor carrying it, or SOURCE_LONG_RANGE/SOURCE_THREATENED with
## the attacker. Sources are kept even when both sides cancel, so the log can
## say so.
static func roll_mode(attacker: ActorState, target: ActorState, defs: DefinitionLibrary, is_ranged: bool, normal_range: float, threatened: bool) -> Dictionary:
	var distance := attacker.position.distance_to(target.position)
	var target_is_close := distance <= MELEE_REACH_METERS + RANGE_EPSILON
	var advantage_sources: Array[Dictionary] = []
	var disadvantage_sources: Array[Dictionary] = []
	var condition_consumptions: Array[Dictionary] = []
	for condition_state in attacker.condition_states:
		var condition_id: StringName = condition_state.definition_id
		var condition := defs.get_condition(condition_id)
		if condition == null:
			continue
		if condition.attack_roll_disadvantage:
			disadvantage_sources.append(_source(condition_id, attacker.id))
		if condition.next_attack_advantage and _matches_related_actor(condition_state, target.id):
			advantage_sources.append(_source(condition_id, attacker.id))
			_append_condition_consumption(condition_consumptions, attacker.id, condition_state, condition)
		if condition.next_attack_disadvantage and _matches_related_actor(condition_state, target.id):
			disadvantage_sources.append(_source(condition_id, attacker.id))
			_append_condition_consumption(condition_consumptions, attacker.id, condition_state, condition)
	for condition_state in target.condition_states:
		var condition_id: StringName = condition_state.definition_id
		var condition := defs.get_condition(condition_id)
		if condition == null:
			continue
		if condition.melee_advantage_when_close and not is_ranged and target_is_close:
			advantage_sources.append(_source(condition_id, target.id))
		if condition.attacks_against_disadvantage or (condition.ranged_disadvantage_when_not_close and is_ranged and not target_is_close):
			disadvantage_sources.append(_source(condition_id, target.id))
		if condition.next_attack_against_advantage and _matches_related_actor(condition_state, attacker.id):
			advantage_sources.append(_source(condition_id, target.id))
			_append_condition_consumption(condition_consumptions, target.id, condition_state, condition)
		if condition.next_attack_against_disadvantage and _matches_related_actor(condition_state, attacker.id):
			disadvantage_sources.append(_source(condition_id, target.id))
			_append_condition_consumption(condition_consumptions, target.id, condition_state, condition)
	if is_ranged and distance > normal_range + RANGE_EPSILON:
		disadvantage_sources.append(_source(SOURCE_LONG_RANGE, attacker.id))
	if is_ranged and threatened:
		disadvantage_sources.append(_source(SOURCE_THREATENED, attacker.id))
	var advantage := not advantage_sources.is_empty()
	var disadvantage := not disadvantage_sources.is_empty()
	return {
		"advantage": advantage and not disadvantage,
		"disadvantage": disadvantage and not advantage,
		"advantage_sources": advantage_sources,
		"disadvantage_sources": disadvantage_sources,
		"condition_consumptions": condition_consumptions,
	}


static func _matches_related_actor(condition_state: ConditionState, actor_id: int) -> bool:
	return condition_state.related_actor_id < 0 or condition_state.related_actor_id == actor_id


static func _append_condition_consumption(consumptions: Array[Dictionary], owner_id: int, condition_state: ConditionState, condition: ConditionDefinition) -> void:
	for existing in consumptions:
		if existing["condition_actor_id"] == owner_id and existing["condition"] == condition.id:
			return
	consumptions.append({
		"condition_actor_id": owner_id,
		"condition": condition.id,
		"source_actor_id": condition_state.source_actor_id,
		"related_actor_id": condition_state.related_actor_id,
		"consumption": condition.attack_consumption,
	})


## Everything about one attack that is fixed before its d20 is rolled: the
## attacker's weapon_profile, the target's armor, cover, and roll mode, plus
## the resulting hit and critical probabilities. armor_class already includes
## the cover bonus; target_armor_class does not.
static func evaluate(state: BattleState, attacker: ActorState, target: ActorState, defs: DefinitionLibrary, cover: StringName, is_ranged: bool, normal_range: float) -> Dictionary:
	var evaluation := weapon_profile(attacker, defs)
	var target_armor := armor_class(target, defs)
	var bonus := cover_bonus(cover)
	var mode := roll_mode(attacker, target, defs, is_ranged, normal_range, is_ranged and is_threatened(state, attacker))
	var total_armor_class: int = int(target_armor["total"]) + bonus
	evaluation.merge(mode)
	evaluation.merge({
		"is_ranged": is_ranged,
		"target_armor_class": target_armor["total"],
		"cover": cover,
		"cover_bonus": bonus,
		"armor_class": total_armor_class,
		"hit_probability": hit_probability(int(evaluation["attack_bonus"]), total_armor_class, mode["advantage"], mode["disadvantage"]),
		"critical_probability": critical_probability(mode["advantage"], mode["disadvantage"]),
	})
	return evaluation


## A natural 1 always misses and a natural 20 always hits.
static func is_hit(roll: int, attack_bonus: int, armor_class_total: int) -> bool:
	return roll != 1 and (is_critical(roll) or roll + attack_bonus >= armor_class_total)


static func is_critical(roll: int) -> bool:
	return roll == 20


static func hit_probability(attack_bonus: int, armor_class_total: int, advantage: bool, disadvantage: bool) -> float:
	var hit_faces := 0
	for face in range(1, 21):
		if is_hit(face, attack_bonus, armor_class_total):
			hit_faces += 1
	return _apply_roll_mode(float(hit_faces) / 20.0, advantage, disadvantage)


static func critical_probability(advantage: bool, disadvantage: bool) -> float:
	return _apply_roll_mode(1.0 / 20.0, advantage, disadvantage)


## Critical hits roll the attack's damage dice twice; an unarmed strike has no
## dice to double.
static func damage_dice_count(evaluation: Dictionary, critical: bool) -> int:
	return int(evaluation["damage_dice_count"]) * (2 if critical else 1)


## Every hit deals at least 1 damage.
static func damage_total(die_values: Array, damage_modifier: int) -> int:
	var total := damage_modifier
	for value in die_values:
		total += int(value)
	return maxi(1, total)


## Expected value of an evaluated attack against a target with `target_hp`
## hit points, counted over every die face rather than sampled. Keys:
## expected_damage, kill_probability (damage reaching `target_hp`).
static func expected_outcome(evaluation: Dictionary, target_hp: int) -> Dictionary:
	var critical_chance := float(evaluation["critical_probability"])
	var normal_chance := maxf(0.0, float(evaluation["hit_probability"]) - critical_chance)
	var expected_damage := 0.0
	var kill_probability := 0.0
	for weighted in [[normal_chance, false], [critical_chance, true]]:
		var chance: float = weighted[0]
		var distribution := _damage_distribution(damage_dice_count(evaluation, weighted[1]), int(evaluation["damage_die"]), int(evaluation["damage_modifier"]))
		for damage in distribution:
			var probability: float = distribution[damage]
			expected_damage += chance * probability * float(damage)
			if int(damage) >= target_hp:
				kill_probability += chance * probability
	return {"expected_damage": expected_damage, "kill_probability": kill_probability}


static func _apply_roll_mode(single_roll_probability: float, advantage: bool, disadvantage: bool) -> float:
	if advantage:
		return 1.0 - pow(1.0 - single_roll_probability, 2.0)
	if disadvantage:
		return single_roll_probability * single_roll_probability
	return single_roll_probability


## Final damage -> probability for `dice_count` dice of `die` sides plus a
## modifier, after damage_total's minimum of 1.
static func _damage_distribution(dice_count: int, die: int, damage_modifier: int) -> Dictionary:
	var sums := {0: 1.0}
	for _die_index in range(dice_count if die > 0 else 0):
		var next := {}
		for partial in sums:
			for face in range(1, die + 1):
				next[partial + face] = float(next.get(partial + face, 0.0)) + float(sums[partial]) / float(die)
		sums = next
	var distribution := {}
	for dice_sum in sums:
		var damage := maxi(1, int(dice_sum) + damage_modifier)
		distribution[damage] = float(distribution.get(damage, 0.0)) + float(sums[dice_sum])
	return distribution


static func _source(source: StringName, actor_id: int) -> Dictionary:
	return {"source": source, "actor_id": actor_id}
