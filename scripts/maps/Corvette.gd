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

const HX := 92.0                # hull half length (x)
const HZ := 46.0                # hull half width (z)
const H := 10.0                 # ceiling height
const W := 11.0                 # corridor width
const ROWS := [-30.0, 0.0, 30.0]          # corridor centre lines along x (z values)
const COLS := [-60.0, -20.0, 20.0, 60.0]  # cross corridor centre lines along z (x values)
const BEACONS := [Vector2(0, 0), Vector2(-40, -37), Vector2(40, -37), Vector2(-40, 37), Vector2(40, 37)]
const SPAWNS := [[Vector2(-80, -25), Vector2(-82, 0), Vector2(-80, 25)],
	[Vector2(80, -25), Vector2(82, 0), Vector2(80, 25)]]

var _wall_mat: StandardMaterial3D

func _init() -> void:
	center = Vector2.ZERO
	minimap_half = HX + 4.0

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
	return ImageTexture.create_from_image(img)

func _mat(c: Color, tex: Texture2D = null, scale := 6.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.55
	if tex != null:
		m.albedo_texture = tex
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
	if absf(cx) > 70.0:  # the end columns: spawn halls
		return true
	if absf(cx) < 1.0 and absf(cz) < 20.0:  # centre column, inner rows: the reactor room
		return true
	if absf(absf(cx) - 40.0) < 1.0 and absf(cz) > 35.0:  # beacon alcoves off the outer corridors
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

# Light strips down every corridor's centre line under the ceiling, and over the halls.
func _lights() -> void:
	var lamp := _glow(Color("#e8f4ff"))
	for z in ROWS:
		_box(Vector3(HX * 2.0 - 4.0, 0.1, 1.2), Vector3(0, H - 0.06, z), lamp, false)
	for x in COLS:
		_box(Vector3(1.2, 0.1, HZ * 2.0 - 4.0), Vector3(x, H - 0.06, 0), lamp, false)
	var stripe := _glow(Color("#c03030"))
	for s in [-1.0, 1.0]:  # red door-frame stripes where the halls open onto the corridors
		_box(Vector3(0.3, 0.3, HZ * 2.0), Vector3(s * 70.0, H - 0.4, 0), stripe, false)

# Cover: consoles in the reactor room, crates and pillars in the spawn halls, a console
# in each beacon alcove -- >= 9 m from walls and each other, beacons and spawns clear.
func _dressing() -> void:
	var console := _mat(Color("#3a4048"))
	var crate := _mat(Color("#8a8f96"), _panel_texture(Color("#8a8f96"), Color("#5c6168")), 2.0)
	var core := _glow(Color("#5ab0ff"))
	for s in [-1.0, 1.0]:
		_box(Vector3(6, 1.4, 2), Vector3(0, 0.7, s * 18.0), console)
		_box(Vector3(5.5, 0.1, 1.4), Vector3(0, 1.45, s * 18.0), core, false)
		for t in [-1.0, 1.0]:
			_box(Vector3(2.4, 2.4, 2.4), Vector3(s * 74.0, 1.2, t * 12.0), crate)  # hall pillars of crates
			_box(Vector3(2.4, 4.8, 2.4), Vector3(s * 74.0, 2.4, t * 38.0), crate)
			_box(Vector3(4, 1.2, 1.6), Vector3(s * 40.0, 0.6, t * (HZ - 0.8)), console)  # alcove consoles flush on the hull wall (no slot behind)
