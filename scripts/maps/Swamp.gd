extends MapScene
# T225: swamp. ~260 m of murky water over a mud bottom (wading depth, <= 0.6 m) between dry
# hummocks; mechs in the water slow to WADE of their speed (Mech.terrain_speed, stepped
# here every tick from height vs the surface -- same on every peer, so server and a
# predicting client agree; T233: ramps in over 5 s, out over 2 s). Raised plank boardwalks link hummocks (boarded from the dry ground: full
# speed lanes), dead trees, a sunken ruin in the middle, low fog. Point-symmetric
# (x, z) -> (-x, -z): team 0 west, team 1 east; 5 beacons (V18), 3 spawns each.

const HALF := 130.0
const WATER_Y := 0.0
const WADE := 0.55
const BEACONS := [Vector2(0, 0), Vector2(-70, 55), Vector2(70, -55), Vector2(-70, -55), Vector2(70, 55)]
const SPAWNS := [[Vector2(-112, -35), Vector2(-116, 0), Vector2(-112, 35)],
	[Vector2(112, 35), Vector2(116, 0), Vector2(112, -35)]]
# dry hummocks [centre, radius]; mirrored through the centre
const HUMMOCKS := [[Vector2(-40, 20), 12.0], [Vector2(-30, -45), 10.0], [Vector2(-95, 85), 13.0],
	[Vector2(-15, 90), 11.0], [Vector2(-100, -90), 12.0], [Vector2(-55, -100), 9.0]]
const BOARDWALKS := [[Vector2(-40, 20), Vector2(-70, 55)], [Vector2(-30, -45), Vector2(-70, -55)],
	[Vector2(-40, 20), Vector2(0, 0)], [Vector2(-15, 90), Vector2(-70, 55)]]
const MUD := Color("#3d3424")
const MURK := Color(0.15, 0.17, 0.09)  # T250: swamp water colour
const MURK_ALPHA := 0.94
const GRASS := Color("#4f5a2e")

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

func _dry_spots() -> Array:
	var out: Array = []
	for h in HUMMOCKS:
		out.append(h)
		out.append([-(h[0] as Vector2), h[1]])
	for b in BEACONS:
		out.append([b, 13.0])
	for team in SPAWNS:
		for s in team:
			out.append([s, 22.0])
	return out

