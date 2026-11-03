extends MapScene
# T211: Badlands. 320 m square (Math Temple's bowl is ~190 m across): rolling hills, two
# winding canyons (trenches you enter at their shallow ends -- covered routes past the
# centre), decrepit ruins (broken walls of uneven height, collapsed roof slabs, rubble)
# instead of Math Temple's precision. Point-symmetric for fairness: 5 beacons (V18),
# 3 spawn points per team at the north / south ends. Terrain = an analytic height
# function (ground_y), meshed on a 2 m grid with trimesh collision -> the navmesh bakes
# from it (Arena's nav_source group, V55). Everything seeded: same map on every peer.

const HALF := 160.0     # half the side, metres
const CELL := 2.0       # terrain grid
const EDGE := 22.0      # berm width at the boundary
const BEACONS := [Vector2(0, 0), Vector2(-85, 45), Vector2(85, -45), Vector2(85, 60), Vector2(-85, -60)]
const SPAWNS := [[Vector2(-60, 132), Vector2(0, 138), Vector2(60, 132)],
	[Vector2(60, -132), Vector2(0, -138), Vector2(-60, -132)]]
const CANYONS := [  # polylines; depth tapers to 0 at both ends (the way in)
	[Vector2(-140, 22), Vector2(-92, 8), Vector2(-45, -12), Vector2(-12, -38)],
	[Vector2(140, -22), Vector2(92, -8), Vector2(45, 12), Vector2(12, 38)],
]
const CANYON_W := 15.0
const CANYON_D := 9.0
const SAND := Color("#b08a5a")
const ROCK := Color("#7d6a55")
const DUST := Color("#5e4a38")
const CONCRETE := Color("#7a7064")
const RUST := Color("#6b3a22")

func _init() -> void:
	center = Vector2.ZERO
	minimap_half = HALF + 6.0

func spawn_points(team: int) -> Array:
	var out: Array = []
	for p in SPAWNS[team]:
		out.append(Vector3(p.x, ground_y(p.x, p.y), p.y))
	return out

func minimap_outline() -> PackedVector2Array:
	return PackedVector2Array([Vector2(-HALF, -HALF), Vector2(HALF, -HALF), Vector2(HALF, HALF), Vector2(-HALF, HALF)])

# ---- terrain ----

func _hills(x: float, z: float) -> float:
	return 6.0 * sin(x * 0.021 + 0.7) * cos(z * 0.017 - 0.3) + 3.0 * sin(x * 0.047 + z * 0.031) \
		+ 1.5 * sin(x * 0.11 - z * 0.083)

func _canyon_cut(x: float, z: float) -> float:
	var cut := 0.0
	var p := Vector2(x, z)
	for line in CANYONS:
		var total := 0.0
		for k in line.size() - 1:
			total += (line[k] as Vector2).distance_to(line[k + 1])
		var along := 0.0
		for k in line.size() - 1:
			var a: Vector2 = line[k]
			var b: Vector2 = line[k + 1]
			var seg := b - a
			var t := clampf((p - a).dot(seg) / seg.length_squared(), 0.0, 1.0)
			var d := p.distance_to(a + seg * t)
			var u := (along + seg.length() * t) / total            # 0..1 along the canyon
			var taper := smoothstep(0.0, 0.18, u) * smoothstep(1.0, 0.82, u)
			cut = maxf(cut, CANYON_D * taper * smoothstep(CANYON_W, CANYON_W * 0.45, d))
			along += seg.length()
	return cut

func _raw(x: float, z: float) -> float:
	var h := _hills(x, z) - _canyon_cut(x, z)
	var edge := maxf(absf(x), absf(z)) - (HALF - EDGE)  # berm rising to the boundary
	if edge > 0.0:
		h += 18.0 * smoothstep(0.0, EDGE, edge)
	return h

## Floor height: the terrain with beacon pads and spawn areas flattened.
func ground_y(x: float, z: float) -> float:
	var h := _raw(x, z)
	var p := Vector2(x, z)
	for b in BEACONS:
		h = lerpf(h, _raw(b.x, b.y), smoothstep(14.0, 7.0, p.distance_to(b)))
	for team in SPAWNS:
		for s in team:
			h = lerpf(h, _hills(s.x, s.y), smoothstep(28.0, 20.0, p.distance_to(s)))
	return h

func build() -> void:
	_terrain()
	_boundary()
	var rng := RandomNumberGenerator.new()
	rng.seed = 211
	# ruins: a few near each flank beacon and along the routes, none on a beacon pad / spawn
	# point-symmetric pairs (fair cover); a ruined-town cluster on each flank
	var half_spots := [Vector2(-30, 30), Vector2(-110, 70), Vector2(60, 95), Vector2(-40, -70),
		Vector2(-115, -20), Vector2(20, 105), Vector2(-62, 20), Vector2(-100, 38), Vector2(-70, 68),
		Vector2(-120, 100), Vector2(10, 62), Vector2(40, 28)]
	var spots: Array = []
	for v in half_spots:
		spots.append(v)
		spots.append(-v)
	for s in spots:
		_ruin(s, rng)

