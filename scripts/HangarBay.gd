extends Node3D
# T208: the hangar's repair bay (design/ui_kits/game/hangar-screen.jsx "REPAIR BAY"),
# built around the 5-mech lineup (Hangar._setup_lineup_viewport: mechs at x = -6..6, 3 m
# apart, orthographic camera from +z). Per bay: gantry with a downlight (warm over the
# bays under repair, cool over the ready ones) and its light shaft, a floor light pool in
# the mech's accent, two umbilical cables. Welder drones hover over the bays under repair
# throwing sparks; parts ride a conveyor along the back wall; an observation deck with a
# lit window and a blinking status light sits high on the left. Dark steel palette from
# the design (#0c0e13 .. #2a2e37).

const SPACING := 3.0
const BAYS := 5
const REPAIRING := [2, 4]  # the design's squad: bays 3 and 5 under repair (welders)
const ACCENTS := {  # design accents (mech-bay.js) + matching ones for the rest of the roster
	"Slip": Color("#1AD9FF"), "Cesh": Color("#8fb083"), "Hornet": Color("#99CCFF"),
	"Vesuvius": Color("#FF590D"), "Seeker": Color("#C77DFF"), "Hippogriff": Color("#FFD27A"),
	"Pegasus": Color("#7CFFB2"), "Kestrel": Color("#FF6A9E"), "Everest": Color("#B8C4D6"),
}
const STEEL_0 := Color("#0c0e13")
const STEEL_1 := Color("#14161d")
const STEEL_2 := Color("#20232b")
const STEEL_3 := Color("#2a2e37")

var _pools: Array = []      # floor light pool materials, per bay
var _parts: Array = []      # conveyor parts
var _status_light: StandardMaterial3D
var _t := 0.0
# T254 (HUMAN_FOUND_ISSUES 2026-11-05: "fancy hangar ... copy more of Design's animation,
# the flying drones, conveyor belts"; under GRAPHICS > FANCY HANGAR, Game.settings
# fancy_hangar): from hangar-screen.jsx -- RepairDroneSwarm (drones roam mech to mech, a
# new target each trip, sparking while they hover), the treads scrolling under the belt
# (mbTread), robot arms swinging over it (mbArm), the repairing bays' downlights
# flickering (mbFlicker) and their pools pulsing (mbPulse). Off = the T208 bay.
var fancy := true
var _swarm: Array = []        # [node, from, to, t]
var _arms: Array = []         # [pivot, phase]
var _tread: StandardMaterial3D = null
var _repair_spots: Array = [] # SpotLight3D over the bays under repair
var _repair_pools: Array = [] # their pool materials
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	fancy = bool(Game.settings.get("fancy_hangar", true))
	_rng.seed = 254
	_room()
	for i in BAYS:
		_bay(i, (float(i) - (BAYS - 1) * 0.5) * SPACING)
	_conveyor()
	_deck()
	if fancy:
		_fancy()

## Tint bay i's floor pool with its mech's accent (Hangar calls this as the squad changes).
func set_bay_mech(i: int, mech_name: String) -> void:
	if i >= 0 and i < _pools.size():
		var c: Color = ACCENTS.get(mech_name, Color("#8899aa"))
		(_pools[i] as StandardMaterial3D).albedo_color = Color(c.r, c.g, c.b, 0.45)

func _process(delta: float) -> void:
	_t += delta
	for p in _parts:
		var n: Node3D = p
		n.position.x += delta * 0.9
		if n.position.x > 12.0:
			n.position.x -= 24.0
	if _status_light != null:
		_status_light.emission_energy_multiplier = 0.4 + 2.6 * maxf(0.0, sin(_t * 2.9))
	if fancy:
		_animate_fancy(delta)

# ---- building blocks ----