func ground_y(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var mud := WATER_Y - 0.45 + 0.15 * sin(x * 0.07) * cos(z * 0.06)  # wading depth
	var dry := mud
	for d in _dry_spots():
		var k := smoothstep(float(d[1]) + 6.0, float(d[1]), p.distance_to(d[0]))
		dry = lerpf(dry, WATER_Y + 0.6, k)
	return dry

func _mat(c: Color, rough := 0.95) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m

func _box(size: Vector3, pos: Vector3, mat: Material, rot := Vector3.ZERO, collide := true) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	if not collide:
		mi.position = pos
		mi.rotation = rot
		add_child(mi)
		return
	var body := StaticBody3D.new()
	body.position = pos
	body.rotation = rot
	var col := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	col.shape = bs
	body.add_child(col)
	body.add_child(mi)
	add_child(body)

func build() -> void:
	make_terrain(HALF, 2.0, func(x: float, z: float, y: float) -> Color:
		return MUD.lerp(GRASS, clampf((y - WATER_Y) * 2.0, 0.0, 1.0)), 225)
	make_boundary(HALF)
	var env := own_environment()
	if env != null:
		env.fog_enabled = true
		env.fog_light_color = Color("#4b5440")
		env.fog_density = 0.012
		env.ambient_light_color = Color("#8a9475")
		env.ambient_light_energy = 0.55
	var water := MeshInstance3D.new()  # the surface (visual; wading is Mech.terrain_speed)
	var pm := PlaneMesh.new()
	pm.size = Vector2(HALF * 2.0, HALF * 2.0)
	water.mesh = pm
	var wm := StandardMaterial3D.new()
	# T250 (HUMAN_FOUND_ISSUES 2026-11-05: "make swamp water murkier"): darker, browner,
	# barely see-through (was 0.22/0.26/0.17 at 82% opacity, glossy 0.15)
	wm.albedo_color = Color(MURK.r, MURK.g, MURK.b, MURK_ALPHA)
	wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wm.roughness = 0.45
	water.material_override = wm
	water.position.y = WATER_Y
	add_child(water)
	var plank := _mat(Color("#5b4630"))
	for bw in BOARDWALKS:
		for s in [1.0, -1.0]:
			_boardwalk(bw[0] * s, bw[1] * s, plank)
	_sunken_ruin()
	var rng := RandomNumberGenerator.new()
	rng.seed = 225
	var dead := _mat(Color("#4a4238"))
	var placed: Array = []
	for k in 120:
		var p := Vector2(rng.randf_range(-HALF + 10, HALF - 10), rng.randf_range(-HALF + 10, HALF - 10))
		if not _clear(p, placed):
			continue
		var h := rng.randf_range(8, 18)
		var lean := Vector3(rng.randf_range(-0.15, 0.15), rng.randf() * PI, rng.randf_range(-0.15, 0.15))
		for q in [p, -p]:
			placed.append(q)
			_dead_tree(q, h, lean if q == p else Vector3(-lean.x, lean.y + PI, -lean.z), dead)
	_shore_dressing()
	_fireflies()

# T446 (user 2026-11-17: yes to Swamp's dressing, "keep the moody fog"): reeds along the water's
# edge, lily pads out on the water, moss on the dead trees, fireflies over it all. The fog is not
# touched. Visual only (no colliders: wading and paths unchanged), from its own RNG (the tree
# layout's draws stay put), merged per material (T424); the fireflies are one particle system,
# off with GRAPHICS > AMBIENT EFFECTS.
var _moss: StandardMaterial3D = _mat(Color("#55603f"))
const REED_COLS := [Color("#6b7443"), Color("#857c4c")]
const PAD := Color("#3a5228")

func _shore_dressing() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2251
	var reeds := [_mat(REED_COLS[0]), _mat(REED_COLS[1])]
	var pad := _mat(PAD, 0.6)
	for gx in range(-HALF + 6, HALF - 6, 3):
		for gz in range(-HALF + 6, HALF - 6, 3):
			var p := Vector2(gx + rng.randf_range(-1.2, 1.2), gz + rng.randf_range(-1.2, 1.2))
			var roll := rng.randf()
			if not _dress_clear(p):
				continue
			var g := ground_y(p.x, p.y)
			if absf(g - WATER_Y) < 0.18 and roll < 0.45:  # the water's edge
				for k in 5:
					var mi := MeshInstance3D.new()
					var bm := BoxMesh.new()
					bm.size = Vector3(0.09, rng.randf_range(1.2, 2.2), 0.09)
					mi.mesh = bm
					mi.material_override = reeds[k % 2]
					var o := Vector2(rng.randf_range(-0.6, 0.6), rng.randf_range(-0.6, 0.6))
					mi.position = Vector3(p.x + o.x, g + bm.size.y * 0.5 - 0.15, p.y + o.y)
					mi.rotation = Vector3(rng.randf_range(-0.15, 0.15), 0, rng.randf_range(-0.15, 0.15))
					add_child(mi)
			elif g < WATER_Y - 0.25 and roll < 0.022:  # open water
				for k in 3:
					var mi := MeshInstance3D.new()
					var cm := CylinderMesh.new()
					var r := rng.randf_range(0.45, 0.9)
					cm.top_radius = r
					cm.bottom_radius = r
					cm.height = 0.03
					cm.radial_segments = 8
					cm.rings = 1
					mi.mesh = cm
					mi.material_override = pad
					mi.position = Vector3(p.x + rng.randf_range(-1.5, 1.5), WATER_Y + 0.02 + k * 0.004, p.y + rng.randf_range(-1.5, 1.5))
					add_child(mi)

## Dressing stays off the beacon rings, spawns and boardwalk decks (it would poke through them).
func _dress_clear(p: Vector2) -> bool:
	for b in BEACONS:
		if p.distance_to(b) < Beacon.CIRCLE_RADIUS + 2.0:
			return false
	for team in SPAWNS:
		for s in team:
			if p.distance_to(s) < 12.0:
				return false
	for bw in BOARDWALKS:
		for s in [1.0, -1.0]:
			var a: Vector2 = bw[0] * s
			var b: Vector2 = bw[1] * s
			var t := clampf((p - a).dot(b - a) / (b - a).length_squared(), 0.0, 1.0)
			if p.distance_to(a + (b - a) * t) < 5.5:  # half the deck + a pad cluster's spread
				return false
	return true

func _fireflies() -> void:
	if not Game.settings.get("map_effects", true) or DisplayServer.get_name() == "headless":
		return
	var fx := CPUParticles3D.new()
	fx.name = "Fireflies"
	fx.amount = 160
	fx.lifetime = 7.0
	fx.preprocess = 7.0
	fx.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	fx.emission_box_extents = Vector3(HALF - 10.0, 1.6, HALF - 10.0)
	fx.position.y = WATER_Y + 2.2
	fx.direction = Vector3.UP
	fx.spread = 180.0
	fx.gravity = Vector3.ZERO
	fx.initial_velocity_min = 0.1
	fx.initial_velocity_max = 0.4
	var fade := Curve.new()  # blink in, glow, blink out
	fade.add_point(Vector2(0.0, 0.0))
	fade.add_point(Vector2(0.2, 1.0))
	fade.add_point(Vector2(0.7, 1.0))
	fade.add_point(Vector2(1.0, 0.0))
	fx.scale_amount_curve = fade
	var q := QuadMesh.new()
	q.size = Vector2(0.14, 0.14)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_color = Color(0.85, 1.0, 0.45)
	m.disable_fog = true  # they glow through the murk instead of vanishing in it
	q.material = m
	fx.mesh = q
	add_child(fx)

func _clear(p: Vector2, placed: Array) -> bool:
	for b in BEACONS:
		if p.distance_to(b) < 18.0:
			return false
	for team in SPAWNS:
		for s in team:
			if p.distance_to(s) < 30.0:
				return false
	for q in placed:
		if p.distance_to(q) < 10.0:
			return false
	if p.length() < 26.0:  # the ruin
		return false
	for bw in BOARDWALKS:  # keep the walkways (both mirrors) clear
		for s in [1.0, -1.0]:
			var a: Vector2 = bw[0] * s
			var b: Vector2 = bw[1] * s
			var t := clampf((p - a).dot(b - a) / (b - a).length_squared(), 0.0, 1.0)
			if p.distance_to(a + (b - a) * t) < 8.0:
				return false
	return true

# Planks on a box collider, deck at WATER_Y + DECK_TOP: a 0.1 m step up from the hummocks'
# dry ground (T232: flush with it, the deck z-fought the ground and flickered); from the
# water it's a ledge.
const DECK_TOP := 0.7
func _boardwalk(a: Vector2, b: Vector2, mat: Material) -> void:
	var mid := (a + b) * 0.5
	var length := a.distance_to(b)
	var yaw := atan2(b.x - a.x, b.y - a.y)
	_box(Vector3(4.0, 0.3, length), Vector3(mid.x, WATER_Y + DECK_TOP - 0.15, mid.y), mat, Vector3(0, yaw, 0))
	var dir := (b - a).normalized()
	var side := Vector2(-dir.y, dir.x)
	var n := int(length / 6.0)
	for k in n + 1:  # posts (visual)
		var p := a + dir * (length * k / maxf(1.0, n))
		for sd in [1.6, -1.6]:
			var q: Vector2 = p + side * float(sd)
			_box(Vector3(0.3, 1.4, 0.3), Vector3(q.x, WATER_Y - 0.2, q.y), mat, Vector3.ZERO, false)

func _dead_tree(p: Vector2, h: float, lean: Vector3, mat: Material) -> void:
	var body := StaticBody3D.new()
	body.position = Vector3(p.x, ground_y(p.x, p.y) - 0.3, p.y)
	body.rotation = lean
	var col := CollisionShape3D.new()
	var cs := CapsuleShape3D.new()  # V59: no cylinders
	cs.radius = 0.6
	cs.height = h
	col.shape = cs
	col.position.y = h * 0.5
	body.add_child(col)
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.2
	cm.bottom_radius = 0.7
	cm.height = h
	mi.mesh = cm
	mi.material_override = mat
	mi.position.y = h * 0.5
	body.add_child(mi)
	for k in 3:  # bare branches (visual)
		var br := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.25, h * 0.3, 0.25)
		br.mesh = bm
		br.material_override = mat
		br.position = Vector3(0, h * (0.55 + 0.12 * k), 0)
		br.rotation = Vector3(0.9, k * 2.1, 0)
		body.add_child(br)
		# T446: a strand of moss hanging from the branch's tip (visual), length by branch
		var tip := br.position + Basis.from_euler(br.rotation) * Vector3(0, h * 0.15, 0)
		var moss := MeshInstance3D.new()
		var mm := BoxMesh.new()
		mm.size = Vector3(0.35, 1.4 + k * 0.8, 0.06)
		moss.mesh = mm
		moss.material_override = _moss
		moss.position = tip - Vector3(0, mm.size.y * 0.5 - 0.1, 0)
		moss.rotation.y = k * 2.1
		body.add_child(moss)
	add_child(body)

