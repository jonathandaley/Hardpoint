class_name MapScene
extends Node3D
# T210: a map is its own scene: geometry, the 5 beacons (V18), spawn points, minimap
# shape. Arena instantiates MapDef.scene_path as its "Map" child, calls build() after the
# mechs spawn (match-start order as before), and asks the map for the rest. The map's
# static colliders bake into the navmesh through Arena's nav_source group (V55).

var center := Vector2.ZERO   # world XZ: spawns face it, minimap centre
var minimap_half := 100.0    # metres from center to the minimap edge
var spawn_spacing := 8.0     # T358: metres between mechs in a team's spawn line

func build() -> void:
	pass

## World positions of `team`'s spawn points (y = ground_y there).
func spawn_points(_team: int) -> Array:
	return []

## T358: a spot in a team's spawn line, kept somewhere a mech fits (maps with tight spawn rooms
## override it; pure geometry, so every peer places the mech alike).
func clamp_spawn(p: Vector3) -> Vector3:
	return p

## Floor height before the floor colliders exist (the match-start spawn runs first).
func ground_y(_x: float, _z: float) -> float:
	return 0.0

## Map boundary for the minimap, world XZ.
func minimap_outline() -> PackedVector2Array:
	return PackedVector2Array()

## T223: a terrain mesh + trimesh collision over [-half, half]^2 (around `center`) from
## this map's ground_y, every `cell` m; `color_at(x, z, y) -> Color` paints the vertices.
## Godot's front faces wind clockwise seen from above (T211: the other way round and every
## mech fell through).
func make_terrain(half: float, cell: float, color_at: Callable, detail_seed := 0) -> void:
	var n := int(half * 2.0 / cell) + 1
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	for j in n:
		for i in n:
			var x := center.x - half + i * cell
			var z := center.y - half + j * cell
			var y := ground_y(x, z)
			verts.append(Vector3(x, y, z))
			cols.append(color_at.call(x, z, y))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in n - 1:
		for i in n - 1:
			var a := j * n + i
			for k in [a, a + 1, a + n, a + 1, a + n + 1, a + n]:
				st.set_color(cols[k])
				st.add_vertex(verts[k])
	st.generate_normals()
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.95
	var grain := NoiseTexture2D.new()
	var fn := FastNoiseLite.new()
	fn.frequency = 0.08
	fn.seed = detail_seed
	grain.noise = fn
	grain.seamless = true
	mat.detail_enabled = true
	mat.detail_albedo = grain
	mat.detail_blend_mode = BaseMaterial3D.BLEND_MODE_MUL
	mat.uv1_triplanar = true
	mat.uv1_scale = Vector3(0.15, 0.15, 0.15)
	mi.material_override = mat
	add_child(mi)
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	col.shape = mesh.create_trimesh_shape()
	body.add_child(col)
	add_child(body)

## T241 (HUMAN_FOUND_ISSUES 2026-11-04: floors look textured, "the trees and obstacles are
## plain ... add some surface detail, just to break up the silhouette a bit"): after build(),
## every plain opaque material on the map (no texture, no detail yet, not emissive, not
## transparent) gets a soft triplanar noise detail layer -- grey 0.72..1.0 multiplied in, so
## surfaces vary without going darker overall. Shared materials are touched once.
func add_surface_detail() -> void:
	var grain := NoiseTexture2D.new()
	var fn := FastNoiseLite.new()
	fn.frequency = 0.12
	fn.fractal_octaves = 3
	grain.noise = fn
	grain.seamless = true
	grain.width = 128
	grain.height = 128
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.72, 0.72, 0.72))
	ramp.set_color(1, Color(1, 1, 1))
	grain.color_ramp = ramp
	var done := {}
	for mi in find_children("*", "MeshInstance3D", true, false):
		for mm in surface_materials(mi as MeshInstance3D):
			var m := mm as StandardMaterial3D
			if m == null or done.has(m) or not plain_material(m):
				continue
			done[m] = true
			_dress(m, grain)

func _dress(m: StandardMaterial3D, grain: Texture2D) -> void:
	m.detail_enabled = true
	m.detail_albedo = grain
	m.detail_blend_mode = BaseMaterial3D.BLEND_MODE_MUL
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * 0.5

## What each surface of a mesh draws with: override, else surface override, else the mesh's.
static func surface_materials(n: MeshInstance3D) -> Array:
	if n.material_override != null:
		return [n.material_override]
	var out: Array = []
	if n.mesh != null:
		for i in n.mesh.get_surface_count():
			out.append(n.get_surface_override_material(i) if n.get_surface_override_material(i) != null else n.mesh.surface_get_material(i))
	return out

## A flat colour with nothing on it yet, made in code (a material loaded from a file may be
## shared with mechs or the UI; those are left alone).
static func plain_material(m: StandardMaterial3D) -> bool:
	return m.resource_path == "" and m.albedo_texture == null and not m.detail_enabled and not m.emission_enabled \
		and m.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED and not m.vertex_color_use_as_albedo

## T223: invisible boundary walls around a square of side 2*half (+ center).
func make_boundary(half: float, height := 40.0) -> void:
	for side in [[Vector3(0, 0, -half), Vector3(half * 2.0, height, 2)], [Vector3(0, 0, half), Vector3(half * 2.0, height, 2)],
			[Vector3(-half, 0, 0), Vector3(2, height, half * 2.0)], [Vector3(half, 0, 0), Vector3(2, height, half * 2.0)]]:
		var body := StaticBody3D.new()
		var col := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = side[1]
		col.shape = box
		body.add_child(col)
		body.position = side[0] + Vector3(center.x, height * 0.5, center.y)
		add_child(body)

## T223: the arena's environment, made this map's own (a copy) so changes (fog, sky) don't
## leak into the next match on another map.
func own_environment() -> Environment:
	var we := get_parent().get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we == null or we.environment == null:
		return null
	we.environment = we.environment.duplicate()
	return we.environment
