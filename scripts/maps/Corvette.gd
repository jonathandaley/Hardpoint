extends MapScene
# T235: ship interior in the spirit of the Tantive IV's corridors (HUMAN_FOUND_ISSUES
# 2026-11-04; not a copy). Roofed (user 2026-11-04): a 184 x 92 m hull, floor to a 10 m
# ceiling. Three long corridors (along x) and four cross corridors, all 11 m wide, cut a
# grid of solid wall blocks; the blocks at the ends are open spawn halls, the centre ones
# a reactor room, and four are beacon alcoves off the outer corridors. White panelled
# walls with (visual, 0.15 m) ribs, ceiling light strips. Mirror-symmetric across x = 0:
# team 0 west, team 1 east; 5 beacons (V18), 3 spawns each. Colliders: boxes (V59).
# Jumps and arcing shots meet the ceiling; the shoulder camera's spring arm (mask 1) is
# kept out of walls and ceiling by the same colliders.

# T303 (HUMAN_FOUND 2026-11-05: "Corvette feels very spread out, shrink it by 30%"): the whole
# floor plan -- hull, corridors (11 -> 7.7 m), blocks, beacons, spawns, set pieces -- is the
# T235 layout scaled by S; the ceiling height and the props' own sizes stay.
const S := 0.7
const HX := 92.0 * S            # hull half length (x)
const HZ := 46.0 * S            # hull half width (z)
const H := 10.0                 # ceiling height
const W := 11.0 * S             # corridor width
const ROWS := [-30.0 * S, 0.0, 30.0 * S]                  # corridor centre lines along x (z values)
const COLS := [-60.0 * S, -20.0 * S, 20.0 * S, 60.0 * S]  # cross corridor centre lines along z (x values)
const BEACONS := [Vector2(0, 0), Vector2(-40, -37) * S, Vector2(40, -37) * S, Vector2(-40, 37) * S, Vector2(40, 37) * S]
# T358 (user on T303: "Reduce to two spawnpoint, neither of them partly inside the wall like they
# are now. Make sure mechs can't stick into the walls"): the team's spawn line (8 m apart, up to
# +-20 m) ran into the hull walls and the crate pillars. Two spawns a side, a 5 m line, and
# clamp_spawn keeps every spot in the open hall, SPAWN_CLEAR m off the walls and the crates.
const SPAWNS := [[Vector2(-82, -20) * S, Vector2(-82, 20) * S], [Vector2(82, -20) * S, Vector2(82, 20) * S]]
const SPAWN_CLEAR := 2.5
const CRATES_X := 74.0 * S
const CRATES_Z := [-38.0 * S, -12.0 * S, 12.0 * S, 38.0 * S]
const CRATE_HALF := 1.2

var _wall_mat: StandardMaterial3D

func _init() -> void:
	center = Vector2.ZERO
	minimap_half = HX + 4.0
	spawn_spacing = 5.0  # T358
	# T488 (HUMAN_FOUND 2026-11-18: "Navmesh in Corvette needs work, some bots are trying to walk through
	# pillars."): bots crossing the corridor grid cut the wall-block corners on the 0.75 m margin (a big
	# mech's capsule is ~0.8 m): 2 cells keep paths clear of them
	nav_agent_radius = 1.5

func clamp_spawn(p: Vector3) -> Vector3:
	var side := signf(p.x) if p.x != 0.0 else 1.0
	var inner: float = COLS[COLS.size() - 1] + W * 0.5  # the hall's inner edge
	var x := side * clampf(absf(p.x), inner + SPAWN_CLEAR, HX - SPAWN_CLEAR)
	var z := clampf(p.z, -HZ + SPAWN_CLEAR, HZ - SPAWN_CLEAR)
	if absf(absf(x) - CRATES_X) < CRATE_HALF + SPAWN_CLEAR:  # in a crate column: step out along x
		for cz in CRATES_Z:
			if absf(z - float(cz)) < CRATE_HALF + SPAWN_CLEAR:
				x = side * (CRATES_X + CRATE_HALF + SPAWN_CLEAR)  # the hull side of the crates: open floor
	return Vector3(x, p.y, z)

func spawn_points(team: int) -> Array:
	var out: Array = []
	for p in SPAWNS[team]:
		out.append(Vector3(p.x, 0.0, p.y))
	return out

func ground_y(_x: float, _z: float) -> float:
	return 0.0

func minimap_outline() -> PackedVector2Array:
	return PackedVector2Array([Vector2(-HX, -HZ), Vector2(HX, -HZ), Vector2(HX, HZ), Vector2(-HX, HZ)])

