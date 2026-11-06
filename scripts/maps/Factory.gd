extends MapScene
# T226 / T234: "Factory" (was Flight Deck; user 2026-11-04: keep the deck, rename it, burnt
# orange-red sky). A 220 m square deck plate over a dark hull under a burnt orange-red sky:
# launch rails down the middle with blast deflectors, cargo container stacks, bulkhead walls
# with doorways splitting the deck in thirds, raised catwalks on the outer bulkheads (solid
# wedge ramps up), the bridge tower on the north edge. Flat deck at y = 0. Mirror-symmetric
# across x = 0: team 0 west, team 1 east; 5 beacons (V18), 3 spawns each. Obstacles keep
# >= LANE m apart (T221: no wedges); colliders are boxes and convex wedges (V59).

const HALF := 110.0
const LANE := 9.0
const BEACONS := [Vector2(0, 0), Vector2(-60, -45), Vector2(60, -45), Vector2(-60, 45), Vector2(60, 45)]
const SPAWNS := [[Vector2(-96, -40), Vector2(-98, 0), Vector2(-96, 40)],
	[Vector2(96, -40), Vector2(98, 0), Vector2(96, 40)]]
const BULK_X := 40.0
const TALL := [[-34.0, -16.0], [16.0, 34.0]]       # 10 m bulkheads (z ranges) at x = +-BULK_X
const CATWALK_H := 4.0                             # outer bulkheads: walkable tops, z 60..edge
const CATWALK_Z := 60.0
const RAMP_L := 12.0                               # 4 m over 12 m = 18 deg
const RAIL_Z := 12.0
const DEFLECT_X := 70.0

var _blocked: Array = []  # Rect2 footprints of everything solid placed so far

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
	return PackedVector2Array([Vector2(-HALF, -HALF), Vector2(HALF, -HALF), Vector2(HALF, HALF), Vector2(-HALF, HALF)])

func _mat(c: Color, rough := 0.6, metal := 0.5) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m

