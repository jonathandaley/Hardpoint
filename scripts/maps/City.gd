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
	_rects.append(Rect2(-30, QUAY_Z + 2, 60, 28))  # the sails' podium
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
	_dress_materials()
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
				_rects.append(Rect2(c - Vector2.ONE * BLOCK * 0.5, Vector2.ONE * BLOCK))
				if c.distance_to(PARKS[0 if sx < 0 else 1]) < 1.0:
					_park(c, rng)
				else:
					_block(c, rng, facades)
	_infill(rng, facades)
	# central avenue median + plaza paving at the beacons
	for b in BEACONS:
		# T514 (HUMAN_FOUND 2026-11-19: "There's a race between the pad under beacons and the sidewalk on
		# Sydney."): the T449 pavement is 0.12 m too -- the tops z-fought where they overlap; 1 cm up
		_solid(Vector3(22, 0.13, 22), Vector3(b.x, 0.065, b.y), _mat(PAVE), 0.0, false)
	_streets()

# T231 (HUMAN_FOUND_ISSUES 2026-11-04: "Sydney feels too open"): the beacon / spawn
# clearings, the promenade and the avenue get low and mid-rise buildings and kiosks
# (cover), mirrored across x = 0, each >= LANE from everything else (T221: no wedges).
# Streets between blocks (14 m) stay open: an infill needs LANE on both sides.
const LANE := 9.0
var _rects: Array = []  # Rect2 footprints of everything solid at street level

func _rect_dist(r: Rect2, p: Vector2) -> float:
	return Vector2(maxf(maxf(r.position.x - p.x, 0.0), p.x - r.end.x),
		maxf(maxf(r.position.y - p.y, 0.0), p.y - r.end.y)).length()

func _infill_free(r: Rect2) -> bool:
	if r.position.x < -HALF + LANE or r.end.x > HALF - LANE or r.position.y < QUAY_Z + LANE or r.end.y > HALF - LANE:
		return false
	for b in BEACONS:
		if _rect_dist(r, b) < 14.0:
			return false
	for team in SPAWNS:
		for sp in team:
			if _rect_dist(r, sp) < 24.0:
				return false
	for o in _rects:
		if (o as Rect2).grow(LANE).intersects(r):
			return false
	return true

func _infill(rng: RandomNumberGenerator, facades: Array) -> void:
	var kiosk := [_mat(Color("#7a5a3a")), _mat(Color("#3f5f6f")), _mat(Color("#8a3f34")), _mat(Color("#6b6b5a"))]
	for k in 500:
		var big := rng.randf() < 0.55
		var size := Vector2(rng.randf_range(10, 18), rng.randf_range(10, 18)) if big else Vector2(rng.randf_range(4, 7), rng.randf_range(4, 7))
		var h := rng.randf_range(6, 18) if big else rng.randf_range(3, 4.5)
		var c := Vector2(rng.randf_range(LANE, HALF - LANE), rng.randf_range(QUAY_Z + LANE, HALF - LANE))
		var r := Rect2(c - size * 0.5, size)
		var m := Rect2(Vector2(-r.end.x, r.position.y), size)
		if r.position.x < LANE * 0.5 or not _infill_free(r) or not _infill_free(m):
			continue
		var pick := rng.randi()
		var mat: Material = _lowrise[pick % _lowrise.size()] if big else kiosk[pick % kiosk.size()]
		for rect in [r, m]:
			var q: Vector2 = (rect as Rect2).get_center()
			_rects.append(rect)
			_solid(Vector3(size.x, h, size.y), Vector3(q.x, h * 0.5, q.y), mat)
			_solid(Vector3(size.x + 0.1, 0.2, size.y + 0.1), Vector3(q.x, h + 0.1, q.y), _roof, 0.0, false)
			_shopfront(q, size, pick)
			if big:
				_parapet(q, size, h)
				_roof_plant(q, size, h)
			else:  # kiosk: a deep overhanging roof in the awning colour
				_deco(Vector3(size.x + 1.4, 0.25, size.y + 1.4), Vector3(q.x, h + 0.125, q.y), _awnings[pick % _awnings.size()], "Awning")

# T441 (user 2026-11-17: "the skyscrapers in Sydney are great, the various smaller buildings are
# boring"): the low-rise infill gets sandstone / brick / render facades with their own windows,
# every low building and podium a lit shopfront band at street level under an awning, the
# infill a parapet and roof plant (AC units, a stair hut, a water tank), kiosks a deep coloured
# roof. All visual (no colliders: the T221 layout and its lanes are untouched); the plant is
# seeded per mirrored pair so both halves match; materials are shared so the merge (T424) keeps
# it to one draw each.
var _roof: StandardMaterial3D
var _shop: StandardMaterial3D
var _plant: StandardMaterial3D
var _tank: StandardMaterial3D
var _awnings: Array = []
var _lowrise: Array = []
const LOWRISE_WALLS := [Color("#c9a26b"), Color("#9a4f3c"), Color("#d6cdb6")]  # sandstone, brick, render
const AWNING_COLS := [Color("#2f5d4a"), Color("#8c2f2f"), Color("#2c3e63"), Color("#b0832b")]

