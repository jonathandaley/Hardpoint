extends MapScene
# T459 (user 2026-11-17: "Denali worked well: add as many mechs as you think are good. Also maps and
# weapons."): Glacier. ~320 m of snowfield: a frozen lake in the middle (flat, open, fast -- the
# centre beacon sits on the ice), two shallow ravines down each half (cover from the lake; slopes
# under 40 deg so mechs and bots walk in and out), ice ridges and leaning seracs, dark rock
# outcrops, and a research station on each side. Mirror-symmetric across x = 0: team 0 west,
# team 1 east; 5 beacons (V18), 3 spawns each. Colliders: boxes and the terrain (V59).

const HALF := 160.0
const BEACONS := [Vector2(0, 0), Vector2(-75, -85), Vector2(75, -85), Vector2(-75, 85), Vector2(75, 85)]
const SPAWNS := [[Vector2(-140, -45), Vector2(-145, 0), Vector2(-140, 45)],
	[Vector2(140, -45), Vector2(145, 0), Vector2(140, 45)]]
const LAKE := Vector2(46.0, 62.0)   # half-axes (x, z) of the frozen lake
const LAKE_Y := -1.0
const RAVINE_X := 48.0              # each half's ravine runs north-south at |x| = RAVINE_X ...
const RAVINE_Z := 120.0             # ... between z = +-RAVINE_Z
const RAVINE_DEPTH := 3.0
const STATION := Vector2(105, 0)
const SNOW := Color("#e6edf3")
const SNOW_SHADE := Color("#b9c9da")
const ICE := Color("#7fb6dc")
const SNOW_SHADES := [0.80, 0.86, 0.93, 1.0]  # T459: the floor grain, lighter than FLOOR_SHADES (snow, not stone)
const ROCK := Color("#4c535c")

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

## 0 outside the lake .. 1 well inside it.
static func lake_k(x: float, z: float) -> float:
	var e := Vector2(x / LAKE.x, z / LAKE.y).length()
	return smoothstep(1.15, 0.92, e)

static func ravine_k(x: float, z: float) -> float:
	var across := absf(absf(x) - RAVINE_X)
	var along := smoothstep(RAVINE_Z + 10.0, RAVINE_Z - 10.0, absf(z))
	return smoothstep(9.0, 4.0, across) * along  # 5 m of slope for 3 m of depth: ~31 deg

func _drifts(x: float, z: float) -> float:
	return 1.6 * sin(x * 0.045 + 0.7) * cos(z * 0.038) + 0.7 * sin(x * 0.11 + z * 0.07)

func ground_y(x: float, z: float) -> float:
	var ax := absf(x)  # mirrored across x = 0
	var h := _drifts(ax, z)
	var p := Vector2(x, z)
	h = lerpf(h, LAKE_Y, lake_k(x, z))
	h -= RAVINE_DEPTH * ravine_k(x, z)
	for b in BEACONS:
		h = lerpf(h, LAKE_Y if b == Vector2.ZERO else 0.0, smoothstep(16.0, 8.0, p.distance_to(b)))
	for team in SPAWNS:
		for s in team:
			h = lerpf(h, 0.0, smoothstep(28.0, 20.0, p.distance_to(s)))
	var st := Vector2(ax, z).distance_to(STATION)
	h = lerpf(h, 0.0, smoothstep(26.0, 16.0, st))
	return h

func _mat(c: Color, rough := 0.95) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m

func _box(size: Vector3, pos: Vector3, mat: Material, rot := Vector3.ZERO, solid := true) -> void:
	var holder: Node3D = StaticBody3D.new() if solid else Node3D.new()
	holder.position = pos
	holder.rotation = rot
	if solid:
		var col := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		col.shape = bs
		holder.add_child(col)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	holder.add_child(mi)
	add_child(holder)

