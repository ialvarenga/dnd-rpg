class_name Dice
extends RefCounted

const MODULUS: int = 2147483648
const MULTIPLIER: int = 1103515245
const INCREMENT: int = 12345


static func roll_die(rng_state: int, sides: int) -> Dictionary:
	assert(sides > 0)
	var normalized_state := posmod(rng_state, MODULUS)
	var next_state := int((normalized_state * MULTIPLIER + INCREMENT) % MODULUS)
	return {"value": (next_state % sides) + 1, "next_rng_state": next_state}

