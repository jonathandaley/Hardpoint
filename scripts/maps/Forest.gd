extends MapScene
# T223: forest (user: "Endor"): a giant-redwood forest in that spirit, no Star Wars props.
# ~280 m: gently rolling mossy floor, giant trunks (3-8 m across, 60-90 m tall) under a high
# dark canopy, fallen logs and mossy boulders for cover, ferns, dim green light and fog.
# Point-symmetric (x, z) -> (-x, -z) for fairness: team 0 west, team 1 east; 5 beacons
# (V18), 3 spawns each. Trunks keep >= LANE m apart (and clear of logs, rocks, pads) so a
# mech never wedges between them (T221 checks it).

const HALF := 140.0
const LANE := 9.0          # min gap between obstacles (mechs ~2 m wide, Everest 3)
const BEACONS := [Vector2(0, 0), Vector2(-80, 60), Vector2(80, -60), Vector2(-80, -60), Vector2(80, 60)]
const SPAWNS := [[Vector2(-118, -40), Vector2(-122, 0), Vector2(-118, 40)],
	[Vector2(118, 40), Vector2(122, 0), Vector2(118, -40)]]
const MOSS := Color("#3c5a2c")
const SOIL := Color("#4a3a26")
const BARK := Color("#6a3622")

var _blocked: Array = []  # [Vector2, radius] of everything placed so far

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

func _rise(x: float, z: float) -> float:
	return 2.5 * sin(x * 0.04 + 0.5) * cos(z * 0.035) + 1.5 * sin(x * 0.09 + z * 0.07)

func ground_y(x: float, z: float) -> float:
	var h := _rise(x, z)
	var p := Vector2(x, z)
	for b in BEACONS:
		h = lerpf(h, _rise(b.x, b.y), smoothstep(14.0, 7.0, p.distance_to(b)))
	for team in SPAWNS:
		for s in team:
			h = lerpf(h, _rise(s.x, s.y), smoothstep(26.0, 18.0, p.distance_to(s)))
	return h

func _mat(c: Color, rough := 0.95) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m

func _free(p: Vector2, r: float) -> bool:
	if absf(p.x) > HALF - 8.0 - r or absf(p.y) > HALF - 8.0 - r:
		return false
	for b in BEACONS:
		if p.distance_to(b) < 16.0 + r:
			return false
	for team in SPAWNS:
		for s in team:
			if p.distance_to(s) < 28.0 + r:
				return false
	for o in _blocked:
		if p.distance_to(o[0]) < float(o[1]) + r + LANE:
			return false
	return true

func build() -> void:
	make_terrain(HALF, 2.0, func(x: float, z: float, y: float) -> Color:
		return MOSS.lerp(SOIL, clampf(0.5 + 0.5 * sin(x * 0.21) * cos(z * 0.17), 0.0, 1.0) * 0.6).lightened(clampf(y * 0.02, -0.1, 0.1)), 223)
	make_boundary(HALF)
	var env := own_environment()
	if env != null:
		env.fog_enabled = true
		env.fog_light_color = Color("#3b4a35")
		env.fog_density = 0.008
		env.ambient_light_color = Color("#7f9a72")
		env.ambient_light_energy = 0.55
	var rng := RandomNumberGenerator.new()
	rng.seed = 223
	var bark := _mat(BARK)
	var moss_rock := _mat(Color("#55644a"))
	var leaf := _mat(Color("#1f3a1c"))
	# giant trunks, placed in symmetric pairs
	for k in 260:
		var p := Vector2(rng.randf_range(-HALF, HALF), rng.randf_range(-HALF, HALF))
		var r := rng.randf_range(1.5, 4.0)
		if not (_free(p, r) and _free(-p, r)):
			continue
		var h := rng.randf_range(60.0, 90.0)
		for q in [p, -p]:
			_blocked.append([q, r])
			_trunk(q, r, h, bark, leaf)
	# fallen logs (cover), symmetric pairs
	for k in 60:
		var p := Vector2(rng.randf_range(-HALF, HALF), rng.randf_range(-HALF, HALF))
		var length := rng.randf_range(12.0, 22.0)
		var r := rng.randf_range(1.0, 1.6)
		if not (_free(p, length * 0.5) and _free(-p, length * 0.5)):
			continue
		var yaw := rng.randf() * PI
		for q in [p, -p]:
			_blocked.append([q, length * 0.5])
			_log(q, length, r, yaw + (PI if q != p else 0.0), bark)
	# mossy boulders
	for k in 80:
		var p := Vector2(rng.randf_range(-HALF, HALF), rng.randf_range(-HALF, HALF))
		var s := rng.randf_range(2.0, 4.5)
		if not (_free(p, s) and _free(-p, s)):
			continue
		var yaw := rng.randf() * PI
		for q in [p, -p]:
			_blocked.append([q, s])
			_rock(q, s, yaw, moss_rock)
	# ferns: dressing only (no collision)
	var fern := _mat(Color("#3f7a32"))
	for k in 500:
		var q := Vector2(rng.randf_range(-HALF + 6, HALF - 6), rng.randf_range(-HALF + 6, HALF - 6))
		var mi := MeshInstance3D.new()
		var pm := PrismMesh.new()
		pm.size = Vector3(rng.randf_range(1.0, 2.2), rng.randf_range(0.5, 1.2), rng.randf_range(1.0, 2.2))
		var yaw := rng.randf() * PI
		# T314: a clearing around each beacon -- a fern on the (now 6 m) capture ring hid it.
		# Skipped after its draws, so every other fern / the layout stays where it was.
		if BEACONS.any(func(b): return q.distance_to(b) < Beacon.CIRCLE_RADIUS + 1.2):
			mi.free()
			continue
		mi.mesh = pm
		mi.material_override = fern
		add_child(mi)
		mi.position = Vector3(q.x, ground_y(q.x, q.y) + pm.size.y * 0.4, q.y)
		mi.rotation.y = yaw