func build() -> void:
	make_terrain(HALF, 2.0, func(x: float, z: float, y: float) -> Color:
		var k := lake_k(x, z)
		var snow := SNOW.lerp(SNOW_SHADE, clampf(-y * 0.12 + 0.8 * ravine_k(x, z), 0.0, 0.85))
		return snow.lerp(ICE, k), 459, false, SNOW_SHADES)
	make_boundary(HALF)
	_sky()
	var rng := RandomNumberGenerator.new()
	rng.seed = 459
	var ice := _mat(ICE.darkened(0.08), 0.35)
	var ice_dark := _mat(ICE.darkened(0.3), 0.4)
	var rock := _mat(ROCK)
	var metal := _mat(Color("#8b9198"), 0.6)
	var orange := _mat(Color("#e0662a"), 0.7)
	# ice ridges: low walls of ice blocks across each half, gaps to walk through
	for ridge in [[Vector2(30, -45), 0.35], [Vector2(28, 50), -0.4], [Vector2(85, -40), 1.2], [Vector2(88, 45), -1.1],
			[Vector2(60, -120), 0.1], [Vector2(62, 122), -0.15], [Vector2(118, -95), 0.8], [Vector2(118, 98), -0.8]]:
		var at: Vector2 = ridge[0]
		var yaw: float = ridge[1]
		var dir := Vector2(cos(yaw), -sin(yaw))
		for k in range(-2, 3):
			if k == 0:
				continue  # the gap
			var p := at + dir * (k * 4.6)
			var hgt := rng.randf_range(2.2, 3.6)
			for sx in [-1.0, 1.0]:
				var q := Vector2(p.x * sx, p.y)
				_box(Vector3(4.2, hgt, 2.2), Vector3(q.x, ground_min(q.x, q.y, 2.5) + hgt * 0.5 - 0.4, q.y), ice,
					Vector3(0, yaw * sx, 0))
	# seracs: leaning ice towers, mirrored (T463: 30 -> 70 tries, closer together)
	for k in 70:
		var p := Vector2(rng.randf_range(12, HALF - 22), rng.randf_range(-HALF + 22, HALF - 22))
		if _crowded(p, 9.0):
			continue
		var s := Vector3(rng.randf_range(2.0, 3.5), rng.randf_range(4.0, 8.0), rng.randf_range(2.0, 3.5))
		var lean := Vector3(rng.randf_range(-0.15, 0.15), rng.randf() * PI, rng.randf_range(-0.15, 0.15))
		for sx in [-1.0, 1.0]:
			var q := Vector2(p.x * sx, p.y)
			var rot := Vector3(lean.x, lean.y * sx, lean.z * sx)
			_box(s, Vector3(q.x, ground_min(q.x, q.y, s.x) - 0.6 - MapScene.box_low(s, rot), q.y), ice_dark, rot)
	# rock outcrops on the ravine rims
	for k in 12:
		var z := rng.randf_range(-RAVINE_Z + 10, RAVINE_Z - 10)
		var x := RAVINE_X + rng.randf_range(7.0, 12.0) * (1.0 if rng.randf() < 0.5 else -1.0)
		var p := Vector2(x, z)
		if _crowded(p, 10.0):
			continue
		var s := Vector3(rng.randf_range(2.5, 4.5), rng.randf_range(1.5, 3.0), rng.randf_range(2.5, 4.5))
		for sx in [-1.0, 1.0]:
			var q := Vector2(p.x * sx, p.y)
			_box(s, Vector3(q.x, ground_min(q.x, q.y, s.x * 0.6) + s.y * 0.5 - 0.5, q.y), rock, Vector3(0.08, rng.randf() * PI, -0.06))
	# research stations
	for sx in [-1.0, 1.0]:
		_station(Vector2(STATION.x * sx, STATION.y), sx, metal, orange)
	# T463 (user 2026-11-18: "doesn't look like either new map has enough cover ... adding more ice
	# and basalt would probably be good"): pressure ridges on the lake and ice walls across the open
	# snow. Slabs 1.1 m thick: thinner than the navmesh agent (2 x 0.75 m), so no walkable top.
	var rnd := Callable(rng, "randf_range")
	for k in 24:  # the lake: broken ridges 22-50 m out from the beacon, tangent to it
		var a := rng.randf_range(-PI * 0.5, PI * 0.5)
		var e := rng.randf_range(0.35, 0.9)
		var at := Vector2(cos(a) * LAKE.x * e, sin(a) * LAKE.y * e)
		if at.length() < 22.0 or at.x < 5.0:
			continue
		_slab_row(at, a + PI * 0.5 + rng.randf_range(-0.4, 0.4), rng.randi_range(2, 4), ice, rnd)
	for k in 80:  # the snowfields: short ice walls wherever there is room
		var at := Vector2(rng.randf_range(14, HALF - 14), rng.randf_range(-HALF + 14, HALF - 14))
		if _crowded_walls(at):
			continue
		_slab_row(at, rng.randf() * PI, rng.randi_range(2, 3), ice_dark, rnd)
	_snowfall()

## Ice slabs in a row along `yaw` (mirrored across x = 0), each tilted about its long axis.
func _slab_row(at: Vector2, yaw: float, n: int, mat: Material, rnd: Callable) -> void:
	var dir := Vector2(cos(yaw), -sin(yaw))
	for i in n:
		var p: Vector2 = at + dir * ((i - (n - 1) * 0.5) * 3.4) + Vector2(rnd.call(-0.6, 0.6), rnd.call(-0.6, 0.6))
		var s := Vector3(rnd.call(2.8, 3.6), rnd.call(2.2, 3.4), 1.1)
		var rot := Vector3(rnd.call(-0.25, 0.25), yaw + rnd.call(-0.15, 0.15), rnd.call(-0.06, 0.06))
		for sx in [-1.0, 1.0]:
			var q := Vector2(p.x * sx, p.y)
			var r2 := Vector3(rot.x, rot.y * sx, rot.z * sx)
			_box(s, Vector3(q.x, ground_min(q.x, q.y, 1.8) - 0.5 - MapScene.box_low(s, r2), q.y), mat, r2)