func _dress_materials() -> void:
	_roof = _mat(CONCRETE)
	_plant = _mat(Color("#a7aaad"), 0.7)
	_tank = _mat(Color("#5d6166"), 0.6)
	for c in AWNING_COLS:
		_awnings.append(_mat(c))
	_shop = _pixel_mat(_shopfront_image(), Vector3(1.0 / 4.0, 1.0 / 2.4, 1.0 / 4.0), Color(0.3, 0.25, 0.17))
	var wr := RandomNumberGenerator.new()
	wr.seed = 2221
	for wall in LOWRISE_WALLS:
		var imgs := _lowrise_images(wall, wr)
		var m := _pixel_mat(imgs[0], Vector3.ONE / 12.0, Color(0.16, 0.14, 0.09))
		m.emission_texture = ImageTexture.create_from_image(imgs[1])
		_lowrise.append(m)

## Nearest-filtered, world-triplanar (so it merges and lines up across pieces), lit by its texture.
func _pixel_mat(img: Image, scale: Vector3, glow: Color) -> StandardMaterial3D:
	img.generate_mipmaps()
	var m := _mat(Color.WHITE, 0.7)
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = scale
	m.emission_enabled = true
	m.emission_texture = m.albedo_texture
	m.emission = glow
	return m

## 16 x 8 px over 4 m x 2.4 m: dark frame rows top and bottom, 1 m glass panes split by
## mullions, each its own tint (warm, cool, dark: a closed shop). Symmetric top / bottom, so it
## reads the same whichever way the triplanar v runs.
func _shopfront_image() -> Image:
	var img := Image.create(16, 8, false, Image.FORMAT_RGB8)
	img.fill(Color("#1c1d20"))
	var panes := [Color("#b8894a"), Color("#6f8793"), Color("#262b33"), Color("#c48a3c")]
	for p in 4:  # 1 m panes: 3 px of glass + a 1 px mullion
		for x in range(p * 4, p * 4 + 3):
			for y in range(1, 7):
				img.set_pixel(x, y, panes[p])
	return img

## 32 x 32 px over 12 m: wall with a 2-shade pixel grain, rows of 3 x 4 px windows (lit / dark).
## [albedo, emission]: the emission has only the lit windows, so the wall itself doesn't glow.
func _lowrise_images(wall: Color, wr: RandomNumberGenerator) -> Array:
	var img := Image.create(32, 32, false, Image.FORMAT_RGB8)
	var glow := Image.create(32, 32, false, Image.FORMAT_RGB8)
	glow.fill(Color.BLACK)
	for y in 32:
		for x in 32:
			img.set_pixel(x, y, wall.darkened(0.12) if wr.randf() < 0.3 else wall)
	for y in range(3, 32, 8):
		for x in range(2, 32, 6):
			var lit := wr.randf() < 0.4
			var c := Color("#e2c27e") if lit else Color("#2b3038")
			for dy in 4:
				for dx in 3:
					img.set_pixel(x + dx, y + dy, c)
					if lit:
						glow.set_pixel(x + dx, y + dy, c)
	return [img, glow]

func _deco(size: Vector3, pos: Vector3, mat: Material, label: String) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.set_meta(&"deco", label)  # names collide (Godot renames duplicates); probe city_lowrise reads this
	mi.position = pos
	add_child(mi)

## A lit band of shop windows round the building's foot, and an awning over it.
func _shopfront(c: Vector2, size: Vector2, pick: int) -> void:
	_deco(Vector3(size.x + 0.3, 2.4, size.y + 0.3), Vector3(c.x, 1.2, c.y), _shop, "Shopfront")
	_deco(Vector3(size.x + 1.2, 0.15, size.y + 1.2), Vector3(c.x, 2.95, c.y), _awnings[absi(pick) % _awnings.size()], "Awning")

func _parapet(c: Vector2, size: Vector2, h: float) -> void:
	for s in [-1.0, 1.0]:
		_deco(Vector3(size.x + 0.1, 0.6, 0.3), Vector3(c.x, h + 0.3, c.y + s * (size.y * 0.5 - 0.1)), _roof, "Parapet")
		_deco(Vector3(0.3, 0.6, size.y + 0.1), Vector3(c.x + s * (size.x * 0.5 - 0.1), h + 0.3, c.y), _roof, "Parapet")

