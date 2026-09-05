class_name CompiledTerrain
extends StaticBody3D

## Presentation and physics adapter for TerrainProvider.  Both the mesh and
## collision are made from the provider's exact exported triangles, so raycasts
## and character grounding cannot silently disagree with terrain queries.

const SURFACE_COLORS := {
	&"grass": [Color("5a843e"), Color("426a35"), Color("78a34b")],
	&"sand": [Color("d9bc78"), Color("c99e5d"), Color("ecd38e")],
	&"dirt": [Color("8b6240"), Color("6d482f"), Color("a5784f")],
	&"stone": [Color("7b7e78"), Color("5f625f"), Color("999b91")],
}


static func create(terrain: TerrainProvider, surface: StringName = &"grass") -> CompiledTerrain:
	var root := CompiledTerrain.new()
	root.name = "Terrain"
	root.collision_layer = 1
	root.collision_mask = 0
	var triangles := terrain.export_navigation_geometry()
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	for triangle in triangles:
		if triangle.size() != 3:
			continue
		var normal := (triangle[1] - triangle[0]).cross(triangle[2] - triangle[0]).normalized()
		if normal.y < 0.0:
			normal = -normal
		for vertex in triangle:
			vertices.append(vertex)
			normals.append(normal)
			# World-space UVs keep the pattern aligned across terrain triangles.
			uvs.append(Vector2(vertex.x, vertex.z) * 0.5)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := _surface_material(surface)
	mesh.surface_set_material(0, material)
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	root.add_child(visual)
	var collision := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(vertices)
	collision.shape = shape
	root.add_child(collision)
	return root


static func _surface_material(surface: StringName) -> ShaderMaterial:
	var palette: Array = SURFACE_COLORS.get(surface, SURFACE_COLORS[&"grass"])
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode diffuse_burley;

uniform vec4 base_color : source_color;
uniform vec4 variation_color : source_color;
uniform vec4 highlight_color : source_color;

float hash(vec2 value) {
	return fract(sin(dot(value, vec2(127.1, 311.7))) * 43758.5453123);
}

void fragment() {
	vec2 cell = floor(UV);
	float grain = hash(cell);
	vec3 color = mix(variation_color.rgb, base_color.rgb, smoothstep(0.15, 0.85, grain));
	color = mix(color, highlight_color.rgb, smoothstep(0.90, 1.0, grain) * 0.35);
	ALBEDO = color;
	ROUGHNESS = 0.92;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter(&"base_color", palette[0])
	material.set_shader_parameter(&"variation_color", palette[1])
	material.set_shader_parameter(&"highlight_color", palette[2])
	return material
