class_name ArrowProjectile
extends Node3D

## Presentation-only arrow for a ranged attack the simulation already settled.
## It is a bare mesh tweened along an arc: no physics body, no collision layer,
## and it never decides whether anything was hit -- EventPlayer tells it where
## to land and narrates the outcome once it arrives.

signal arrived

const SPEED_METERS_PER_SECOND := 30.0
const MIN_FLIGHT_SECONDS := 0.15
const MAX_FLIGHT_SECONDS := 0.6
## The arc's apex rises with distance so long shots read as lobbed.
const ARC_HEIGHT_PER_METER := 0.08
const MIN_ARC_HEIGHT := 0.3
const MAX_ARC_HEIGHT := 2.0
## A miss stays stuck where it fell this long before it is removed.
const STUCK_SECONDS := 1.5

var has_arrived := false
var _from := Vector3.ZERO
var _control := Vector3.ZERO
var _to := Vector3.ZERO
var _sticks := false
var _tween: Tween


## Must be called once this node is inside the tree. `sticks` leaves the arrow
## where it lands for a moment (a miss in the ground); otherwise it is freed on
## arrival (a hit).
func launch(model: PackedScene, from: Vector3, to: Vector3, sticks: bool) -> void:
	if model != null:
		add_child(model.instantiate())
	_from = from
	_to = to
	_sticks = sticks
	var distance := from.distance_to(to)
	_control = (from + to) * 0.5 + Vector3.UP * clampf(distance * ARC_HEIGHT_PER_METER, MIN_ARC_HEIGHT, MAX_ARC_HEIGHT)
	_fly(0.0)
	_tween = create_tween()
	_tween.tween_method(_fly, 0.0, 1.0, flight_seconds(distance))
	_tween.finished.connect(_on_arrived)


static func flight_seconds(distance: float) -> float:
	return clampf(distance / SPEED_METERS_PER_SECOND, MIN_FLIGHT_SECONDS, MAX_FLIGHT_SECONDS)


## Quadratic Bezier from the bow to the landing point, nose along the tangent.
func _fly(t: float) -> void:
	var inverse := 1.0 - t
	global_position = inverse * inverse * _from + 2.0 * inverse * t * _control + t * t * _to
	var tangent := 2.0 * inverse * (_control - _from) + 2.0 * t * (_to - _control)
	if tangent.length_squared() < 0.0001:
		return
	var up := Vector3.UP if absf(tangent.normalized().dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
	# KayKit's arrow_bow points its tip down +Z, the model front.
	look_at(global_position + tangent, up, true)


func _on_arrived() -> void:
	if has_arrived:
		return
	has_arrived = true
	arrived.emit()
	if _sticks and is_inside_tree():
		get_tree().create_timer(STUCK_SECONDS).timeout.connect(queue_free)
	else:
		queue_free()