func _mat(c: Color, emissive := false, energy := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.75
	m.metallic = 0.35
	if emissive:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = energy
	return m

func _glow_mat(c: Color) -> StandardMaterial3D:  # additive, unshaded: light shafts, pools
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = c
	return m

func _box(size: Vector3, pos: Vector3, mat: Material, parent: Node = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	(parent if parent != null else self).add_child(mi)  # T254: drone / arm parts go on their node
	return mi

func _grate_texture() -> ImageTexture:
	var img := Image.create(16, 16, false, Image.FORMAT_RGB8)
	img.fill(STEEL_1)
	for k in 16:
		img.set_pixel(k, 0, STEEL_3)
		img.set_pixel(0, k, STEEL_3)
		img.set_pixel(k, 8, STEEL_2)
	return ImageTexture.create_from_image(img)

func _room() -> void:
	var floor_mat := _mat(Color.WHITE)
	floor_mat.albedo_texture = _grate_texture()
	floor_mat.uv1_scale = Vector3(24, 12, 1)
	floor_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_box(Vector3(26, 0.1, 14), Vector3(0, -0.05, -1.0), floor_mat)
	_box(Vector3(28, 10, 0.4), Vector3(0, 4.0, -5.2), _mat(Color("#151821")))
	for k in 10:  # wall ribs
		_box(Vector3(0.35, 10, 0.3), Vector3(-13.5 + k * 3.0, 4.0, -4.9), _mat(STEEL_2))
	_box(Vector3(28, 0.45, 0.6), Vector3(0, 5.2, -4.6), _mat(STEEL_3))   # girder
	_box(Vector3(28, 0.12, 0.2), Vector3(0, 0.6, -4.95), _mat(Color("#f7c948"), true, 0.25))  # hazard strip

func _bay(i: int, x: float) -> void:
	var repairing := i in REPAIRING
	var beam_y := 3.65  # the orthographic lineup camera shows up to ~4 m at the mechs
	for side in [-1.0, 1.0]:  # gantry posts + beam
		_box(Vector3(0.18, beam_y, 0.18), Vector3(x + side * 1.35, beam_y * 0.5, -1.4), _mat(STEEL_3))
	_box(Vector3(3.0, 0.22, 0.32), Vector3(x, beam_y, -1.4), _mat(STEEL_2))
	_box(Vector3(2.9, 0.16, 0.9), Vector3(x, beam_y, -0.9), _mat(STEEL_2))  # beam arm over the mech
	var warm := Color(1.0, 0.93, 0.78)
	var cool := Color(0.71, 0.82, 1.0)
	var light_c: Color = warm if repairing else cool
	_box(Vector3(0.7, 0.06, 0.4), Vector3(x, beam_y - 0.11, -0.6), _mat(light_c, true, 2.5))  # lamp face
	var spot := SpotLight3D.new()
	spot.position = Vector3(x, beam_y - 0.2, -0.6)
	spot.rotation_degrees = Vector3(-90, 0, 0)
	spot.light_color = light_c
	spot.light_energy = 4.0
	spot.spot_range = 7.0
	spot.spot_angle = 26.0
	add_child(spot)
	if repairing:
		_repair_spots.append(spot)
	var shaft := MeshInstance3D.new()  # the downlight cone, a faint shaft
	var cone := CylinderMesh.new()
	cone.top_radius = 0.25
	cone.bottom_radius = 1.5
	cone.height = beam_y - 0.2
	shaft.mesh = cone
	shaft.position = Vector3(x, (beam_y - 0.2) * 0.5, -0.6)
	shaft.material_override = _glow_mat(Color(light_c.r, light_c.g, light_c.b, 0.07 if repairing else 0.045))
	add_child(shaft)
	var pool := MeshInstance3D.new()  # floor light pool in the mech's accent
	var quad := PlaneMesh.new()
	quad.size = Vector2(3.0, 2.2)
	pool.mesh = quad
	pool.position = Vector3(x, 0.012, -0.2)
	var pm := _glow_mat(Color(0.53, 0.6, 0.67, 0.45))
	var grad := GradientTexture2D.new()
	grad.fill = GradientTexture2D.FILL_RADIAL
	grad.fill_from = Vector2(0.5, 0.5)
	grad.fill_to = Vector2(1.0, 0.5)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	grad.gradient = g
	pm.albedo_texture = grad
	pool.material_override = pm
	add_child(pool)
	_pools.append(pm)
	if repairing:
		_repair_pools.append(pm)
	for side in [-1.0, 1.0]:  # umbilical cables, beam -> mech back
		_cable(Vector3(x + side * 0.9, beam_y - 0.1, -1.0), Vector3(x + side * 0.45, 1.9, -0.55), 0.5)
	# T286 (HUMAN_FOUND 2026-11-05: "Remove the two big stationary drones in the hangar"): no
	# welder drones over the repair bays any more; the T254 swarm drones still roam.

func _cable(a: Vector3, b: Vector3, sag: float) -> void:
	var mat := _mat(STEEL_0)
	var n := 7
	var prev := a
	for k in range(1, n + 1):
		var t := float(k) / n
		var p := a.lerp(b, t) + Vector3.DOWN * sag * 4.0 * t * (1.0 - t)
		var seg := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.035
		cyl.bottom_radius = 0.035
		cyl.height = prev.distance_to(p) + 0.02
		seg.mesh = cyl
		seg.material_override = mat
		add_child(seg)
		seg.global_position = (prev + p) * 0.5
		var up := (p - prev).normalized()
		var side := up.cross(Vector3.FORWARD).normalized() if absf(up.dot(Vector3.FORWARD)) < 0.99 else Vector3.RIGHT
		seg.global_transform.basis = Basis(side, up, side.cross(up)).orthonormalized()
		prev = p

func _conveyor() -> void:
	var y := 1.75  # behind the mechs: parts show between the bays
	var z := -4.2
	_box(Vector3(28, 0.16, 0.55), Vector3(0, y, z), _mat(STEEL_1))
	_box(Vector3(28, 0.05, 0.6), Vector3(0, y + 0.1, z), _mat(Color("#0e1016")))
	for k in 14:  # hangers from the girder
		_box(Vector3(0.06, 0.8, 0.06), Vector3(-13.0 + k * 2.0, y + 0.55, z), _mat(STEEL_2))
	var rng := RandomNumberGenerator.new()
	rng.seed = 208
	for k in 12:  # mech and weapon parts on the belt
		var s := Vector3(rng.randf_range(0.3, 0.8), rng.randf_range(0.2, 0.5), rng.randf_range(0.25, 0.45))
		var part := _box(s, Vector3(-12.0 + k * 2.0 + rng.randf_range(-0.4, 0.4), y + 0.13 + s.y * 0.5, z),
			_mat([STEEL_3, Color("#3a3f4b"), Color("#4b3a2a")][k % 3]))
		_parts.append(part)

func _deck() -> void:
	var at := Vector3(-7.9, 3.0, -3.6)
	_box(Vector3(3.6, 1.6, 1.8), at, _mat(Color("#12141b")))
	_box(Vector3(2.4, 0.6, 0.05), at + Vector3(0.3, 0.05, 0.92), _mat(Color("#5a4a1c"), true, 0.35))  # dim lit window
	_box(Vector3(3.6, 0.05, 0.1), at + Vector3(0, 0.72, 0.92), _mat(Color("#f7c948"), true, 0.6))    # ceiling strip
	for k in 2:  # silhouettes in the window
		_box(Vector3(0.22, 0.5, 0.05), at + Vector3(-0.7 + k * 1.4, -0.12, 0.95), _mat(Color("#05060a")))
	_box(Vector3(2.6, 0.12, 0.12), at + Vector3(0.6, -1.15, -0.2), _mat(STEEL_2))  # strut
	_status_light = _mat(Color("#ff6a3d"), true, 2.0)
	_box(Vector3(0.12, 0.12, 0.12), at + Vector3(1.75, 0.85, 0.9), _status_light)

# ---- T254: fancy hangar ----

func _bay_x(i: int) -> float:
	return (float(i) - (BAYS - 1) * 0.5) * SPACING

func _hover_point(i: int) -> Vector3:  # beside a mech's head, in front of the gantry
	return Vector3(_bay_x(i) + _rng.randf_range(-0.9, 0.9), _rng.randf_range(2.2, 3.0), _rng.randf_range(0.2, 0.6))

func _fancy() -> void:
	for k in 3:  # the roaming swarm
		var d := Node3D.new()
		d.name = "SwarmDrone%d" % k
		d.scale = Vector3.ONE * 1.3
		add_child(d)
		_box(Vector3(0.34, 0.12, 0.26), Vector3.ZERO, _mat(STEEL_3), d)
		for sx in [-1.0, 1.0]:  # rotor pods
			_box(Vector3(0.12, 0.04, 0.12), Vector3(sx * 0.22, 0.06, 0), _mat(STEEL_2), d)
		_box(Vector3(0.06, 0.04, 0.03), Vector3(0, 0, 0.14), _mat(Color("#7fd0ff"), true, 3.0), d)
		var sparks := CPUParticles3D.new()
		sparks.amount = 10
		sparks.lifetime = 0.5
		sparks.direction = Vector3(0, -1, 0.3)
		sparks.spread = 40.0
		sparks.initial_velocity_min = 0.6
		sparks.initial_velocity_max = 1.6
		sparks.gravity = Vector3(0, -6, 0)
		sparks.scale_amount_min = 0.02
		sparks.scale_amount_max = 0.04
		sparks.color = Color("#ffd27a")
		sparks.position = Vector3(0, -0.08, 0.12)
		d.add_child(sparks)
		var start := _hover_point(_rng.randi() % BAYS)
		d.position = start
		_swarm.append([d, start, _hover_point(_rng.randi() % BAYS), 0.0, sparks])
	_tread = _mat(Color.WHITE)  # scrolling tread stripes on the belt top
	var img := Image.create(16, 2, false, Image.FORMAT_RGB8)
	for x in 16:
		for y in 2:
			img.set_pixel(x, y, Color("#151821") if x < 8 else Color("#0e1016"))
	_tread.albedo_texture = ImageTexture.create_from_image(img)
	_tread.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_tread.uv1_scale = Vector3(56, 1, 1)
	_box(Vector3(28, 0.02, 0.6), Vector3(0, 1.75 + 0.135, -4.2), _tread)
	for k in 3:  # robot arms swinging over the assembly line
		var pivot := Node3D.new()
		pivot.name = "AssemblyArm%d" % k
		pivot.position = Vector3(-6.0 + k * 6.0, 3.1, -4.2)
		add_child(pivot)
		_box(Vector3(0.3, 0.2, 0.3), Vector3.ZERO, _mat(STEEL_3), pivot)
		_box(Vector3(0.1, 1.0, 0.1), Vector3(0, -0.55, 0), _mat(STEEL_2), pivot)
		_box(Vector3(0.22, 0.08, 0.16), Vector3(0, -1.08, 0), _mat(Color("#f7c948"), true, 0.4), pivot)
		_arms.append([pivot, k * 1.7])

func _animate_fancy(delta: float) -> void:
	for d in _swarm:
		d[3] = float(d[3]) + delta / 2.6  # one trip ~2.6 s, then hover and spark
		var t: float = clampf(float(d[3]), 0.0, 1.0)
		var e := t * t * (3.0 - 2.0 * t)
		var n: Node3D = d[0]
		n.position = (d[1] as Vector3).lerp(d[2], e) + Vector3(0, sin(_t * 3.0 + float(d[3])) * 0.05 + sin(e * PI) * 0.6, 0)
		(d[4] as CPUParticles3D).emitting = t >= 1.0
		if float(d[3]) > 1.6:  # hovered ~1.5 s at this mech: off to another
			d[1] = n.position
			d[2] = _hover_point(_rng.randi() % BAYS)
			d[3] = 0.0
	for a in _arms:
		(a[0] as Node3D).rotation.z = deg_to_rad(-7.0 + 16.0 * (0.5 + 0.5 * sin(_t * TAU / 2.4 + float(a[1]))))
	if _tread != null:
		_tread.uv1_offset.x = fmod(_tread.uv1_offset.x - delta / 1.3, 1.0)
	for i in _repair_spots.size():
		var f := 1.0
		var c := fmod(_t + i * 1.3, 4.0) / 4.0  # mbFlicker: a dip near the middle of each 4 s
		if c > 0.47 and c < 0.53:
			f = 0.6 if c < 0.5 else 0.85
		(_repair_spots[i] as SpotLight3D).light_energy = 4.0 * f
	for i in _repair_pools.size():
		var m: StandardMaterial3D = _repair_pools[i]
		m.albedo_color.a = 0.45 * (0.7 + 0.3 * (0.5 + 0.5 * sin(_t * TAU / 2.6 + i)))