## Walls stay off the beacons, spawn lines, stations and lake, and out of the ravine floors.
func _crowded_walls(p: Vector2) -> bool:
	if ravine_k(p.x, p.y) > 0.2:
		return true
	for b in BEACONS:
		if Vector2(absf(p.x), p.y).distance_to(Vector2(absf(b.x), b.y)) < 16.0:
			return true
	for team in SPAWNS:
		for s in team:  # the spawn line runs north-south, 5 x 8 m
			if absf(absf(p.x) - absf(s.x)) < 12.0 and absf(p.y - s.y) < 26.0:
				return true
	return lake_k(p.x, p.y) > 0.05 or Vector2(absf(p.x), p.y).distance_to(STATION) < 22.0

## Keep props off the beacons, spawns, lake and stations.
func _crowded(p: Vector2, r: float) -> bool:
	for b in BEACONS:
		if p.distance_to(b) < r + 8.0 or Vector2(-p.x, p.y).distance_to(b) < r + 8.0:
			return true
	for team in SPAWNS:
		for s in team:
			if Vector2(absf(p.x), p.y).distance_to(Vector2(absf(s.x), s.y)) < r + 18.0:
				return true
	if lake_k(p.x, p.y) > 0.05:
		return true
	return Vector2(absf(p.x), p.y).distance_to(STATION) < r + 16.0

## A research station: three modules on the flattened pad, a mast with a dish, an orange stripe.
func _station(at: Vector2, sx: float, metal: Material, orange: Material) -> void:
	var g := ground_y(at.x, at.y)
	for m in [[Vector3(10, 3.4, 5), Vector2(0, -7)], [Vector3(6, 3.0, 6), Vector2(-5 * sx, 3)], [Vector3(8, 4.2, 5), Vector2(4 * sx, 9)]]:
		var s: Vector3 = m[0]
		var o: Vector2 = m[1]
		_box(s, Vector3(at.x + o.x, g + s.y * 0.5, at.y + o.y), metal)
		_box(Vector3(s.x + 0.04, 0.5, s.z + 0.04), Vector3(at.x + o.x, g + s.y * 0.72, at.y + o.y), orange, Vector3.ZERO, false)
	var mast := Vector2(at.x + 3 * sx, at.y - 1)
	_box(Vector3(0.5, 12, 0.5), Vector3(mast.x, g + 6.0, mast.y), metal)
	var dish := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 2.2
	cm.bottom_radius = 0.6
	cm.height = 1.0
	cm.radial_segments = 12
	cm.rings = 1
	dish.mesh = cm
	dish.material_override = metal
	add_child(dish)
	dish.position = Vector3(mast.x, g + 12.2, mast.y)
	dish.rotation = Vector3(0.6, 0.8 * sx, 0)

func _sky() -> void:
	var env := own_environment()
	if env == null:
		return
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color("#5b7fa6")
	sm.sky_horizon_color = Color("#d6e3ee")
	sm.sky_curve = 0.15
	sm.ground_horizon_color = Color("#d6e3ee")
	sm.ground_bottom_color = Color("#8ea3b6")
	sm.sun_angle_max = 10.0
	sm.sun_curve = 0.06
	own_sky(env).sky_material = sm
	env.fog_enabled = true
	env.fog_light_color = Color("#dfe8f0")
	env.fog_density = 0.0016
	env.fog_sky_affect = 0.4
	env.ambient_light_color = Color("#c9d8e8")
	env.ambient_light_energy = 0.7
	var sun := get_parent().get_node_or_null("Sun") as DirectionalLight3D
	if sun != null:
		sun.light_color = Color(0.92, 0.95, 1.0)
		var e := deg_to_rad(22.0)  # a low polar sun, long shadows
		var to_sun := Vector3(0.5 * cos(e), sin(e), 0.866 * cos(e))
		sun.basis = Basis.looking_at(-to_sun, Vector3.UP)

## Light snow over the whole map (GRAPHICS > AMBIENT EFFECTS, off headless).
func _snowfall() -> void:
	if not Game.settings.get("map_effects", true) or DisplayServer.get_name() == "headless":
		return
	var fx := CPUParticles3D.new()
	fx.name = "Snowfall"
	fx.amount = 600
	fx.lifetime = 9.0
	fx.preprocess = 9.0
	fx.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	fx.emission_box_extents = Vector3(HALF, 1.0, HALF)
	fx.position.y = 26.0
	fx.direction = Vector3(0.3, -1, 0.1)
	fx.spread = 15.0
	fx.gravity = Vector3.ZERO
	fx.initial_velocity_min = 2.4
	fx.initial_velocity_max = 3.4
	var q := QuadMesh.new()
	q.size = Vector2(0.12, 0.12)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_color = Color(1, 1, 1)
	q.material = m
	fx.mesh = q
	add_child(fx)