func _panel_texture(base: Color, seam: Color) -> ImageTexture:
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	img.fill(base)
	for i in 64:
		for e in [0, 32]:
			img.set_pixel(i, e, seam)
			img.set_pixel(e, i, seam)
	for e in [8, 56]:  # vents / fastener rows
		for i in range(12, 52, 4):
			img.set_pixel(i, e, seam)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

func _mat(c: Color, tex: Texture2D = null, scale := 6.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.55
	if tex != null:
		m.albedo_texture = tex
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS  # T440: crisp texels
		m.uv1_triplanar = true
		m.uv1_scale = Vector3.ONE / scale
	return m

func _glow(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 1.2
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

# The x / z spans between corridors: [lo, hi] pairs inside the hull.
static func _spans(lines: Array, half: float) -> Array:
	var out: Array = []
	var lo := -half
	for c in lines:
		out.append([lo, float(c) - W * 0.5])
		lo = float(c) + W * 0.5
	out.append([lo, half])
	return out

func _open(xs: Array, zs: Array) -> bool:
	var cx := (float(xs[0]) + float(xs[1])) * 0.5
	var cz := (float(zs[0]) + float(zs[1])) * 0.5
	if absf(cx) > 70.0 * S:  # the end columns: spawn halls
		return true
	if absf(cx) < 1.0 and absf(cz) < 20.0 * S:  # centre column, inner rows: the reactor room
		return true
	if absf(absf(cx) - 40.0 * S) < 1.0 and absf(cz) > 35.0 * S:  # beacon alcoves off the outer corridors
		return true
	return false

func build() -> void:
	var sun := get_parent().get_node_or_null("Sun") as DirectionalLight3D
	if sun != null:
		sun.shadow_enabled = false  # indoors: the ceiling would black out "FULL" shadows; the sun is the overhead light
	var env := own_environment()
	if env != null:
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color("#05070a")
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color("#dfe6ee")
		env.ambient_light_energy = 0.8
		env.fog_enabled = false
	_wall_mat = _mat(Color.WHITE, _panel_texture(Color("#d8dce0"), Color("#9aa1a8")), 4.0)
	var floor_mat := _mat(Color.WHITE, _panel_texture(Color("#6c727a"), Color("#4a4f55")), 4.0)
	var ceil_mat := _mat(Color.WHITE, _panel_texture(Color("#c2c7cc"), Color("#8e959c")), 4.0)
	_box(Vector3(HX * 2.0 + 4.0, 1.0, HZ * 2.0 + 4.0), Vector3(0, -0.5, 0), floor_mat)
	_box(Vector3(HX * 2.0 + 4.0, 1.0, HZ * 2.0 + 4.0), Vector3(0, H + 0.5, 0), ceil_mat)
	for s in [-1.0, 1.0]:  # hull walls
		_box(Vector3(HX * 2.0 + 4.0, H, 2.0), Vector3(0, H * 0.5, s * (HZ + 1.0)), _wall_mat)
		_box(Vector3(2.0, H, HZ * 2.0), Vector3(s * (HX + 1.0), H * 0.5, 0), _wall_mat)
	var xs_all := _spans(COLS, HX)
	var zs_all := _spans(ROWS, HZ)
	for xs in xs_all:
		for zs in zs_all:
			if _open(xs, zs):
				continue
			var sx := float(xs[1]) - float(xs[0])
			var sz := float(zs[1]) - float(zs[0])
			var c := Vector3((float(xs[0]) + float(xs[1])) * 0.5, H * 0.5, (float(zs[0]) + float(zs[1])) * 0.5)
			_box(Vector3(sx, H, sz), c, _wall_mat)
			_ribs(c, sx, sz)
	_frames(xs_all, zs_all)
	_lights()
	_dressing()

# Visual frame ribs every 8 m along a block's faces (0.15 m proud: mechs never catch on them).
func _ribs(c: Vector3, sx: float, sz: float) -> void:
	var rib := _mat(Color("#a9b0b7"))
	for face in [[Vector3(0, 0, 1), sx], [Vector3(0, 0, -1), sx], [Vector3(1, 0, 0), sz], [Vector3(-1, 0, 0), sz]]:
		var n: Vector3 = face[0]
		var length: float = face[1]
		var along := Vector3(absf(n.z), 0, absf(n.x))
		var half_depth := (sz if n.z != 0.0 else sx) * 0.5
		var k := -length * 0.5 + 4.0
		while k < length * 0.5 - 2.0:
			var p := c + n * (half_depth + 0.075) + along * k
			_box(Vector3(0.15 + along.x * 0.85, H, 0.15 + along.z * 0.85), Vector3(p.x, H * 0.5, p.z), rib, false)
			k += 8.0

# T554 (user 2026-11-25: "Corvette frames are good. Maybe some accent colors, don't change the whole
# aesthetic (red highlights)"): door frames at the junctions -- a heavy dark post on every wall-block
# corner with a red glow edge, and a dark header with a red underside across each corridor stretch that
# is walled on both sides (the centre corridor's doorways). Visual only, <= 0.2 m proud like the ribs:
# collision, nav and spawns are untouched; one MultiMesh per material = 2 draws for all of them.
func _frames(xs_all: Array, zs_all: Array) -> void:
	var dark: Array[Transform3D] = []
	var red: Array[Transform3D] = []
	for xs in xs_all:
		for zs in zs_all:
			if _open(xs, zs):
				continue
			for cx in xs:
				for cz in zs:
					var out := Vector3(signf(float(cx) - (float(xs[0]) + float(xs[1])) * 0.5), 0.0,
						signf(float(cz) - (float(zs[0]) + float(zs[1])) * 0.5))
					if absf(float(cx)) >= HX - 0.01 or absf(float(cz)) >= HZ - 0.01:
						continue  # against the hull: no junction there
					var corner := Vector3(float(cx), H * 0.5, float(cz))
					dark.append(Transform3D(Basis.from_scale(Vector3(0.6, H, 0.6)), corner - out * 0.15))
					red.append(Transform3D(Basis.from_scale(Vector3(0.12, H - 1.0, 0.12)), corner + out * 0.13))
	# headers: a long-corridor stretch (between two cross corridors) with blocks on both sides
	for j in ROWS.size():
		for xs in xs_all:
			if _open(xs, zs_all[j]) or _open(xs, zs_all[j + 1]):
				continue
			for x in xs:
				if absf(float(x)) >= HX - 0.01:
					continue
				var at := Vector3(float(x), H - 0.35, float(ROWS[j]))
				dark.append(Transform3D(Basis.from_scale(Vector3(0.6, 0.7, W)), at))
				red.append(Transform3D(Basis.from_scale(Vector3(0.25, 0.05, W - 0.6)), at - Vector3(0, 0.375, 0)))
	_multi(dark, _mat(Color("#2b3037")))
	_multi(red, _glow(Color("#c03030")))

func _multi(xforms: Array[Transform3D], mat: Material) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = BoxMesh.new()  # 1 m cube, scaled per instance
	mm.instance_count = xforms.size()
	for k in xforms.size():
		mm.set_instance_transform(k, xforms[k])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	add_child(mmi)

# Light strips down every corridor's centre line under the ceiling, and over the halls.
func _lights() -> void:
	var lamp := _glow(Color("#e8f4ff"))
	for z in ROWS:
		_box(Vector3(HX * 2.0 - 4.0, 0.1, 1.2), Vector3(0, H - 0.06, z), lamp, false)
	for x in COLS:
		_box(Vector3(1.2, 0.1, HZ * 2.0 - 4.0), Vector3(x, H - 0.06, 0), lamp, false)
	var stripe := _glow(Color("#c03030"))
	for s in [-1.0, 1.0]:  # red door-frame stripes where the halls open onto the corridors
		_box(Vector3(0.3, 0.3, HZ * 2.0), Vector3(s * 70.0 * S, H - 0.4, 0), stripe, false)

# Cover: consoles in the reactor room, crates and pillars in the spawn halls, a console
# in each beacon alcove -- >= 9 m from walls and each other, beacons and spawns clear.
func _dressing() -> void:
	var console := _mat(Color("#3a4048"))
	var crate := _mat(Color("#8a8f96"), _panel_texture(Color("#8a8f96"), Color("#5c6168")), 2.0)
	var core := _glow(Color("#5ab0ff"))
	for s in [-1.0, 1.0]:
		_box(Vector3(6, 1.4, 2), Vector3(0, 0.7, s * 18.0 * S), console)
		_box(Vector3(5.5, 0.1, 1.4), Vector3(0, 1.45, s * 18.0 * S), core, false)
		for t in [-1.0, 1.0]:
			_box(Vector3(2.4, 2.4, 2.4), Vector3(s * 74.0 * S, 1.2, t * 12.0 * S), crate)  # hall pillars of crates
			_box(Vector3(2.4, 4.8, 2.4), Vector3(s * 74.0 * S, 2.4, t * 38.0 * S), crate)
			_box(Vector3(4, 1.2, 1.6), Vector3(s * 40.0 * S, 0.6, t * (HZ - 0.8)), console)  # alcove consoles flush on the hull wall (no slot behind)
