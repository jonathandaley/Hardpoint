extends MapScene
# T222: downtown modeled on Sydney. ~300 m square, flat streets between city blocks:
# CBD towers (lit-window facades) of mixed heights, two parks, a harbour along the north
# edge (quay wall; water beyond, not playable) with a steel arch bridge out over the water
# and a sail-roofed landmark on the waterfront plaza. Mirror-symmetric across x = 0 for
# fairness: team 0 spawns west, team 1 east. 5 beacons (V18) at the plazas, 3 spawns each.
# Everything is generated from fixed data / a fixed seed: identical on every peer.

const HALF := 150.0
const QUAY_Z := -118.0   # harbour edge (north); water beyond
const STREET := 14.0     # street width between blocks
const BLOCK := 34.0      # city block side
const BEACONS := [Vector2(0, 0), Vector2(-70, -80), Vector2(70, -80), Vector2(-70, 70), Vector2(70, 70)]
const SPAWNS := [[Vector2(-132, -40), Vector2(-136, 10), Vector2(-132, 60)],
	[Vector2(132, -40), Vector2(136, 10), Vector2(132, 60)]]
const PARKS := [Vector2(-76, 6), Vector2(76, 6)]  # block centres kept green
const ASPHALT := Color("#2b2d31")
const PAVE := Color("#55575c")
const CONCRETE := Color("#8a8a86")

func _init() -> void:
	center = Vector2.ZERO
	minimap_half = HALF + 6.0

func spawn_points(team: int) -> Array:
	var out: Array = []
	for p in SPAWNS[team]:
		out.append(Vector3(p.x, 0.0, p.y))
	return out

func ground_y(_x: float, _z: float) -> float:
	return 0.0

func minimap_outline() -> PackedVector2Array:
	return PackedVector2Array([Vector2(-HALF, QUAY_Z), Vector2(HALF, QUAY_Z), Vector2(HALF, HALF), Vector2(-HALF, HALF)])

# ---- helpers ----

