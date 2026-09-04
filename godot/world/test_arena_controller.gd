class_name TestArenaController
extends Node3D

## World-side composition root for A3. Hover resolves a non-mutating preview;
## confirmed input creates Commands, applies accepted events immediately, and
## EventPlayer alone narrates movement on the CharacterView.

@onready var camera: Camera3D = $CameraRig/Pivot/Camera3D
@onready var character: CharacterView = $PlayerCharacter
@onready var navigation_region: NavigationRegion3D = $NavigationRegion3D
@onready var event_player: EventPlayer = $EventPlayer
@onready var destination_marker: MeshInstance3D = $Debug/DestinationMarker
@onready var path_mesh: MeshInstance3D = $Debug/PathLine
@onready var debug_label: Label = $DebugOverlay/Panel/Label

var battle_state := BattleState.new()
var nav_provider: NavProvider
var los_provider: LosProvider
var last_command: Command
var last_resolution: ResolutionResult
var last_preview: ResolutionResult
var last_input_status: StringName = &"idle"

var _preview_path := PackedVector3Array()
var _preview_cost := 0.0
var _preview_remaining := 0.0
var _preview_ignores_budget := false

var _line_mesh := ImmediateMesh.new()


func _ready() -> void:
	path_mesh.mesh = _line_mesh
	destination_marker.visible = false
	nav_provider = GodotNavProvider.new(navigation_region)
	los_provider = GodotLosProvider.new(get_world_3d(), 8)
	_initialize_exploration_state()
	event_player.register_character_view(character)
	event_player.movement_completed.connect(_synchronize_completed_movement)


func _process(_delta: float) -> void:
	_update_debug_view()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var preview_target: Variant = _terrain_position_from_screen(event.position)
		if preview_target is Vector3:
			preview_move_target(preview_target)
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		handle_terrain_click(_terrain_position_from_screen(event.position))
		get_viewport().set_input_as_handled()


## Kept public so headless scene tests can exercise the same input boundary as
## a terrain click without requiring a visible window.
func handle_terrain_click(destination: Variant) -> void:
	if destination == null:
		last_input_status = &"outside_terrain"
		return
	if not (destination is Vector3) or not _is_finite_vector(destination):
		last_input_status = &"invalid_target"
		return
	# The click confirms a fresh authoritative resolution; it never applies the
	# hover result, which remains presentation-only.
	preview_move_target(destination)
	submit_move_target(destination)


## Public for runtime tests and future UI. It intentionally calls only the pure
## resolver and updates local debug state; BattleState and CharacterView remain
## untouched until submit_move_target confirms a command.
func preview_move_target(target: Vector3) -> ResolutionResult:
	var preview_command := Command.create(&"move", character.actor_id)
	preview_command.target_pos = target
	last_preview = Resolver.resolve(battle_state, preview_command, nav_provider, los_provider)
	_preview_path = PackedVector3Array()
	_preview_cost = 0.0
	_preview_remaining = 0.0
	_preview_ignores_budget = battle_state.phase != &"combat"
	var previewed_movement := false
	for event in last_preview.events:
		if event.type == &"movement_segment":
			previewed_movement = true
			_preview_path = (event.data["path"] as PackedVector3Array).duplicate()
			_preview_cost = float(event.data["path_cost"])
			var actor: ActorState = battle_state.actors[character.actor_id]
			_preview_remaining = maxf(0.0, actor.movement_remaining - _preview_cost)
			destination_marker.global_position = (event.data["to"] as Vector3) + Vector3.UP * 0.08
			destination_marker.visible = true
		elif event.type == &"command_rejected":
			last_input_status = event.data["reason"]
	if previewed_movement:
		last_input_status = &"preview"
	return last_preview


func submit_move_target(target: Vector3) -> ResolutionResult:
	var command := Command.create(&"move", character.actor_id)
	command.target_pos = target
	last_command = command
	last_resolution = Resolver.resolve(battle_state, command, nav_provider, los_provider)
	_apply_resolution(last_resolution)
	_prepare_presentation_paths(last_resolution)
	var accepted_movement := false
	for event in last_resolution.events:
		if event.type == &"movement_segment":
			accepted_movement = true
			var resolved_target: Vector3 = event.data["to"]
			destination_marker.global_position = resolved_target + Vector3.UP * 0.08
			destination_marker.visible = true
		elif event.type == &"command_rejected":
			last_input_status = event.data["reason"]
	if accepted_movement:
		last_input_status = &"accepted"
		_clear_preview()
	event_player.play_events(last_resolution.events)
	return last_resolution


func _initialize_exploration_state() -> void:
	battle_state.phase = &"exploration"
	battle_state.rng_seed = 1
	battle_state.rng_state = 1
	var player := ActorState.new()
	player.id = character.actor_id
	player.side = &"heroes"
	player.position = character.global_position
	player.hp = 20
	player.max_hp = 20
	battle_state.actors[player.id] = player


func _apply_resolution(resolution: ResolutionResult) -> void:
	for event in resolution.events:
		Resolver.apply(battle_state, event)
	battle_state.rng_state = resolution.next_rng_state


func _prepare_presentation_paths(resolution: ResolutionResult) -> void:
	for event in resolution.events:
		if event.type != &"movement_segment":
			continue
		var authoritative_target: Vector3 = event.data["to"]
		var presentation_path := nav_provider.find_path(character.global_position, authoritative_target)
		if not presentation_path.is_empty():
			# A replacement command resolves from BattleState's already-applied
			# endpoint. Playback instead begins from the visible character's current
			# location, so it stops the old route without affecting simulation state.
			event.data["presentation_path"] = presentation_path


func _synchronize_completed_movement(actor_id: int) -> void:
	if not battle_state.actors.has(actor_id):
		return
	var view := event_player.get_character_view(actor_id)
	if view == null:
		return
	# BattleState changes on acceptance for deterministic command handling while
	# the view interpolates the event path. Completion snaps only tiny collision
	# or tolerance drift back to that already-authoritative position.
	view.synchronize_to_authoritative_position((battle_state.actors[actor_id] as ActorState).position)


func _terrain_position_from_screen(screen_position: Vector2) -> Variant:
	var ray_origin := camera.project_ray_origin(screen_position)
	var ray_end := ray_origin + camera.project_ray_normal(screen_position) * 500.0
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end, 1)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null
	return hit["position"]


func _update_debug_view() -> void:
	var path := _preview_path
	if path.is_empty():
		path = event_player.get_resolved_path(character.actor_id)
	_line_mesh.clear_surfaces()
	if path.size() >= 2:
		_line_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
		for point in path:
			_line_mesh.surface_add_vertex(point + Vector3.UP * 0.12)
		_line_mesh.surface_end()
	var preview_text := "Preview: --"
	if not _preview_path.is_empty():
		if _preview_ignores_budget:
			preview_text = "Preview: %.2fm (exploration: budget ignored)" % _preview_cost
		else:
			preview_text = "Preview: %.2fm consumed, %.2fm remaining" % [_preview_cost, _preview_remaining]
	debug_label.text = "Command: %s\nDestination: %s (%s)\nVelocity: %s\n%s" % [
		last_input_status,
		_format_vector(character.destination),
		character.destination_state,
		_format_vector(character.get_debug_velocity()),
		preview_text,
	]


func _clear_preview() -> void:
	_preview_path = PackedVector3Array()
	_preview_cost = 0.0
	_preview_remaining = 0.0
	_preview_ignores_budget = false


func _format_vector(value: Vector3) -> String:
	return "(%.1f, %.1f, %.1f)" % [value.x, value.y, value.z]


func _is_finite_vector(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)