## AC units in one quadrant, a stair hut and a water tank in others; mirrored with the building.
func _roof_plant(c: Vector2, size: Vector2, h: float) -> void:
	var mirror := -1.0 if c.x < 0.0 else 1.0
	var pr := RandomNumberGenerator.new()
	pr.seed = hash([snappedf(absf(c.x), 0.01), snappedf(c.y, 0.01)])
	var top := h + 0.2
	var quads := [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]
	var first := pr.randi() % 4
	var at := func(k: int) -> Vector2:
		var qd: Vector2 = quads[(first + k) % 4]
		return c + Vector2(qd.x * size.x * 0.25 * mirror, qd.y * size.y * 0.25)
	var ac: Vector2 = at.call(0)
	for k in pr.randi_range(1, 3):
		_deco(Vector3(1.6, 1.1, 1.6), Vector3(ac.x + (k - 1) * 1.9 * mirror, top + 0.55, ac.y), _plant, "RoofPlant")
	if pr.randf() < 0.6:
		var hut: Vector2 = at.call(1)
		_deco(Vector3(3.0, 2.6, 2.6), Vector3(hut.x, top + 1.3, hut.y), _roof, "RoofPlant")
	if pr.randf() < 0.45:
		var tk: Vector2 = at.call(2)
		_deco(Vector3(2.4, 0.6, 2.4), Vector3(tk.x, top + 0.3, tk.y), _tank, "RoofPlant")
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 1.1
		cm.bottom_radius = 1.1
		cm.height = 2.2
		mi.mesh = cm
		mi.material_override = _tank
		mi.set_meta(&"deco", "RoofPlant")
		mi.position = Vector3(tk.x, top + 0.6 + 1.1, tk.y)
		add_child(mi)

# T449 (user 2026-11-17: yes to "lane markings, crosswalks and kerbs"): dashed white centre lines
# down the streets, zebra crossings on each arm of a junction, and a pavement with a kerb round
# every city block. Flat and visual only (no colliders); markings skip anything solid at street
# level (_rects: blocks, parks, kiosks), the beacon plazas and the spawns; merged per material.
const STREET_X := [0.0, 52.0, -52.0, 100.0, -100.0]  # centre lines between the block columns
const STREET_Z := [-66.0, -18.0, 30.0, 78.0]          # and between the block rows
const DASH := 3.0
const DASH_GAP := 3.0

func _street_free(p: Vector2, margin: float) -> bool:
	if p.x < -HALF + 6.0 or p.x > HALF - 6.0 or p.y < QUAY_Z + 4.0 or p.y > HALF - 6.0:
		return false
	for r in _rects:
		if (r as Rect2).grow(margin).has_point(p):
			return false
	for b in BEACONS:
		if absf(p.x - b.x) < 11.0 + margin and absf(p.y - b.y) < 11.0 + margin:
			return false
	return not _near_spawn(p)

func _streets() -> void:
	var paint := _mat(Color("#d6d4c8"), 0.8)
	var walk := _mat(Color("#6e7076"))
	var kerb := _mat(Color("#9a9a94"))
	# centre dashes, along z on the x lines and along x on the z lines
	for x in STREET_X:
		var z := QUAY_Z + 4.0
		while z < HALF - 6.0:
			if _street_free(Vector2(x, z), 1.0) and _street_free(Vector2(x, z + DASH), 1.0) and not _at_junction(Vector2(x, z + DASH * 0.5)):
				_solid(Vector3(0.25, 0.03, DASH), Vector3(x, 0.015, z + DASH * 0.5), paint, 0.0, false)
			z += DASH + DASH_GAP
	for z in STREET_Z:
		var x := -HALF + 6.0
		while x < HALF - 6.0:
			if _street_free(Vector2(x, z), 1.0) and _street_free(Vector2(x + DASH, z), 1.0) and not _at_junction(Vector2(x + DASH * 0.5, z)):
				_solid(Vector3(DASH, 0.03, 0.25), Vector3(x + DASH * 0.5, 0.015, z), paint, 0.0, false)
			x += DASH + DASH_GAP
	# zebra crossings on each arm of every junction, 9 m out from its centre
	for x in STREET_X:
		for z in STREET_Z:
			for arm in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
				var c: Vector2 = Vector2(x, z) + arm * 9.0
				if not _street_free(c, 0.5):
					continue
				for k in 6:  # stripes run along the street, stepped across it
					var off := (k - 2.5) * 1.6
					var at: Vector2 = c + Vector2(arm.y, arm.x) * off
					var size := Vector3(2.4, 0.03, 0.7) if arm.x != 0.0 else Vector3(0.7, 0.03, 2.4)
					if _street_free(at, 0.3):
						_solid(size, Vector3(at.x, 0.015, at.y), paint, 0.0, false)
	# pavement + kerb round every city block (34 m squares), skipping the parks' green
	for r in _rects:
		var rect := r as Rect2
		if absf(rect.size.x - BLOCK) > 0.5 or absf(rect.size.y - BLOCK) > 0.5:
			continue
		var c := rect.get_center()
		var side := BLOCK * 0.5 + 0.9
		for s in [-1.0, 1.0]:
			_solid(Vector3(BLOCK + 3.6, 0.12, 1.8), Vector3(c.x, 0.06, c.y + s * side), walk, 0.0, false)
			_solid(Vector3(1.8, 0.12, BLOCK), Vector3(c.x + s * side, 0.06, c.y), walk, 0.0, false)
			_solid(Vector3(BLOCK + 4.0, 0.2, 0.2), Vector3(c.x, 0.1, c.y + s * (side + 1.0)), kerb, 0.0, false)
			_solid(Vector3(0.2, 0.2, BLOCK + 4.0), Vector3(c.x + s * (side + 1.0), 0.1, c.y), kerb, 0.0, false)

