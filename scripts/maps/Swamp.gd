extends MapScene
# T225: swamp. ~260 m of murky water over a mud bottom (wading depth, <= 0.6 m) between dry
# hummocks; mechs in the water move at WADE of their speed (Mech.terrain_speed, set here
# every tick from height vs the surface -- same on every peer, so server and a predicting
# client agree). Raised plank boardwalks link hummocks (boarded from the dry ground: full
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
	wm.albedo_color = Color(0.22, 0.26, 0.17, 0.82)
	wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wm.roughness = 0.15
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

# Planks on a box collider, deck at WATER_Y + 0.6 (= the hummocks' dry ground): you walk on
# from the hummocks; from the water it's a ledge.
func _boardwalk(a: Vector2, b: Vector2, mat: Material) -> void:
	var mid := (a + b) * 0.5
	var length := a.distance_to(b)
	var yaw := atan2(b.x - a.x, b.y - a.y)
	_box(Vector3(4.0, 0.3, length), Vector3(mid.x, WATER_Y + 0.45, mid.y), mat, Vector3(0, yaw, 0))
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
	add_child(body)

# A sunken concrete hulk at the centre: tilted wall slabs half in the water, gaps >= 9 m.
func _sunken_ruin() -> void:
	var conc := _mat(Color("#6b6a62"))
	for s in [1.0, -1.0]:
		_box(Vector3(18, 7, 1.2), Vector3(-6 * s, 1.5, 15 * s), conc, Vector3(0.25 * s, 0.3, 0.1))
		_box(Vector3(1.2, 6, 14), Vector3(17 * s, 1.0, -4 * s), conc, Vector3(0, 0.2, 0.22 * s))
		_box(Vector3(9, 0.8, 7), Vector3(13 * s, 2.6, 16 * s), conc, Vector3(0.4 * s, 0, 0.15))

func _physics_process(_delta: float) -> void:
	# T225: wading. Mech origin = its feet; under the surface -> slowed.
	for m in get_tree().get_nodes_in_group("mechs"):
		m.set("terrain_speed", WADE if (m as Node3D).global_position.y < WATER_Y - 0.05 else 1.0)
