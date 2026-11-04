extends MapScene
# T224: Giza. ~340 m desert plateau: three pyramids and a sphinx-like monument down the
# middle line, column-hall temples (some roof slabs down) beside the pyramids, flush stone
# causeways, low dunes, warm haze. Mirror-symmetric across x = 0 (the monuments sit on the
# line): team 0 west, team 1 east; 5 beacons (V18), 3 spawns each. Pyramid faces are
# 60.5 deg -- steeper than the navmesh's 60 deg walkable slope (V55: bots never path up a
# face a mech can't climb, floor max 45). Colliders: convex pyramids, boxes (V59).

const HALF := 170.0
const FACE := deg_to_rad(60.5)
const BEACONS := [Vector2(0, 0), Vector2(-90, -60), Vector2(90, -60), Vector2(-90, 80), Vector2(90, 80)]
const SPAWNS := [[Vector2(-150, -50), Vector2(-155, 0), Vector2(-150, 50)],
	[Vector2(150, -50), Vector2(155, 0), Vector2(150, 50)]]
const PYRAMIDS := [[Vector2(0, -100), 70.0], [Vector2(0, 100), 60.0], [Vector2(0, 40), 28.0]]  # centre, base side
const SPHINX := Vector2(0, -42)
const SAND := Color("#c9a66b")
const STONE := Color("#cdb88f")

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

func _dunes(x: float, z: float) -> float:
	return 2.2 * sin(x * 0.031 + 1.1) * cos(z * 0.027) + 1.0 * sin(x * 0.08 - z * 0.05)

func ground_y(x: float, z: float) -> float:
	var h := _dunes(absf(x), z)  # mirrored across x = 0
	var p := Vector2(x, z)
	for b in BEACONS:
		h = lerpf(h, 0.0, smoothstep(16.0, 8.0, p.distance_to(b)))
	for team in SPAWNS:
		for s in team:
			h = lerpf(h, 0.0, smoothstep(28.0, 20.0, p.distance_to(s)))
	for py in PYRAMIDS:  # pyramids and the sphinx sit on level ground
		var d := maxf(absf(x - py[0].x), absf(z - py[0].y)) - float(py[1]) * 0.5
		h = lerpf(h, 0.0, smoothstep(14.0, 2.0, d))
	h = lerpf(h, 0.0, smoothstep(30.0, 18.0, p.distance_to(SPHINX)))
	if absf(x) < 6.0:  # causeway line down the middle: flat
		h = lerpf(h, 0.0, smoothstep(6.0, 3.0, absf(x)))
	return h

func _mat(c: Color, rough := 0.95) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m

