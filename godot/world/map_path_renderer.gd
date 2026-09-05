class_name MapPathRenderer
extends Node3D

## B11 bounded ribbons.  Deliberately simple segment quads keep output stable
## and make their width match the MapSpec validation footprint.

static func create(path_data: Dictionary, terrain: TerrainProvider) -> MapPathRenderer:
	var root := MapPathRenderer.new()
	root.name = String(path_data.id)
	var points: PackedVector2Array = path_data.points
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var width := float(path_data.width)
	var lift := 0.045 if path_data.kind == &"river" else 0.06
	for index in range(1, points.size()):
		var a := points[index - 1]
		var b := points[index]
		var direction := (b - a).normalized()
		if direction.length_squared() == 0.0:
			continue
		var side := Vector2(-direction.y, direction.x) * width
		var quad := [a - side, a + side, b + side, b - side]
		# A triangle list (rather than indexed geometry) is portable to both the
		# renderer and ConcavePolygonShape-style consumers.
		for point in [quad[0], quad[1], quad[2], quad[0], quad[2], quad[3]]:
			vertices.append(Vector3(point.x, terrain.height_at(point.x, point.y) + lift, point.y))
			normals.append(Vector3.UP)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	if not vertices.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("3978a6") if path_data.kind == &"river" else Color("8b6a3e")
		material.roughness = 1.0
		mesh.surface_set_material(0, material)
		var visual := MeshInstance3D.new()
		visual.mesh = mesh
		root.add_child(visual)
	return root
