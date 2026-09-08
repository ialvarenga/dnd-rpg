class_name MapPathRenderer
extends Node3D

## Continuous ribbons. MapSpec control points use the `[x, z]` convention.
const SHORE_WIDTH_M := 0.35
const MAX_MITER_RATIO := 2.5


static func create(path_data: Dictionary, terrain: TerrainProvider) -> MapPathRenderer:
	var root := MapPathRenderer.new()
	root.name = String(path_data.id)
	var points: PackedVector2Array = path_data.points
	var boundaries := ribbon_boundaries(points, float(path_data.width))
	if boundaries.is_empty():
		return root
	if path_data.kind == &"river":
		var water_height := float(path_data.get("water_height", terrain.height_at(points[0].x, points[0].y)))
		root.add_child(_create_ribbon_mesh("Water", boundaries, terrain, _water_material(), water_height, 0.025))
		root.add_child(_create_shores(boundaries, terrain))
		if bool(path_data.get("debug_rivers", false)):
			root.add_child(_create_debug(points, boundaries, water_height))
	else:
		root.add_child(_create_ribbon_mesh("Road", boundaries, terrain, _road_material(), NAN, 0.06))
	return root


## Alternating left/right points. Shared join pairs make a crack-free ribbon.
static func ribbon_boundaries(points: PackedVector2Array, half_width: float) -> PackedVector2Array:
	var boundaries := PackedVector2Array()
	if points.size() < 2 or half_width <= 0.0:
		return boundaries
	for index in range(points.size()):
		var tangent: Vector2
		if index == 0:
			tangent = (points[1] - points[0]).normalized()
		elif index == points.size() - 1:
			tangent = (points[index] - points[index - 1]).normalized()
		else:
			var previous := (points[index] - points[index - 1]).normalized()
			var following := (points[index + 1] - points[index]).normalized()
			var normal_sum := Vector2(-previous.y, previous.x) + Vector2(-following.y, following.x)
			if normal_sum.length_squared() > 0.000001:
				var miter := normal_sum.normalized()
				var scale := minf(half_width / maxf(absf(miter.dot(Vector2(-following.y, following.x))), 0.001), half_width * MAX_MITER_RATIO)
				boundaries.append(points[index] + miter * scale)
				boundaries.append(points[index] - miter * scale)
				continue
			tangent = following
		if tangent.length_squared() <= 0.000001:
			return PackedVector2Array()
		var side := Vector2(-tangent.y, tangent.x) * half_width
		boundaries.append(points[index] + side)
		boundaries.append(points[index] - side)
	return boundaries


static func _create_ribbon_mesh(node_name: String, boundaries: PackedVector2Array, terrain: TerrainProvider, material: Material, fixed_height: float, lift: float) -> MeshInstance3D:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var length_along := 0.0
	for index in range(0, boundaries.size(), 2):
		if index > 0:
			length_along += ((boundaries[index] + boundaries[index + 1]) * 0.5).distance_to((boundaries[index - 2] + boundaries[index - 1]) * 0.5)
		for side in range(2):
			var point := boundaries[index + side]
			var height := fixed_height if is_finite(fixed_height) else _height_at_clamped(terrain, point)
			vertices.append(Vector3(point.x, height + lift, point.y))
			normals.append(Vector3.UP)
			uvs.append(Vector2(length_along * 0.18, float(side)))
	var indices := PackedInt32Array()
	for pair in range(boundaries.size() / 2 - 1):
		var start := pair * 2
		indices.append_array(PackedInt32Array([start, start + 1, start + 3, start, start + 3, start + 2]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	var visual := MeshInstance3D.new()
	visual.name = node_name
	visual.mesh = mesh
	return visual


static func _create_shores(boundaries: PackedVector2Array, terrain: TerrainProvider) -> MeshInstance3D:
	var expanded := PackedVector2Array()
	for index in range(0, boundaries.size(), 2):
		var center := (boundaries[index] + boundaries[index + 1]) * 0.5
		expanded.append(center + (boundaries[index] - center).normalized() * (boundaries[index].distance_to(center) + SHORE_WIDTH_M))
		expanded.append(center + (boundaries[index + 1] - center).normalized() * (boundaries[index + 1].distance_to(center) + SHORE_WIDTH_M))
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	for pair in range(boundaries.size() / 2 - 1):
		for quad in [[boundaries[pair * 2], expanded[pair * 2], expanded[pair * 2 + 2], boundaries[pair * 2 + 2]], [boundaries[pair * 2 + 1], boundaries[pair * 2 + 3], expanded[pair * 2 + 3], expanded[pair * 2 + 1]]]:
			for point in [quad[0], quad[1], quad[2], quad[0], quad[2], quad[3]]:
				vertices.append(Vector3(point.x, _height_at_clamped(terrain, point) + 0.035, point.y))
				normals.append(Vector3.UP)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _shore_material())
	var visual := MeshInstance3D.new()
	visual.name = "Shore"
	visual.mesh = mesh
	return visual


## A path that reaches the map edge extrudes its ribbon and shore slightly past
## it, so the sample -- not the vertex -- is clamped back inside. Height is only
## read to drape the mesh over the terrain; the ribbon keeps its authored shape.
static func _height_at_clamped(terrain: TerrainProvider, point: Vector2) -> float:
	return terrain.height_at(clampf(point.x, 0.0, terrain.bounds.x), clampf(point.y, 0.0, terrain.bounds.y))


static func _water_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = "shader_type spatial; render_mode diffuse_burley, cull_disabled; void fragment() { float ripple = sin((UV.x - TIME * 0.20) * 18.0 + sin(UV.y * 8.0)) * 0.08; ALBEDO = mix(vec3(0.035, 0.28, 0.34), vec3(0.08, 0.52, 0.58), UV.y * 0.55 + 0.25 + ripple); ROUGHNESS = 0.48; METALLIC = 0.03; }"
	var material := ShaderMaterial.new()
	material.shader = shader
	return material


static func _shore_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("6f8150")
	material.roughness = 0.9
	return material


static func _road_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("8b6a3e")
	material.roughness = 1.0
	return material


static func _create_debug(points: PackedVector2Array, boundaries: PackedVector2Array, height: float) -> Node3D:
	var debug := Node3D.new()
	debug.name = "RiverDebug"
	var lines := ImmediateMesh.new()
	lines.surface_begin(Mesh.PRIMITIVE_LINES)
	for index in range(1, points.size()):
		for segment in [[points[index - 1], points[index]], [boundaries[(index - 1) * 2], boundaries[index * 2]], [boundaries[(index - 1) * 2 + 1], boundaries[index * 2 + 1]]]:
			lines.surface_add_vertex(Vector3(segment[0].x, height + 0.12, segment[0].y))
			lines.surface_add_vertex(Vector3(segment[1].x, height + 0.12, segment[1].y))
	lines.surface_end()
	var debug_material := StandardMaterial3D.new()
	debug_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	debug_material.albedo_color = Color("f5d742")
	debug_material.emission_enabled = true
	debug_material.emission = Color("f5d742")
	lines.surface_set_material(0, debug_material)
	var visual := MeshInstance3D.new()
	visual.mesh = lines
	debug.add_child(visual)
	for point in points:
		var marker := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.14
		sphere.height = 0.28
		marker.mesh = sphere
		marker.position = Vector3(point.x, height + 0.14, point.y)
		debug.add_child(marker)
	return debug