func _box(size: Vector3, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	body.rotation = rot
	var col := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	col.shape = bs
	body.add_child(col)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	body.add_child(mi)
	add_child(body)

func build() -> void:
	make_terrain(HALF, 2.0, func(x: float, z: float, y: float) -> Color:
		return SAND.lerp(Color("#b48d55"), clampf(0.5 + 0.5 * sin(x * 0.13) * sin(z * 0.11), 0.0, 1.0) * 0.5).lightened(clampf(y * 0.03, -0.08, 0.08)), 224)
	make_boundary(HALF)
	var env := own_environment()
	if env != null:
		env.fog_enabled = true
		env.fog_light_color = Color("#d9c29a")
		env.fog_density = 0.0025
		env.ambient_light_color = Color("#f0d9b0")
		env.ambient_light_energy = 0.75
	var stone := _mat(STONE)
	stone.detail_enabled = true
	var grain := NoiseTexture2D.new()
	var fn := FastNoiseLite.new()
	fn.frequency = 0.15
	fn.seed = 224
	grain.noise = fn
	grain.seamless = true
	stone.detail_albedo = grain
	stone.detail_blend_mode = BaseMaterial3D.BLEND_MODE_MUL
	stone.uv1_triplanar = true
	stone.uv1_scale = Vector3(0.1, 0.1, 0.1)
	for py in PYRAMIDS:
		_pyramid(py[0], py[1], stone)
	_sphinx(SPHINX, stone)
	# causeway: flush stone slabs down the middle (0.25 m: steppable)
	var slab := _mat(Color("#bfae88"))
	for z in range(-150, 151, 12):
		var zz := float(z)
		if _inside_monument(Vector2(0, zz), 3.0):
			continue
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(8, 0.25, 11.5)
		mi.mesh = bm
		mi.material_override = slab
		add_child(mi)
		mi.position = Vector3(0, 0.05, zz)
	# temples: column halls beside the pyramids (mirrored pairs)
	var rng := RandomNumberGenerator.new()
	rng.seed = 224
	for at in [Vector2(52, -100), Vector2(48, 100), Vector2(60, 15)]:
		var plan := [rng.randi_range(3, 4), rng.randi_range(2, 3), rng.randf() < 0.6, rng.randf_range(4.0, 7.0)]
		for sx in [-1.0, 1.0]:
			_temple(Vector2(at.x * sx, at.y), plan, stone, sx)
	# scattered blocks (fallen casing stones), mirrored
	for k in 30:
		var p := Vector2(rng.randf_range(20, HALF - 20), rng.randf_range(-HALF + 20, HALF - 20))
		var s := Vector3(rng.randf_range(1.5, 3.0), rng.randf_range(1.0, 2.0), rng.randf_range(1.5, 3.5))
		if _inside_monument(p, 10.0) or _near_pad(p, 20.0):
			continue
		var yaw := rng.randf() * PI
		for sx in [-1.0, 1.0]:
			_box(s, Vector3(p.x * sx, ground_y(p.x * sx, p.y) + s.y * 0.4, p.y), stone, Vector3(0, yaw * sx, 0.1 * sx))

func _inside_monument(p: Vector2, margin: float) -> bool:
	for py in PYRAMIDS:
		if maxf(absf(p.x - py[0].x), absf(p.y - py[0].y)) < float(py[1]) * 0.5 + margin:
			return true
	return absf(p.x - SPHINX.x) < 8.0 + margin and absf(p.y - SPHINX.y) < 18.0 + margin

func _near_pad(p: Vector2, r: float) -> bool:
	for b in BEACONS:
		if p.distance_to(b) < r:
			return true
	for team in SPAWNS:
		for s in team:
			if p.distance_to(s) < r + 12.0:
				return true
	return false

func _pyramid(c: Vector2, base: float, mat: Material) -> void:
	var h := base * 0.5 * tan(FACE)
	var mesh := CylinderMesh.new()  # 4 radial segments + no top = a square pyramid
	mesh.radial_segments = 4
	mesh.rings = 1
	mesh.top_radius = 0.0
	mesh.bottom_radius = base * 0.5 * sqrt(2.0)
	mesh.height = h
	var body := StaticBody3D.new()
	body.position = Vector3(c.x, h * 0.5 - 0.2, c.y)
	body.rotation.y = PI * 0.25  # faces square to the axes
	var col := CollisionShape3D.new()
	col.shape = mesh.create_convex_shape()
	body.add_child(col)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	body.add_child(mi)
	add_child(body)

# Lion body + head, facing south (+z) along the middle line.
func _sphinx(c: Vector2, mat: Material) -> void:
	_box(Vector3(9, 7, 28), Vector3(c.x, 3.5, c.y - 2), mat)             # body
	_box(Vector3(7, 4, 8), Vector3(c.x, 2.0, c.y + 14), mat)              # forepaws block
	_box(Vector3(6, 7, 6), Vector3(c.x, 9.5, c.y + 9), mat)               # head
	_box(Vector3(8, 4, 3), Vector3(c.x, 10.0, c.y + 8), mat)              # headdress
	_box(Vector3(2.5, 2, 2), Vector3(c.x, 8.0, c.y + 12.5), mat)          # face

# Rows of square pillars under roof slabs; one slab fallen and tilted when plan[2].
func _temple(c: Vector2, plan: Array, mat: Material, sx: float) -> void:
	var cols: int = plan[0]
	var rows: int = plan[1]
	var h: float = plan[3]
	var pitch := 7.0  # >= LANE: no wedges between pillars (T221)
	for i in cols:
		for j in rows:
			var p := c + Vector2((i - (cols - 1) * 0.5) * pitch, (j - (rows - 1) * 0.5) * pitch)
			_box(Vector3(1.6, h, 1.6), Vector3(p.x, ground_y(p.x, p.y) + h * 0.5 - 0.2, p.y), mat)
	var w := cols * pitch
	var d := rows * pitch
	if plan[2]:
		_box(Vector3(w * 0.5, 0.8, d), Vector3(c.x - w * 0.25 * sx, h + 0.4, c.y), mat)
		_box(Vector3(w * 0.45, 0.8, d * 0.9), Vector3(c.x + w * 0.3 * sx, h * 0.45, c.y), mat, Vector3(0, 0, 0.45 * sx))
	else:
		_box(Vector3(w, 0.8, d), Vector3(c.x, h + 0.4, c.y), mat)