func _trunk(p: Vector2, r: float, h: float, bark: Material, leaf: Material) -> void:
	var y0 := ground_y(p.x, p.y) - 0.5
	var body := StaticBody3D.new()
	body.position = Vector3(p.x, y0, p.y)
	var col := CollisionShape3D.new()
	# capsules, not cylinders: mechs brushing a CylinderShape3D got stuck on it (T221 found
	# 16 such spots; Godot's cylinder contacts are the unstable ones)
	var cs := CapsuleShape3D.new()
	cs.radius = r
	cs.height = h
	col.shape = cs
	col.position.y = h * 0.5
	body.add_child(col)
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r * 0.7
	cm.bottom_radius = r
	cm.height = h
	mi.mesh = cm
	mi.material_override = bark
	mi.position.y = h * 0.5
	body.add_child(mi)
	var flare := MeshInstance3D.new()  # root flare (visual; the trunk collider covers its core)
	var fm := CylinderMesh.new()
	fm.top_radius = r
	fm.bottom_radius = r * 1.35
	fm.height = 3.0
	flare.mesh = fm
	flare.material_override = bark
	flare.position.y = 1.5
	body.add_child(flare)
	var crown := MeshInstance3D.new()  # canopy far overhead (no collision)
	var sm := SphereMesh.new()
	sm.radius = r * 4.0
	sm.height = r * 3.0
	crown.mesh = sm
	crown.material_override = leaf
	crown.position.y = h * 0.85
	body.add_child(crown)
	add_child(body)

func _log(p: Vector2, length: float, r: float, yaw: float, bark: Material) -> void:
	var body := StaticBody3D.new()
	body.position = Vector3(p.x, ground_y(p.x, p.y) + r * 0.6, p.y)
	body.rotation = Vector3(0, yaw, PI * 0.5)
	var col := CollisionShape3D.new()
	var cs := CapsuleShape3D.new()  # see _trunk: no cylinders
	cs.radius = r
	cs.height = length
	col.shape = cs
	body.add_child(col)
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = length
	mi.mesh = cm
	mi.material_override = bark
	body.add_child(mi)
	add_child(body)

func _rock(p: Vector2, s: float, yaw: float, mat: Material) -> void:
	var body := StaticBody3D.new()
	body.position = Vector3(p.x, ground_y(p.x, p.y) + s * 0.3, p.y)
	body.rotation = Vector3(0.2, yaw, 0.15)
	var col := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(s, s * 0.8, s * 1.2)
	col.shape = bs
	body.add_child(col)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = bs.size
	mi.mesh = bm
	mi.material_override = mat
	body.add_child(mi)
	add_child(body)
