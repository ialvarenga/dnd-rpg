class_name CompiledTerrain
extends StaticBody3D

## Presentation and physics adapter for TerrainProvider.  Both the mesh and
## collision are made from the provider's exact exported triangles, so raycasts
## and character grounding cannot silently disagree with terrain queries.

static func create(terrain: TerrainProvider) -> CompiledTerrain:
	var root := CompiledTerrain.new()
	root.name = "Terrain"
	root.collision_layer = 1
	root.collision_mask = 0
	var triangles := terrain.export_navigation_geometry()
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	for triangle in triangles:
		if triangle.size() != 3:
			continue
		var normal := (triangle[1] - triangle[0]).cross(triangle[2] - triangle[0]).normalized()
		if normal.y < 0.0:
			normal = -normal
		for vertex in triangle:
			vertices.append(vertex)
			normals.append(normal)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("48683c")
	material.roughness = 1.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
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
