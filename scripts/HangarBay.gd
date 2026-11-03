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
var _drones: Array = []     # [node, base y, phase]
var _parts: Array = []      # conveyor parts
var _status_light: StandardMaterial3D
var _t := 0.0

func _ready() -> void:
	_room()
	for i in BAYS:
		_bay(i, (float(i) - (BAYS - 1) * 0.5) * SPACING)
	_conveyor()
	_deck()

## Tint bay i's floor pool with its mech's accent (Hangar calls this as the squad changes).
func set_bay_mech(i: int, mech_name: String) -> void:
	if i >= 0 and i < _pools.size():
		var c: Color = ACCENTS.get(mech_name, Color("#8899aa"))
		(_pools[i] as StandardMaterial3D).albedo_color = Color(c.r, c.g, c.b, 0.45)

func _process(delta: float) -> void:
	_t += delta
	for d in _drones:
		(d[0] as Node3D).position.y = float(d[1]) + sin(_t * 2.1 + float(d[2])) * 0.08
	for p in _parts:
		var n: Node3D = p
		n.position.x += delta * 0.9
		if n.position.x > 12.0:
			n.position.x -= 24.0
	if _status_light != null:
		_status_light.emission_energy_multiplier = 0.4 + 2.6 * maxf(0.0, sin(_t * 2.9))

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

func _box(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	add_child(mi)
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
	for side in [-1.0, 1.0]:  # umbilical cables, beam -> mech back
		_cable(Vector3(x + side * 0.9, beam_y - 0.1, -1.0), Vector3(x + side * 0.45, 1.9, -0.55), 0.5)
	if repairing:
		_welder(Vector3(x + 1.05, 2.45, 0.35), -1.0)

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

func _welder(pos: Vector3, facing: float) -> void:
	var drone := Node3D.new()
	drone.position = pos
	drone.scale = Vector3.ONE * 1.6  # readable at the lineup's size
	add_child(drone)
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.42, 0.22, 0.36)
	body.mesh = bm
	body.material_override = _mat(STEEL_3)
	drone.add_child(body)
	for side in [-1.0, 1.0]:  # rotor pods
		var pod := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(0.16, 0.06, 0.16)
		pod.mesh = pm
		pod.position = Vector3(side * 0.3, 0.12, 0)
		pod.material_override = _mat(STEEL_2)
		drone.add_child(pod)
	var eye := MeshInstance3D.new()
	var em := BoxMesh.new()
	em.size = Vector3(0.12, 0.05, 0.02)
	eye.mesh = em
	eye.position = Vector3(0, 0.02, 0.19)
	eye.material_override = _mat(Color("#ffd27a"), true, 3.0)
	drone.add_child(eye)
	var arm := MeshInstance3D.new()  # torch arm reaching to the hull
	var am := BoxMesh.new()
	am.size = Vector3(0.45, 0.05, 0.05)
	arm.mesh = am
	arm.position = Vector3(facing * 0.36, -0.12, 0.05)
	arm.rotation_degrees = Vector3(0, 0, facing * -25.0)
	arm.material_override = _mat(STEEL_2)
	drone.add_child(arm)
	var sparks := CPUParticles3D.new()
	sparks.position = Vector3(facing * 0.58, -0.24, 0.05)
	sparks.amount = 24
	sparks.lifetime = 0.55
	sparks.explosiveness = 0.15
	sparks.direction = Vector3(facing * 0.4, -1, 0.3)
	sparks.spread = 55.0
	sparks.initial_velocity_min = 1.2
	sparks.initial_velocity_max = 2.6
	sparks.gravity = Vector3(0, -6.0, 0)
	var spark_mesh := BoxMesh.new()
	spark_mesh.size = Vector3(0.035, 0.035, 0.035)
	spark_mesh.material = _mat(Color("#fff3c4"), true, 6.0)
	sparks.mesh = spark_mesh
	drone.add_child(sparks)
	var flash := OmniLight3D.new()  # the weld's glow on the hull
	flash.position = sparks.position
	flash.light_color = Color("#ffd27a")
	flash.light_energy = 1.4
	flash.omni_range = 1.6
	drone.add_child(flash)
	_drones.append([drone, pos.y, randf() * TAU])

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
