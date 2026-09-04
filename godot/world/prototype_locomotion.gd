class_name PrototypeLocomotion
extends RefCounted

## Small engine-independent path follower used by the A1 prototype controller.
## It owns no Node or simulation state: A2 will replace the direct controller
## with Command -> Event playback while retaining the same presentation boundary.

const EPSILON := 0.001

var speed: float = 5.0
var waypoint_tolerance: float = 0.22
var active_target: Vector3 = Vector3.ZERO
var _path := PackedVector3Array()
var _waypoint_index := 0
var _active := false


func begin_path(path: PackedVector3Array, target: Vector3) -> Dictionary:
	stop()
	if path.is_empty():
		return {"accepted": false, "reason": &"empty_path"}
	_path = path.duplicate()
	active_target = target
	_active = true
	return {"accepted": true, "reason": &""}


func stop() -> void:
	_path = PackedVector3Array()
	_waypoint_index = 0
	_active = false


func is_active() -> bool:
	return _active


func get_path() -> PackedVector3Array:
	return _path.duplicate()


func step(current_position: Vector3, delta: float) -> Dictionary:
	if not _active or delta <= 0.0:
		return {"velocity": Vector3.ZERO, "finished": not _active}

	while _waypoint_index < _path.size():
		var waypoint := _path[_waypoint_index]
		waypoint.y = current_position.y
		if current_position.distance_to(waypoint) > waypoint_tolerance:
			break
		_waypoint_index += 1

	if _waypoint_index >= _path.size():
		_active = false
		return {"velocity": Vector3.ZERO, "finished": true}

	var next_waypoint := _path[_waypoint_index]
	next_waypoint.y = current_position.y
	var offset := next_waypoint - current_position
	offset.y = 0.0
	var distance := offset.length()
	if distance <= EPSILON:
		_waypoint_index += 1
		return step(current_position, delta)
	var travel_speed := minf(speed, distance / delta)
	return {"velocity": offset / distance * travel_speed, "finished": false}