func _mat(c: Color, rough := 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m

func _solid(size: Vector3, pos: Vector3, mat: Material, rot_y := 0.0, collide := true) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	var holder: Node3D
	if collide:
		var body := StaticBody3D.new()
		var col := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		col.shape = box
		body.add_child(col)
		body.add_child(mi)
		holder = body
	else:
		holder = mi
	holder.position = pos
	holder.rotation.y = rot_y
	add_child(holder)

func _windows_texture(rng: RandomNumberGenerator) -> ImageTexture:
	var img := Image.create(32, 32, false, Image.FORMAT_RGB8)
	img.fill(Color("#1b1d22"))
	for y in range(2, 32, 6):
		for x in range(2, 32, 5):
			var lit := rng.randf() < 0.45
			var c := Color("#b8a978") if lit else Color("#2c323d")
			for dy in 3:
				for dx in 3:
					img.set_pixel(x + dx, y + dy, c)
	return ImageTexture.create_from_image(img)

func build() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 222
	# ground: streets everywhere, pavement plates under blocks
	_solid(Vector3(HALF * 2.0, 1.0, HALF - QUAY_Z), Vector3(0, -0.5, (HALF + QUAY_Z) * 0.5), _mat(ASPHALT))
	# harbour: water plane (no collision) + quay wall + boundary walls
	var water := _mat(Color("#1d4a66"), 0.15)
	water.metallic = 0.3
	_solid(Vector3(600, 0.2, 260), Vector3(0, -2.2, QUAY_Z - 130), water, 0.0, false)
	_solid(Vector3(HALF * 2.0, 1.4, 1.2), Vector3(0, 0.7, QUAY_Z), _mat(PAVE))  # quay edge (low: you see the water)
	for side in [[Vector3(0, 20, QUAY_Z - 0.6), Vector3(HALF * 2.0, 40, 1)], [Vector3(0, 20, HALF), Vector3(HALF * 2.0, 40, 2)],
			[Vector3(-HALF, 20, 15), Vector3(2, 40, 280)], [Vector3(HALF, 20, 15), Vector3(2, 40, 280)]]:
		var body := StaticBody3D.new()
		var col := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = side[1]
		col.shape = box
		body.add_child(col)
		body.position = side[0]
		add_child(body)
	_bridge()
	_sails(Vector3(0, 0, QUAY_Z + 16))
	# city blocks: a grid mirrored across x = 0
	var tex_rng := RandomNumberGenerator.new()
	tex_rng.seed = 2220
	var facades: Array = []
	for k in 4:
		var fm := _mat(Color.WHITE, 0.6)
		fm.albedo_texture = _windows_texture(tex_rng)
		fm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		fm.uv1_triplanar = true
		fm.uv1_scale = Vector3.ONE / 12.0
		fm.emission_enabled = true
		fm.emission_texture = fm.albedo_texture
		fm.emission = Color(0.12, 0.11, 0.08)
		facades.append(fm)
	var pitch := BLOCK + STREET
	for i in range(1, 4):            # block columns east of the central avenue (mirrored west)
		for j in range(-2, 3):       # block rows
			var cx := i * pitch - pitch * 0.5 + 4.0
			var cz := j * pitch + 6.0
			if cz - BLOCK * 0.5 < QUAY_Z + 30.0:
				continue  # waterfront promenade stays open
			for sx in [-1.0, 1.0]:
				var c := Vector2(cx * sx, cz)
				if _near_any(c, BEACONS, 20.0) or _near_spawn(c):
					continue
				if c.distance_to(PARKS[0 if sx < 0 else 1]) < 1.0:
					_park(c, rng)
				else:
					_block(c, rng, facades)
	# central avenue median + plaza paving at the beacons
	for b in BEACONS:
		_solid(Vector3(22, 0.12, 22), Vector3(b.x, 0.06, b.y), _mat(PAVE), 0.0, false)

func _near_any(c: Vector2, pts: Array, r: float) -> bool:
	for p in pts:
		if c.distance_to(p) < r:
			return true
	return false

func _near_spawn(c: Vector2) -> bool:
	for team in SPAWNS:
		if _near_any(c, team, 26.0):
			return true
	return false

# A block: pavement plate, 1-3 towers of mixed height, some low podiums -- seeded, and the
# west half is the mirror of the east half (same rng draws per mirrored pair).
var _block_cache := {}
func _block(c: Vector2, rng: RandomNumberGenerator, facades: Array) -> void:
	var key := Vector2(absf(c.x), c.y)
	if not _block_cache.has(key):
		var plan: Array = []
		var n := rng.randi_range(1, 3)
		for k in n:
			plan.append([rng.randf_range(-6, 6), rng.randf_range(-6, 6), rng.randf_range(10, 18),
				rng.randf_range(10, 18), rng.randf_range(18, 95) if rng.randf() < 0.75 else rng.randf_range(8, 14),
				rng.randi() % facades.size()])
		_block_cache[key] = plan
	var mirror := -1.0 if c.x < 0.0 else 1.0
	# the whole block is a solid podium -- streets are the only ground-level space. (Towers
	# straight on the street with random offsets left 1-2 m slots between them: the T221
	# checker found mechs wedged in two.)
	var podium := 6.0
	_solid(Vector3(BLOCK, podium, BLOCK), Vector3(c.x, podium * 0.5, c.y), facades[int(_block_cache[key][0][5])])
	var roof := _mat(CONCRETE)  # caps: the triplanar window tile also landed on the roofs
	_solid(Vector3(BLOCK + 0.1, 0.2, BLOCK + 0.1), Vector3(c.x, podium + 0.1, c.y), roof, 0.0, false)
	for t in _block_cache[key]:
		var h: float = t[4]
		_solid(Vector3(t[2], h, t[3]), Vector3(c.x + float(t[0]) * mirror, podium + h * 0.5, c.y + float(t[1])), facades[t[5]])
		_solid(Vector3(float(t[2]) + 0.1, 0.2, float(t[3]) + 0.1), Vector3(c.x + float(t[0]) * mirror, podium + h + 0.1, c.y + float(t[1])),
			roof, 0.0, false)
		if h > 40.0:  # roof plant on the tall ones
			_solid(Vector3(float(t[2]) * 0.5, 3.0, float(t[3]) * 0.5), Vector3(c.x + float(t[0]) * mirror, podium + h + 1.5, c.y + float(t[1])),
				_mat(CONCRETE))

func _park(c: Vector2, rng: RandomNumberGenerator) -> void:
	_solid(Vector3(BLOCK, 0.2, BLOCK), Vector3(c.x, 0.1, c.y), _mat(Color("#3f6b35")), 0.0, false)
	var trunk := _mat(Color("#4a3725"))
	var leaf := _mat(Color("#2f5a2a"))
	for k in 9:
		var p := c + Vector2((k % 3 - 1) * 10.0 + rng.randf_range(-2, 2), (k / 3 - 1) * 10.0 + rng.randf_range(-2, 2))
		_solid(Vector3(0.8, 5.0, 0.8), Vector3(p.x, 2.5, p.y), trunk)
		_solid(Vector3(5.0, 4.0, 5.0), Vector3(p.x, 6.5, p.y), leaf, rng.randf() * PI, false)

# Steel through-arch bridge out over the harbour (scenery beyond the quay).
func _bridge() -> void:
	var steel := _mat(Color("#6d7279"), 0.5)
	var z := QUAY_Z - 70.0
	var span := 240.0
	_solid(Vector3(span, 2.0, 22), Vector3(-40, 22, z), steel, 0.0, false)  # deck
	for side in [-1.0, 1.0]:
		var prev := Vector3.ZERO
		for k in 25:
			var t := float(k) / 24.0
			var p := Vector3(-40 - span * 0.5 + span * t, 22.0 + 52.0 * sin(PI * t), z + side * 9.0)
			if k > 0:
				var seg := MeshInstance3D.new()
				var bm := BoxMesh.new()
				bm.size = Vector3(prev.distance_to(p), 3.0, 2.0)
				seg.mesh = bm
				seg.material_override = steel
				add_child(seg)
				seg.position = (prev + p) * 0.5
				seg.rotation.z = atan2(p.y - prev.y, p.x - prev.x)
				if k % 3 == 0:  # hangers down to the deck
					var h := MeshInstance3D.new()
					var hm := BoxMesh.new()
					hm.size = Vector3(0.6, p.y - 22.0, 0.6)
					h.mesh = hm
					h.material_override = steel
					add_child(h)
					h.position = Vector3(p.x, (p.y + 22.0) * 0.5, p.z)
			prev = p
	for px in [-40 - span * 0.5, -40 + span * 0.5]:  # pylons
		_solid(Vector3(14, 40, 26), Vector3(px, 18, z), _mat(Color("#9b8f7a")), 0.0, false)

# Sail-roofed landmark on the waterfront plaza: a podium and white shells (tilted half-shells).
func _sails(at: Vector3) -> void:
	_solid(Vector3(60, 4.0, 28), at + Vector3(0, 2.0, 0), _mat(Color("#b9a98c")))
	var shell := _mat(Color("#f2f0ea"), 0.35)
	for k in 5:
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 9.0 - abs(k - 2) * 1.2
		sm.height = sm.radius * 2.0
		sm.is_hemisphere = true
		mi.mesh = sm
		mi.material_override = shell
		add_child(mi)
		mi.position = at + Vector3(-20 + k * 10.0, 4.0, 0)
		mi.scale = Vector3(0.55, 1.6, 1.0)
		mi.rotation = Vector3(0, 0, deg_to_rad(-22.0 + (k % 2) * 8.0))
	# the shells' footprint is solid (the podium carries the collision); shells are visual
