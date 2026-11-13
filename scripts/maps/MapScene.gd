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

## T424 (browser / potato target): every separate mesh is a draw call (~0.02 ms each in a
## browser; Badlands had 611 rocks). After build(), each plain static mesh is folded into one
## mesh per material. Collision stays per obstacle -- only the drawing merges. Left alone: anything
## scripted or under a scripted / moving node (beacons, water, fog), transparent or shader
## materials, flat planes, meshes with children, squashed meshes, textures in object space.
## Not run headless (Arena): probe map_merge calls it directly.
const _MERGE_TYPES := ["BoxMesh", "CylinderMesh", "PrismMesh", "SphereMesh", "CapsuleMesh"]  # not ArrayMesh: terrain + MathTemple's baked walls are one draw already
var merged_count := 0

func merge_static_meshes() -> void:
	var groups := {}  # [material, cast_shadow, layers] -> SurfaceTool
	var inv := global_transform.affine_inverse()
	for node in find_children("*", "MeshInstance3D", true, false):
		var n := node as MeshInstance3D
		if not _mergeable(n):
			continue
		var mats := surface_materials(n)
		var xf := inv * n.global_transform
		for s in n.mesh.get_surface_count():
			var key := [mats[s], n.cast_shadow, n.layers]
			if not groups.has(key):
				groups[key] = SurfaceTool.new()
			(groups[key] as SurfaceTool).append_from(n.mesh, s, xf)
		merged_count += 1
		n.free()
	for key in groups:
		var out := MeshInstance3D.new()
		out.name = "Merged"
		out.mesh = (groups[key] as SurfaceTool).commit()
		out.material_override = key[0]
		out.cast_shadow = key[1]
		out.layers = key[2]
		add_child(out)

func _mergeable(n: MeshInstance3D) -> bool:
	if n.mesh == null or not n.mesh.get_class() in _MERGE_TYPES or n.get_script() != null or not n.visible \
			or n.get_child_count() > 0 or n.material_overlay != null or n.visibility_range_end > 0.0 \
			or n.skeleton != NodePath("..") and n.skeleton != NodePath(""):
		return false
	var sc := n.global_transform.basis.get_scale()
	if absf(sc.x - sc.y) > 0.001 or absf(sc.x - sc.z) > 0.001:
		return false  # merged normals would be wrong under a squash
	for m in surface_materials(n):
		var sm := m as StandardMaterial3D
		if sm == null or sm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED \
				or sm.albedo_texture != null and sm.uv1_triplanar and not sm.uv1_world_triplanar:
			return false  # a texture laid out in the mesh's own space would slide (City's windows)
	var p := n.get_parent()
	while p != self:  # only plain holders and static bodies up to the map
		if p == null or p.get_script() != null or not (p.get_class() in ["Node3D", "StaticBody3D"]) or not (p as Node3D).visible:
			return false
		p = p.get_parent()
	return true

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
## T374 (HUMAN_FOUND 2026-11-09: a bot walked off the back of Redwood Forest): the walls reach
## BOUNDARY_DEPTH m below y 0 -- a rolling floor dips under 0 at the edge, which left a gap.
const BOUNDARY_DEPTH := 30.0

## T405 (HUMAN_FOUND: "Make the edges of the maps disappear into fog, so the hard world border isn't
## as jarring. The physical edges are good where they are now, just visual needs an upgrade."): the
## Compatibility renderer has no volumetric fog, so a square map's edge (make_boundary, or a map that
## sets edge_half) gets FOG_LAYERS see-through curtains in the map's fog colour, thickening toward the
## wall (the last one opaque: the void beyond is gone) and fading out with height. Arena calls it after
## build(), once the map has set its environment's fog.
var edge_half := 0.0
const FOG_LAYERS := [[0.0, 1.0], [5.0, 0.35], [11.0, 0.22], [18.0, 0.12]]  # [metres inside the wall, opacity]
const FOG_FADE := Vector2(6.0, 45.0)  # full up to 6 m, gone by 45 m
const _FOG_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
uniform vec4 tint : source_color;
uniform vec2 fade = vec2(6.0, 45.0);
uniform float soft = 14.0;  // metres over which a curtain fades in behind the ground it cuts (no bands)
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
varying float wy;
void vertex() { wy = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y; }
void fragment() {
	ALBEDO = tint.rgb;
	float d = texture(depth_tex, SCREEN_UV).r;
	vec4 v = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d * 2.0 - 1.0, 1.0);
	float behind = (-v.z / v.w) - (-VERTEX.z);  // scene depth past this curtain
	ALPHA = tint.a * (1.0 - smoothstep(fade.x, fade.y, wy)) * clamp(behind / soft, 0.0, 1.0);
}
"""

func add_fog_edges() -> void:
	if edge_half <= 0.0:
		return
	var we := get_parent().get_node_or_null("WorldEnvironment") as WorldEnvironment
	var env: Environment = we.environment if we != null else null
	var col := Color(0.45, 0.52, 0.70)  # the arena sky's horizon
	if env != null and env.fog_enabled:
		col = env.fog_light_color
	elif env != null and env.sky != null and env.sky.sky_material is ProceduralSkyMaterial:
		col = (env.sky.sky_material as ProceduralSkyMaterial).sky_horizon_color
	var sh := Shader.new()
	sh.code = _FOG_SHADER
	for layer in FOG_LAYERS:
		var d: float = layer[0]
		var mat := ShaderMaterial.new()
		mat.shader = sh
		mat.set_shader_parameter("tint", Color(col.r, col.g, col.b, layer[1]))
		mat.set_shader_parameter("fade", FOG_FADE)
		var span := (edge_half - d) * 2.0
		for side in 4:
			var mi := MeshInstance3D.new()
			mi.name = "FogEdge_%d_%d" % [int(d), side]
			var q := QuadMesh.new()
			q.size = Vector2(span, FOG_FADE.y + 20.0)
			mi.mesh = q
			mi.material_override = mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var a := side * PI * 0.5
			var out := Vector3(sin(a), 0.0, cos(a))
			mi.position = Vector3(center.x, (FOG_FADE.y + 20.0) * 0.5 - 20.0, center.y) + out * (edge_half - d)
			mi.rotation.y = a
			add_child(mi)

func make_boundary(half: float, height := 40.0) -> void:
	edge_half = half  # T405: fog curtains go along these walls
	var tall := height + BOUNDARY_DEPTH
	for side in [[Vector3(0, 0, -half), Vector3(half * 2.0, tall, 2)], [Vector3(0, 0, half), Vector3(half * 2.0, tall, 2)],
			[Vector3(-half, 0, 0), Vector3(2, tall, half * 2.0)], [Vector3(half, 0, 0), Vector3(2, tall, half * 2.0)]]:
		var body := StaticBody3D.new()
		var col := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = side[1]
		col.shape = box
		body.add_child(col)
		body.position = side[0] + Vector3(center.x, (height - BOUNDARY_DEPTH) * 0.5, center.y)
		add_child(body)

## T223: the arena's environment, made this map's own (a copy) so changes (fog, sky) don't
## leak into the next match on another map.
func own_environment() -> Environment:
	var we := get_parent().get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we == null or we.environment == null:
		return null
	we.environment = we.environment.duplicate()
	return we.environment
