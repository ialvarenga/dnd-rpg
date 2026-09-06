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


## Rolls `count` dice by repeatedly using roll_die.  Keeping this deliberately
## small makes a multi-die roll consume precisely the same RNG sequence as
## callers which still roll each die themselves.
static func roll_dice(rng_state: int, count: int, sides: int) -> Dictionary:
	assert(count >= 0)
	assert(sides > 0)
	var values: Array[int] = []
	var next_rng_state := rng_state
	var total := 0
	for _roll in range(count):
		var roll := roll_die(next_rng_state, sides)
		var value := int(roll["value"])
		values.append(value)
		total += value
		next_rng_state = int(roll["next_rng_state"])
	return {"values": values, "total": total, "next_rng_state": next_rng_state}