func _at_junction(p: Vector2) -> bool:
	for x in STREET_X:
		for z in STREET_Z:
			if absf(p.x - x) < 12.0 and absf(p.y - z) < 12.0:
				return true
	return false

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
	# T441: the podium in a low-rise facade (sandstone / brick / render under the glass towers)
	_solid(Vector3(BLOCK, podium, BLOCK), Vector3(c.x, podium * 0.5, c.y), _lowrise[int(_block_cache[key][0][5]) % _lowrise.size()])
	var roof: Material = _roof  # caps: the triplanar window tile also landed on the roofs
	_solid(Vector3(BLOCK + 0.1, 0.2, BLOCK + 0.1), Vector3(c.x, podium + 0.1, c.y), roof, 0.0, false)
	_shopfront(c, Vector2(BLOCK, BLOCK), int(absf(c.x) + c.y * 3.0))
	_parapet(c, Vector2(BLOCK, BLOCK), podium + 0.2)
	for t in _block_cache[key]:
		var h: float = t[4]
		var low := h < 20.0  # T441: the short ones (8-14 m) are low-rise: own facade, parapet, roof plant
		var tc := Vector2(c.x + float(t[0]) * mirror, c.y + float(t[1]))
		_solid(Vector3(t[2], h, t[3]), Vector3(tc.x, podium + h * 0.5, tc.y), _lowrise[int(t[5]) % _lowrise.size()] if low else facades[t[5]])
		if low:
			_parapet(tc, Vector2(t[2], t[3]), podium + h + 0.2)
			_roof_plant(tc, Vector2(t[2], t[3]), podium + h)
		_solid(Vector3(float(t[2]) + 0.1, 0.2, float(t[3]) + 0.1), Vector3(c.x + float(t[0]) * mirror, podium + h + 0.1, c.y + float(t[1])),
			roof, 0.0, false)
		if h > 40.0:  # roof plant on the tall ones
			_solid(Vector3(float(t[2]) * 0.5, 3.0, float(t[3]) * 0.5), Vector3(c.x + float(t[0]) * mirror, podium + h + 1.5, c.y + float(t[1])),
				_roof)

func _park(c: Vector2, rng: RandomNumberGenerator) -> void:
	_solid(Vector3(BLOCK, 0.2, BLOCK), Vector3(c.x, 0.1, c.y), _mat(Color("#3f6b35")), 0.0, false)
	var trunk := _mat(Color("#4a3725"))
	var leaf := _mat(Color("#2f5a2a"))
	for k in 9:
		var p := c + Vector2((k % 3 - 1) * 10.0 + rng.randf_range(-2, 2), (k / 3 - 1) * 10.0 + rng.randf_range(-2, 2))
		_trunk(Vector3(p.x, 0.0, p.y), trunk)
		_solid(Vector3(5.0, 4.0, 5.0), Vector3(p.x, 6.5, p.y), leaf, rng.randf() * PI, false)

# T230: round trunks (capsule collider, V59). The 0.8 m box trunks had flat faces a bot
# pushed into square-on, and voxelised so thin in the navmesh that paths grazed them: two
# big bots stalled in the park for ~45 s (HUMAN_FOUND_ISSUES 2026-11-04).
func _trunk(at: Vector3, mat: Material) -> void:
	var body := StaticBody3D.new()
	body.position = at
	var col := CollisionShape3D.new()
	var cs := CapsuleShape3D.new()
	cs.radius = 0.6
	cs.height = 6.0
	col.shape = cs
	col.position.y = 2.5
	body.add_child(col)
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.45
	cm.bottom_radius = 0.6
	cm.height = 5.0
	mi.mesh = cm
	mi.material_override = mat
	mi.position.y = 2.5
	body.add_child(mi)
	add_child(body)

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
