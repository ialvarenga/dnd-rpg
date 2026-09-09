class_name D20Test
extends RefCounted

## Deterministic D20 test shared by saving throws and future ability checks.
## The caller supplies all modifiers so this module remains content-agnostic.
static func roll(
	rng_state: int,
	modifier: int,
	difficulty_class: int,
	advantage: bool = false,
	disadvantage: bool = false
) -> Dictionary:
	if advantage and disadvantage:
		advantage = false
		disadvantage = false
	var first := Dice.roll_die(rng_state, 20)
	var rolls: Array[int] = [int(first["value"])]
	var next_rng_state: int = first["next_rng_state"]
	var selected := rolls[0]
	if advantage or disadvantage:
		var second := Dice.roll_die(next_rng_state, 20)
		rolls.append(int(second["value"]))
		next_rng_state = int(second["next_rng_state"])
		selected = maxi(rolls[0], rolls[1]) if advantage else mini(rolls[0], rolls[1])
	var total := selected + modifier
	return {
		"roll": selected,
		"rolls": rolls,
		"modifier": modifier,
		"total": total,
		"difficulty_class": difficulty_class,
		"success": total >= difficulty_class,
		"advantage": advantage,
		"disadvantage": disadvantage,
		"next_rng_state": next_rng_state,
	}
