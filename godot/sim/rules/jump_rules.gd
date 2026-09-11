class_name JumpRules
extends RefCounted

## SRD 5.2.1 Long Jump, High Jump, and Falling, in the project's metric scale
## (1 ft = 0.3 m, so the SRD's 10-ft run-up and fall interval are both 3 m).
## Every value derives from the Strength score alone, so the same numbers drive
## ledge routing (ADR-009), the resolver, the path preview, and the sheet.
##
## Deliberately dropping off a ledge is a project rule the SRD does not cover:
## the jumper absorbs their running High Jump height, and only what remains is
## treated as a fall. A Shove fall is involuntary and absorbs nothing.

const METERS_PER_FOOT := 0.3
## SRD: a full-distance jump needs 10 ft of movement on foot immediately before.
const RUN_UP_M := 3.0
## SRD Falling: 1d6 per 10 ft fallen, to a maximum of 20d6.
const FALL_DIE_INTERVAL_M := 3.0
const FALL_DIE_SIDES := 6
const MAX_FALL_DICE := 20
## Below this rise or drop a ledge is a step, walked rather than jumped.
const STEP_HEIGHT_M := 0.6
## Scores beyond 30 do not exist; routing layers are allocated per score.
const MAX_STRENGTH := 30
## Project rule kept from ADR-008: a push only counts as a fall from 2.5 m.
const FORCED_FALL_MIN_M := 2.5

const DROP := &"drop"
const CLIMB := &"climb"
## A Jump-action leap that neither rises nor falls more than a step.
const LEAP := &"leap"
## A Jump action shorter than this on level ground is not worth a jump.
const MIN_LEAP_M := 0.5

## RejectionReason ids for an out-of-reach Jump action (kept here, and mirrored
## in sim/rules/rejection_reason.gd, so this module has no dependencies).
const JUMP_TOO_FAR := &"jump_too_far"
const JUMP_TOO_HIGH := &"jump_too_high"

## Absorbs float drift such as 5 * 0.3 != 1.5, so SRD boundaries stay exact.
const EPSILON := 0.0001


static func strength_modifier(strength: int) -> int:
	return floori(float(strength - 10) / 2.0)


## SRD Long Jump: up to the Strength score in feet, half from a standstill.
static func long_jump_m(strength: int, running: bool = true) -> float:
	return float(maxi(0, strength)) * METERS_PER_FOOT * (1.0 if running else 0.5)


## SRD High Jump: 3 + Strength modifier feet (minimum 0), half from a standstill.
static func high_jump_m(strength: int, running: bool = true) -> float:
	return float(maxi(0, 3 + strength_modifier(strength))) * METERS_PER_FOOT * (1.0 if running else 0.5)


## Drops strictly shorter than this land on the feet: no damage, no Prone.
static func safe_drop_m(strength: int) -> float:
	return FALL_DIE_INTERVAL_M + high_jump_m(strength, true)


## Outcome of deliberately dropping `drop_m`: {effective_m, dice, prone}.
static func drop_outcome(strength: int, drop_m: float) -> Dictionary:
	return _fall(maxf(0.0, drop_m - high_jump_m(strength, true)))


## Outcome of being pushed off a `drop_m` ledge: {effective_m, dice, prone}.
## SRD Falling leaves the creature Prone whenever the fall damaged it.
static func forced_fall_outcome(drop_m: float) -> Dictionary:
	if drop_m + EPSILON < FORCED_FALL_MIN_M:
		return {"effective_m": drop_m, "dice": 0, "prone": false}
	var dice := clampi(floori(drop_m / FALL_DIE_INTERVAL_M + EPSILON), 1, MAX_FALL_DICE)
	return {"effective_m": drop_m, "dice": dice, "prone": true}


## Lowest Strength that can climb onto a ledge `rise_m` high, or -1 if none.
static func min_strength_for_climb(rise_m: float, running: bool) -> int:
	for strength in range(1, MAX_STRENGTH + 1):
		if high_jump_m(strength, running) + EPSILON >= rise_m:
			return strength
	return -1


## Lowest Strength that drops `drop_m` without damage, or -1 if none.
static func min_strength_for_safe_drop(drop_m: float) -> int:
	for strength in range(1, MAX_STRENGTH + 1):
		if int(drop_outcome(strength, drop_m)["dice"]) == 0:
			return strength
	return -1


## SRD: each foot of a jump costs a foot of movement. A drop pays only its
## horizontal distance -- falling is free -- while a climb also pays the rise.
static func jump_cost(kind: StringName, from: Vector3, to: Vector3) -> float:
	var planar := Vector2(from.x, from.z).distance_to(Vector2(to.x, to.z))
	if kind == CLIMB:
		return planar + maxf(0.0, to.y - from.y)
	return planar


## The Jump action (ADR-009): one straight leap from `from` to `to`, both at
## the jumper's height above the ground. `running` means the jumper moved at
## least RUN_UP_M on foot immediately before (ActorState.run_up_m). Returns
## {ok, reason, kind, distance, rise, running, max_distance, max_rise, cost,
## landing: drop_outcome-shaped}. `reason` is a RejectionReason id or &"".
static func leap_check(strength: int, running: bool, from: Vector3, to: Vector3) -> Dictionary:
	var distance := Vector2(from.x, from.z).distance_to(Vector2(to.x, to.z))
	var rise := to.y - from.y
	var kind := LEAP
	if rise > STEP_HEIGHT_M:
		kind = CLIMB
	elif -rise > STEP_HEIGHT_M:
		kind = DROP
	var max_distance := long_jump_m(strength, running)
	var max_rise := high_jump_m(strength, running)
	var reason: StringName = &""
	if distance > max_distance + EPSILON:
		reason = JUMP_TOO_FAR
	elif kind == CLIMB and rise > max_rise + EPSILON:
		reason = JUMP_TOO_HIGH
	elif kind == LEAP and distance < MIN_LEAP_M:
		reason = &"no_movement"
	return {
		"ok": reason == &"", "reason": reason, "kind": kind,
		"distance": distance, "rise": rise, "running": running,
		"max_distance": max_distance, "max_rise": max_rise,
		"cost": jump_cost(kind, from, to),
		"landing": drop_outcome(strength, -rise) if kind == DROP else {"effective_m": 0.0, "dice": 0, "prone": false},
	}


## Short sheet/preview label such as "1d6", or "" when the landing is safe.
static func dice_label(dice: int) -> String:
	return "" if dice <= 0 else "%dd%d" % [dice, FALL_DIE_SIDES]


static func _fall(effective_m: float) -> Dictionary:
	var dice := mini(MAX_FALL_DICE, floori(effective_m / FALL_DIE_INTERVAL_M + EPSILON))
	return {"effective_m": effective_m, "dice": dice, "prone": dice > 0}