func _glow(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 1.5
	return m

func _box(size: Vector3, pos: Vector3, mat: Material, collide := true) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	if not collide:
		mi.position = pos
		add_child(mi)
		return
	var body := StaticBody3D.new()
	body.position = pos
	var col := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	col.shape = bs
	body.add_child(col)
	body.add_child(mi)
	add_child(body)
	_blocked.append(Rect2(pos.x - size.x * 0.5, pos.z - size.z * 0.5, size.x, size.z))

func _panel_texture() -> ImageTexture:
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	img.fill(Color("#3b4048"))
	for i in 64:
		for e in [0, 1, 32]:
			img.set_pixel(i, e, Color("#262a30"))
			img.set_pixel(e, i, Color("#262a30"))
	for r in [Vector2i(4, 4), Vector2i(59, 4), Vector2i(4, 59), Vector2i(59, 59)]:
		img.set_pixel(r.x, r.y, Color("#5a6069"))
	return ImageTexture.create_from_image(img)

func build() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 226
	_sky(rng)
	var deck := _mat(Color.WHITE, 0.7, 0.4)
	deck.albedo_texture = _panel_texture()
	deck.uv1_triplanar = true
	deck.uv1_scale = Vector3.ONE / 8.0
	var body := StaticBody3D.new()  # the deck plate (not in _blocked: it's the floor)
	var col := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(HALF * 2.0, 1.0, HALF * 2.0)
	col.shape = bs
	body.add_child(col)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = bs.size
	mi.mesh = bm
	mi.material_override = deck
	body.add_child(mi)
	body.position.y = -0.5
	add_child(body)
	_box(Vector3(HALF * 2.0 + 8.0, 24.0, HALF * 2.0 + 40.0), Vector3(0, -13.0, 0), _mat(Color("#20242a")), false)  # hull below
	make_boundary(HALF)
	var edge := _glow(Color("#e0a020"))
	for s in [-1.0, 1.0]:  # deck-edge railings + light strips (visual; the boundary stops you)
		_box(Vector3(HALF * 2.0, 1.2, 0.3), Vector3(0, 0.6, s * (HALF - 0.2)), _mat(Color("#6a7079")), false)
		_box(Vector3(0.3, 1.2, HALF * 2.0), Vector3(s * (HALF - 0.2), 0.6, 0), _mat(Color("#6a7079")), false)
		_box(Vector3(HALF * 2.0, 0.05, 0.6), Vector3(0, 0.03, s * (HALF - 2.0)), edge, false)
	_rails()
	_bulkheads()
	_box(Vector3(36, 28, 14), Vector3(0, 14, -HALF + 7.0), _mat(Color("#4a515b")))  # bridge tower, flush on the edge
	_box(Vector3(30, 3, 0.4), Vector3(0, 22, -HALF + 14.25), _glow(Color("#7fd0ff")), false)  # its window band
	for b in BEACONS:
		_box(Vector3(18, 0.06, 18), Vector3(b.x, 0.03, b.y), _mat(Color("#2d5560")), false)
	for team in SPAWNS:
		for s in team:
			_box(Vector3(10, 0.06, 10), Vector3(s.x, 0.03, s.y), _mat(Color("#55402a")), false)
	_containers(rng)

# T234: burnt orange-red sky, warm ambient light, a light haze (was a starfield + planet).
# T320 (HUMAN_FOUND 2026-11-05: "Texture with GL ID of 63: leaked 349524 bytes" on closing the
# game): giving the environment a new Sky leaks two 256 px radiance maps in the compatibility
# renderer at exit (whether that Sky is freed early, kept static or duplicated); recolouring the
# arena's own Sky doesn't. That Sky is shared through the resource cache, so the material goes
# back when the map leaves.
var _sky_restore: Array = []

func _exit_tree() -> void:
	if not _sky_restore.is_empty():
		(_sky_restore[0] as Sky).sky_material = _sky_restore[1]

func _sky(rng: RandomNumberGenerator) -> void:
	for k in 4000:  # replay the T226 starfield's draws (same calls: randf/randi advance
		rng.randf_range(0.25, 1.0)  # differently) so the container layout stays the same
		rng.randi()
		rng.randi()
		rng.randf_range(0.85, 1.1)
	var env := own_environment()
	if env == null:
		return
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color("#5e1a0c")
	sm.sky_horizon_color = Color("#c8582a")
	sm.ground_horizon_color = Color("#9c4420")
	sm.ground_bottom_color = Color("#2a0f08")
	if env.sky == null:  # an environment without a sky (tools): give it one
		env.sky = Sky.new()
	else:
		_sky_restore = [env.sky, env.sky.sky_material]
	env.sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#d09a7a")
	env.ambient_light_energy = 0.6
	env.fog_enabled = true
	env.fog_light_color = Color("#b4542a")
	env.fog_density = 0.0015  # T300 (HUMAN_FOUND 2026-11-05: "less atmospheric haze"; was 0.004)

# Launch rails down the middle line (flush, visual) with a lit centre stripe; a blast
# deflector (solid, upright) across each rail near either end.
func _rails() -> void:
	var rail := _mat(Color("#7a828c"), 0.3, 0.8)
	var lamp := _glow(Color("#40c0ff"))
	for z in [-RAIL_Z, RAIL_Z]:
		for dz in [-1.4, 1.4]:
			_box(Vector3(176, 0.08, 0.5), Vector3(0, 0.04, z + dz), rail, false)
		for x in range(-84, 85, 8):
			_box(Vector3(0.8, 0.06, 0.8), Vector3(x, 0.03, z), lamp, false)
		for sx in [-1.0, 1.0]:
			_box(Vector3(1.0, 3.5, 10.0), Vector3(sx * DEFLECT_X, 1.75, z), _mat(Color("#8a6a3a")))

# Bulkheads at x = +-BULK_X: two tall wall segments (doorways between), and the outer
# segments as 4 m catwalk blocks with a solid wedge ramp at the inner end.
func _bulkheads() -> void:
	var steel := _mat(Color("#555c66"))
	var stripe := _glow(Color("#e0a020"))
	for sx in [-1.0, 1.0]:
		var x: float = sx * BULK_X
		for seg in TALL:
			var z0: float = seg[0]
			var z1: float = seg[1]
			_box(Vector3(3, 10, z1 - z0), Vector3(x, 5, (z0 + z1) * 0.5), steel)
			# T302 (HUMAN_FOUND 2026-11-05: yellow bands "at the same depth, so flicker"): the
			# stripe ran exactly the wall's length, its end faces in the wall's end planes --
			# 5 cm proud at each end now, like its 5 cm on each side
			_box(Vector3(3.1, 0.4, z1 - z0 + 0.1), Vector3(x, 9.0, (z0 + z1) * 0.5), stripe, false)
		for sz in [-1.0, 1.0]:
			var length := HALF - CATWALK_Z
			_box(Vector3(6, CATWALK_H, length), Vector3(x, CATWALK_H * 0.5, sz * (CATWALK_Z + length * 0.5)), steel)
			for rx in [-2.85, 2.85]:  # guard rails (visual)
				_box(Vector3(0.2, 1.0, length), Vector3(x + rx, CATWALK_H + 0.5, sz * (CATWALK_Z + length * 0.5)), stripe, false)
			_ramp(Vector2(x, sz * (CATWALK_Z - RAMP_L * 0.5)), sz, steel)

# Solid wedge, 6 m wide, rising from the deck to the catwalk top toward |z| = CATWALK_Z.
func _ramp(c: Vector2, sz: float, mat: Material) -> void:
	var pm := PrismMesh.new()
	pm.left_to_right = 1.0  # right triangle: the high end at local +x
	pm.size = Vector3(RAMP_L, CATWALK_H, 6.0)
	var body := StaticBody3D.new()
	body.position = Vector3(c.x, CATWALK_H * 0.5, c.y)
	body.rotation.y = -PI * 0.5 * sz  # local +x -> world +z * sz (toward the catwalk)
	var col := CollisionShape3D.new()
	col.shape = pm.create_convex_shape()
	body.add_child(col)
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	mi.material_override = mat
	body.add_child(mi)
	add_child(body)
	_blocked.append(Rect2(c.x - 3.0, c.y - RAMP_L * 0.5, 6.0, RAMP_L))

func _rect_dist(r: Rect2, p: Vector2) -> float:
	return Vector2(maxf(maxf(r.position.x - p.x, 0.0), p.x - r.end.x),
		maxf(maxf(r.position.y - p.y, 0.0), p.y - r.end.y)).length()

func _free(r: Rect2) -> bool:
	if r.position.x < -HALF + LANE or r.end.x > HALF - LANE or r.position.y < -HALF + LANE or r.end.y > HALF - LANE:
		return false
	if absf(r.get_center().y) - r.size.y * 0.5 < RAIL_Z + 6.0:
		return false  # the launch lane stays open
	for b in BEACONS:
		if _rect_dist(r, b) < 14.0:
			return false
	for team in SPAWNS:
		for s in team:
			if _rect_dist(r, s) < 22.0:
				return false
	for o in _blocked:
		if (o as Rect2).grow(LANE).intersects(r):
			return false
	return true

# Cargo container stacks (12 x 2.6 x 2.6 m boxes, 1-3 high, single or double row), mirrored.
func _containers(rng: RandomNumberGenerator) -> void:
	var paint := [_mat(Color("#a2532c"), 0.8, 0.3), _mat(Color("#2f7276"), 0.8, 0.3),
		_mat(Color("#8c8f93"), 0.8, 0.3), _mat(Color("#b8932f"), 0.8, 0.3)]
	for k in 160:
		var p := Vector2(rng.randf_range(6, HALF - 12), rng.randf_range(-HALF + 12, HALF - 12))
		var along_x := rng.randf() < 0.5
		var rows := rng.randi_range(1, 2)
		var levels := rng.randi_range(1, 3)
		var size := Vector2(12.0, 2.6 * rows) if along_x else Vector2(2.6 * rows, 12.0)
		var r := Rect2(p - size * 0.5, size)
		var m := Rect2(Vector2(-r.end.x, r.position.y), size)
		if r.position.x < LANE * 0.5 or not _free(r) or not _free(m):
			continue
		var colors: Array = []
		for i in rows * levels:
			colors.append(paint[rng.randi() % paint.size()])
		for rect in [r, m]:
			var c: Vector2 = (rect as Rect2).get_center()
			var body := StaticBody3D.new()  # one collider per stack
			body.position = Vector3(c.x, 1.3 * levels, c.y)
			var col := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = Vector3(size.x, 2.6 * levels, size.y)
			col.shape = bs
			body.add_child(col)
			add_child(body)
			_blocked.append(rect)
			for lv in levels:
				for row in rows:
					var mi := MeshInstance3D.new()
					var bm := BoxMesh.new()
					bm.size = Vector3(12.0, 2.5, 2.5) if along_x else Vector3(2.5, 2.5, 12.0)
					mi.mesh = bm
					mi.material_override = colors[lv * rows + row]
					var off := (row - (rows - 1) * 0.5) * 2.6
					mi.position = Vector3(0 if along_x else off, -1.3 * levels + 1.3 + lv * 2.6, off if along_x else 0)
					body.add_child(mi)