# A sunken concrete hulk at the centre: tilted wall slabs half in the water, gaps >= 9 m.
# T416 (user 2026-11-16: bots stuck "at an intersection of walkway and wall near the center beacon"):
# the side slabs were 14 m long at z -4 and stood across the two centre boardwalks at (+-16.6, +-8.3);
# now 7 m at z 0, ~3 m clear of the deck (probe swamp_walkways).
func _sunken_ruin() -> void:
	var conc := _mat(Color("#6b6a62"))
	for s in [1.0, -1.0]:
		_box(Vector3(18, 7, 1.2), Vector3(-6 * s, 1.5, 15 * s), conc, Vector3(0.25 * s, 0.3, 0.1))
		_box(Vector3(1.2, 6, 7), Vector3(17 * s, 1.0, 0.0), conc, Vector3(0, 0.2, 0.22 * s))
		# T439: the low edge sits 0.4 m into the mud (was at y 2.6 with its lowest corner in the air)
		var rot := Vector3(0.4 * s, 0, 0.15)
		_box(Vector3(9, 0.8, 7), Vector3(13 * s, ground_min(13 * s, 16 * s, 5.0) - 0.4 - box_low(Vector3(9, 0.8, 7), rot), 16 * s), conc, rot)

# T233 (HUMAN_FOUND_ISSUES 2026-11-04): wading is a status effect -- the slow builds from
# none to WADE over WADE_IN_S in the water and wears off over WADE_OUT_S out of it (user:
# 2 s). The state is Mech.terrain_speed itself, stepped every physics tick on every peer.
const WADE_IN_S := 5.0
const WADE_OUT_S := 2.0

func _physics_process(delta: float) -> void:
	# T225: wading. Mech origin = its feet; under the surface -> slowing.
	for m in get_tree().get_nodes_in_group("mechs"):
		var wet: bool = (m as Node3D).global_position.y < WATER_Y - 0.05
		var rate := (1.0 - WADE) / (WADE_IN_S if wet else WADE_OUT_S)
		m.set("terrain_speed", move_toward(float(m.get("terrain_speed")), WADE if wet else 1.0, rate * delta))