func _terrain() -> void:
	var n := int(HALF * 2.0 / CELL) + 1
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	for j in n:
		for i in n:
			var x := -HALF + i * CELL
			var z := -HALF + j * CELL
			var y := ground_y(x, z)
			verts.append(Vector3(x, y, z))
			var c := SAND.lerp(ROCK, clampf((y - 2.0) / 10.0, 0.0, 1.0))
			c = c.lerp(DUST, clampf(_canyon_cut(x, z) / CANYON_D, 0.0, 1.0))
			c = c.darkened(0.08 * sin(x * 0.37) * cos(z * 0.29) + 0.04)  # mottling
			cols.append(c)
	for j in n - 1:
		for i in n - 1:
			var a := j * n + i
			for k in [a, a + 1, a + n, a + 1, a + n + 1, a + n]:  # clockwise from above = front (Godot)
				st.set_color(cols[k])
				st.add_vertex(verts[k])
	st.generate_normals()
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.95
	var grain := NoiseTexture2D.new()  # sand / grit detail
	var fn := FastNoiseLite.new()
	fn.frequency = 0.08
	fn.seed = 211
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

func _boundary() -> void:  # invisible walls on top of the berm
	for side in [[Vector3(0, 20, -HALF), Vector3(HALF * 2.0, 40, 2)], [Vector3(0, 20, HALF), Vector3(HALF * 2.0, 40, 2)],
			[Vector3(-HALF, 20, 0), Vector3(2, 40, HALF * 2.0)], [Vector3(HALF, 20, 0), Vector3(2, 40, HALF * 2.0)]]:
		var body := StaticBody3D.new()
		var col := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = side[1]
		col.shape = box
		body.add_child(col)
		body.position = side[0]
		add_child(body)

# ---- ruins ----

func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	return m

func _block(size: Vector3, pos: Vector3, rot_y: float, mat: Material, tilt := Vector3.ZERO) -> void:
	var body := StaticBody3D.new()
	body.add_to_group(&"ruins")
	body.position = pos
	body.rotation = Vector3(tilt.x, rot_y, tilt.z)
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	col.shape = box
	body.add_child(col)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	body.add_child(mi)
	add_child(body)

func _ruin(at: Vector2, rng: RandomNumberGenerator) -> void:
	var w := rng.randf_range(12.0, 22.0)
	var d := rng.randf_range(10.0, 18.0)
	var rot := rng.randf_range(0.0, PI)
	var base := ground_y(at.x, at.y)
	var basis := Basis(Vector3.UP, rot)
	var wall_mat := _mat(CONCRETE.darkened(rng.randf_range(0.0, 0.25)))
	var rust_mat := _mat(RUST.darkened(rng.randf_range(0.0, 0.2)))
	var full_h := rng.randf_range(6.0, 11.0)
	# 4 walls, each in 4 segments of uneven height; some segments gone (breaches, doors)
	for side in 4:
		var length: float = w if side % 2 == 0 else d
		var off: Vector3 = basis * (Vector3(0, 0, d * 0.5) if side == 0 else Vector3(0, 0, -d * 0.5) if side == 2
			else Vector3(w * 0.5, 0, 0) if side == 1 else Vector3(-w * 0.5, 0, 0))
		var along: Vector3 = basis * (Vector3.RIGHT if side % 2 == 0 else Vector3.BACK)
		var segs := 5
		for k in segs:
			if rng.randf() < 0.28:
				continue  # breach
			var h := full_h * rng.randf_range(0.25, 1.0)
			var seg_len := length / segs - 0.15
			var c := Vector3(at.x, 0, at.y) + off + along * ((float(k) + 0.5) / segs - 0.5) * length
			_block(Vector3(seg_len, h, 0.7) if side % 2 == 0 else Vector3(0.7, h, seg_len),
				Vector3(c.x, ground_y(c.x, c.z) + h * 0.5 - 0.3, c.z), rot, wall_mat)
	if rng.randf() < 0.6:  # collapsed roof: a slab resting on one wall, tilted to the ground
		var tilt := deg_to_rad(rng.randf_range(14.0, 26.0))
		_block(Vector3(w * 0.8, 0.45, d * 0.6), Vector3(at.x, base + full_h * 0.45, at.y), rot,
			rust_mat, Vector3(tilt, 0, 0))
	for k in rng.randi_range(4, 8):  # rubble
		var r := Vector2(rng.randf_range(-w, w), rng.randf_range(-d, d)) * 0.7
		var s := Vector3(rng.randf_range(0.6, 2.0), rng.randf_range(0.4, 1.2), rng.randf_range(0.6, 2.0))
		var p := at + r
		_block(s, Vector3(p.x, ground_y(p.x, p.y) + s.y * 0.35, p.y), rng.randf() * PI,
			wall_mat if k % 3 else rust_mat, Vector3(rng.randf_range(-0.3, 0.3), 0, rng.randf_range(-0.3, 0.3)))
