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
	if absf(x) < 7.5:  # causeway line down the middle: flat under all 8 m of slab (T439: was 3 m)
		h = lerpf(h, 0.0, smoothstep(7.5, 4.5, absf(x)))
	return h

const FOG_SKY := 0.7  # T445: share of the sky the fog paints (1 = all of it, the old flat tan)

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
		env.ambient_light_color = Color("#f0d9b0")
		env.ambient_light_energy = 0.75
		# T445 (user 2026-11-17: yes to "a sun disc and a gradient ... lighter fog"): the sky was one
		# flat tan -- the fog painted all of it (fog_sky_affect 1). Now the fog paints FOG_SKY of it
		# over the arena's own sky, so it darkens overhead and pales to sand at the horizon, the
		# sun's glow shows through (the Sun light warmed), and the fog is lighter (0.0025 -> 0.0018)
		# so the far pyramids still read. No Sky of its own: a Sky.new() leaks at exit (T346).
		env.fog_density = 0.0018
		env.fog_sky_affect = FOG_SKY
	var sun := get_parent().get_node_or_null("Sun") as DirectionalLight3D
	if sun != null:
		sun.light_color = Color(1.0, 0.93, 0.8)  # desert sun (Arena's default is a cool white)
	# T443: cut-stone courses (T440's pixel grain before); 0.6 x: the grain used to multiply the
	# stone to about that, and the map's light was tuned for it
	var stone := course_mat(Color(STONE.r * 0.6, STONE.g * 0.6, STONE.b * 0.6), 224)
	for py in PYRAMIDS:
		_pyramid(py[0], py[1], stone)
	_sphinx(SPHINX, stone)
	# causeway: flush stone slabs down the middle (0.25 m: steppable)
	var slab := course_mat(Color("#bfae88").darkened(0.25), 225)  # T443: flagstones (the top view of the courses)
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

# T443 (2026-11-17 survey: the pyramids were smooth): stone laid in courses. 16 x 16 px over 3 m
# (~19 cm a pixel, chunky like T440): two 1.5 m courses of 1.5 m blocks, the upper one offset half a
# block, 1 px mortar lines, each block its own shade with a little pixel grain. World triplanar
# with a sharp blend, so on a pyramid face (closer to upright than flat) the side projection wins
# and the courses run level; seen from above (causeway, roofs) the same tile reads as flagstones.
const COURSE_PX := 16
const COURSE_M := 3.0

static func course_image(base: Color, seed: int) -> Image:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var img := Image.create(COURSE_PX, COURSE_PX, false, Image.FORMAT_RGB8)
	var mortar := base.darkened(0.45)
	for row in 2:
		var shift := 0 if row == 0 else COURSE_PX / 4
		var shades := [rng.randf_range(-0.1, 0.06), rng.randf_range(-0.1, 0.06)]
		for y in range(row * 8, row * 8 + 8):
			for x in COURSE_PX:
				var xs := (x + shift) % COURSE_PX
				var c: Color
				if y == row * 8 or xs % 8 == 0:
					c = mortar
				else:
					var k: float = shades[xs / 8] + rng.randf_range(-0.04, 0.04)
					c = base.lightened(k) if k > 0.0 else base.darkened(-k)
				img.set_pixel(x, y, c)
	img.generate_mipmaps()
	return img

func course_mat(base: Color, seed: int) -> StandardMaterial3D:
	var m := _mat(Color.WHITE)
	m.albedo_texture = ImageTexture.create_from_image(course_image(base, seed))
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_triplanar_sharpness = 8.0
	m.uv1_scale = Vector3.ONE / COURSE_M
	return m

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
	var w := cols * pitch
	var d := rows * pitch
	# T439 (user 2026-11-17: floating pieces in Giza): the roof sat at h + 0.4 while each pillar
	# stood h tall on its own dune height, so roofs hovered up to ~1 m over the low pillars. Now
	# every pillar reaches one top (h over the highest pillar's ground) and the roof rests on it.
	var top := -INF
	for i in cols:
		for j in rows:
			var q := c + Vector2((i - (cols - 1) * 0.5) * pitch, (j - (rows - 1) * 0.5) * pitch)
			top = maxf(top, ground_y(q.x, q.y) + h)
	for i in cols:
		for j in rows:
			var dx := (i - (cols - 1) * 0.5) * pitch
			if plan[2] and dx > 0.9:  # dx is already toward sx (positions mirror below)
				continue  # under the fallen half: these pillars went down with it
			var p := c + Vector2(dx * sx, (j - (rows - 1) * 0.5) * pitch)
			var foot := ground_y(p.x, p.y) - 0.2
			_box(Vector3(1.6, top - foot, 1.6), Vector3(p.x, (top + foot) * 0.5, p.y), mat)
	if plan[2]:
		_box(Vector3(w * 0.5, 0.8, d), Vector3(c.x - w * 0.25 * sx, top + 0.4, c.y), mat)
		# the other half leans from the sand up against the standing half's end
		var length := w * 0.45
		var foot_x := c.x + sx * length * 0.8
		var g := ground_min(foot_x, c.y, length * 0.5) - 0.2
		var tilt := asin(clampf((top - g) / length, 0.0, 1.0))
		var cx := c.x + sx * (cos(tilt) * length * 0.5 - 0.1)  # high end tucked under the roof end
		_box(Vector3(length, 0.8, d * 0.9), Vector3(cx, g + sin(tilt) * length * 0.5 + cos(tilt) * 0.4, c.y), mat, Vector3(0, 0, -tilt * sx))
	else:
		_box(Vector3(w, 0.8, d), Vector3(c.x, top + 0.4, c.y), mat)
