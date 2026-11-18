extends MapScene
# T460 (user 2026-11-17: "Denali worked well: add as many mechs as you think are good. Also maps and
# weapons."): Caldera. A volcanic crater ~330 m across: black rock terraces step down from a rim
# road to a lava lake in the middle. The lake is fenced by a ring of basalt columns (no new
# mechanic: nothing walks on the lava, nothing burns); the centre beacon sits on an island reached
# by two railed causeways, east and west. Basalt column clusters on the terraces for cover; the
# banks between terraces are walkable everywhere (~35 deg). Mirror-symmetric across x = 0: team 0
# west, team 1 east; 5 beacons (V18), 3 spawns each. Colliders: boxes and the terrain (V59).

const HALF := 165.0
const BEACONS := [Vector2(0, 0), Vector2(-75, -78), Vector2(75, -78), Vector2(-75, 78), Vector2(75, 78)]
const SPAWNS := [[Vector2(-140, -45), Vector2(-146, 0), Vector2(-140, 45)],
	[Vector2(140, -45), Vector2(146, 0), Vector2(140, 45)]]
const LAKE_R := 40.0        # lava lake radius (the column ring stands on it)
const ISLAND_R := 14.0
const LAVA_Y := -1.6        # the lava surface (terrain under it a little lower)
const CAUSE_W := 8.0        # causeway width (x from the island to the ring)
const TERRACES := [[62.0, 3.0], [98.0, 3.0], [128.0, 3.0]]  # [radius of the bank, rise]
const BANK := 4.5           # metres a bank's rise spreads over (~34 deg)
const ROCK := Color("#4a423d")
const ASH := Color("#6e6258")
const ROAD := Color("#332d2a")
const ROCK_SHADES := [0.62, 0.72, 0.82, 0.92]  # the floor grain: lighter than FLOOR_SHADES, the rock is dark already
const LAVA := Color("#ff5a14")

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

func _rough(x: float, z: float) -> float:
	return 0.5 * sin(x * 0.09 + 0.4) * cos(z * 0.08) + 0.3 * sin(x * 0.21 - z * 0.17)

## Inside the lava ring and off the island / causeways: the sunken lava bed.
static func in_lava(x: float, z: float) -> bool:
	var r := Vector2(x, z).length()
	return r < LAKE_R and r > ISLAND_R and absf(z) > CAUSE_W * 0.5

func ground_y(x: float, z: float) -> float:
	var ax := absf(x)  # mirrored across x = 0
	var r := Vector2(x, z).length()
	var h := 0.0
	for t in TERRACES:
		h += float(t[1]) * smoothstep(float(t[0]) - BANK * 0.5, float(t[0]) + BANK * 0.5, r)
	h += _rough(ax, z) * smoothstep(LAKE_R + 4.0, LAKE_R + 14.0, r)
	if in_lava(x, z):
		# the bed under the lava disc: a checkerboard of 4 m spikes (every terrain triangle ~70 deg,
		# past the navmesh's 60): no walkable polygons in there. A flat bed baked a navmesh island
		# nothing can reach, and Godot's path search into it logs "It's not expect to not find the
		# most reachable polygons" (map_stuck's crash_scan).
		var parity := (roundi((x + HALF) / 2.0) + roundi((z + HALF) / 2.0)) % 2
		h = LAVA_Y - 0.2 - 4.0 * float(parity)
	var p := Vector2(x, z)
	for b in BEACONS:
		if b != Vector2.ZERO:
			var flat := 0.0
			for t in TERRACES:
				flat += float(t[1]) * smoothstep(float(t[0]) - BANK * 0.5, float(t[0]) + BANK * 0.5, b.length())
			h = lerpf(h, flat, smoothstep(16.0, 8.0, p.distance_to(b)))
	for team in SPAWNS:
		for s in team:
			h = lerpf(h, 9.0, smoothstep(28.0, 20.0, p.distance_to(s)))
	return h

func _mat(c: Color, rough := 0.95) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m

func _box(size: Vector3, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	body.rotation = rot
	var col := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	col.shape = bs
	body.add_child(col)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	body.add_child(mi)
	add_child(body)

## A basalt column: a six-sided prism you see, a box you bump into (V59: boxes).
## `hit` = the collider's width share of the column's (1.6: a box over the hexagon). The lava ring
## uses 1.2: its overlapping boxes made a 2.3 m wall top the navmesh baked a strip along (an island
## no bot reaches: Godot's path search into it logs errors); 1.74 m boxes leave 0.7 m gaps (no mech
## fits) and no top wider than the bake's agent (2 x 0.75 m).
func _column(at: Vector2, base_y: float, h: float, r: float, mat: Material, hit := 1.6) -> void:
	var body := StaticBody3D.new()
	body.position = Vector3(at.x, base_y + h * 0.5, at.y)
	var col := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(r * hit, h, r * hit)
	col.shape = bs
	body.add_child(col)
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = 6
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = mat
	body.add_child(mi)
	add_child(body)

func build() -> void:
	make_terrain(HALF, 2.0, func(x: float, z: float, y: float) -> Color:
		var r := Vector2(x, z).length()
		var c := ROCK.lerp(ASH, clampf(0.5 + 0.5 * sin(x * 0.07) * sin(z * 0.06), 0.0, 1.0) * 0.6)
		for t in TERRACES:  # the banks darker, each terrace a step lighter: the steps read from afar
			c = c.darkened(0.35 * smoothstep(BANK * 0.9, 0.0, absf(r - float(t[0]))))
		c = c.lightened(clampf(y * 0.025, 0.0, 0.22))
		if absf(r - 140.0) < 5.0:
			c = ROAD  # the rim road
		return c, 460, false, ROCK_SHADES)
	make_boundary(HALF)
	_sky()
	var rng := RandomNumberGenerator.new()
	rng.seed = 460
	var basalt := _mat(Color("#232120"), 0.9)
	var basalt_top := _mat(Color("#34302d"), 0.9)
	# the lava, one glowing disc over the sunken bed (unlit: it is the light)
	var lava := MeshInstance3D.new()
	var lm := CylinderMesh.new()
	lm.top_radius = LAKE_R
	lm.bottom_radius = LAKE_R
	lm.height = 0.2
	lm.radial_segments = 48
	lm.rings = 1
	lava.mesh = lm
	var lmat := StandardMaterial3D.new()
	lmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lmat.albedo_color = LAVA
	lmat.albedo_texture = _lava_tex()
	lmat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	lmat.uv1_triplanar = true
	lmat.uv1_world_triplanar = true
	lmat.uv1_scale = Vector3.ONE / 6.0
	lava.material_override = lmat
	add_child(lava)
	lava.position = Vector3(0, LAVA_Y, 0)
	var glow := OmniLight3D.new()
	glow.light_color = Color("#ff6a20")
	glow.light_energy = 2.2
	glow.omni_range = LAKE_R + 30.0
	glow.position = Vector3(0, 6.0, 0)
	add_child(glow)
	# the island and the causeways: solid rock over the lava, railed
	_box(Vector3(ISLAND_R * 2.0, 2.4, ISLAND_R * 2.0), Vector3(0, -1.2, 0), basalt_top)
	for sx in [-1.0, 1.0]:
		var span := LAKE_R - ISLAND_R + 6.0
		var cx: float = sx * (ISLAND_R + span * 0.5 - 3.0)
		_box(Vector3(span, 2.4, CAUSE_W), Vector3(cx, -1.2, 0), basalt_top)
		for sz in [-1.0, 1.0]:
			_box(Vector3(span - 2.0, 1.3, 0.8), Vector3(cx, 0.65, sz * (CAUSE_W * 0.5 - 0.4)), basalt)
	# the column ring around the lava (gaps where the causeways come in)
	var n := int(TAU * LAKE_R / 2.4)
	for i in n:
		var a := TAU * i / n
		var p := Vector2(cos(a), sin(a)) * LAKE_R
		if absf(p.y) < CAUSE_W * 0.5 + 1.2:
			continue
		var h := 2.6 + 1.6 * absf(sin(a * 7.0)) + rng.randf_range(0.0, 0.8)
		_column(p, LAVA_Y - 0.4, h + 1.4, 1.45, basalt, 1.2)
	# T460: the bake ignores everything 1.6..9 m up inside the ring (only the column tops: the island,
	# causeways and rails are below 1.6 m), so no navmesh island sits on top of the ring (bots' paths
	# into one log Godot errors). An obstacle that only shapes the bake: no avoidance, no carving.
	var cut := NavigationObstacle3D.new()
	var ring_pts := PackedVector3Array()
	for i in 24:
		var a := -TAU * i / 24.0
		ring_pts.append(Vector3(cos(a), 0, sin(a)) * (LAKE_R + 3.0))
	cut.vertices = ring_pts
	cut.height = 7.4
	cut.position = Vector3(0, 1.6, 0)
	cut.avoidance_enabled = false
	cut.affect_navigation_mesh = true
	cut.carve_navigation_mesh = false
	add_child(cut)
	# column clusters on the terraces, mirrored (T463: 22 -> 60 tries, closer together, out to the rim)
	for k in 60:
		var p := Vector2(rng.randf_range(10, HALF - 12), rng.randf_range(-HALF + 12, HALF - 12))
		if _crowded(p, 6.0):
			continue
		var count := rng.randi_range(3, 6)
		# heights 0.9 m apart (more than the navmesh's 0.6 m climb) on narrow boxes: every top stays
		# its own ledge too small for the bake's agent -- no unreachable navmesh islands up there
		var heights: Array = [1.8, 2.7, 3.6, 4.5, 5.4, 6.3]
		for c in heights.size():
			var j := rng.randi_range(c, heights.size() - 1)
			var t: float = heights[c]
			heights[c] = heights[j]
			heights[j] = t
		var offs: Array = []
		for c in count:
			offs.append(Vector2(rng.randf_range(-2.5, 2.5), rng.randf_range(-2.5, 2.5)))
		for sx in [-1.0, 1.0]:
			for c in count:
				var q := Vector2((p.x + offs[c].x) * sx, p.y + offs[c].y)
				_column(q, ground_min(q.x, q.y, 1.2) - 0.5, heights[c] + 0.5, 1.0, basalt, 1.2)
	# T463 (user 2026-11-18: "doesn't look like either new map has enough cover ... adding more ice
	# and basalt would probably be good"): basalt walls -- rows of touching columns, alternate ones
	# 0.9 m taller (1.2 m boxes: no navmesh on top, as above)
	for k in 110:
		var p := Vector2(rng.randf_range(10, HALF - 10), rng.randf_range(-HALF + 10, HALF - 10))
		if _crowded_walls(p):
			continue
		var dir := Vector2.from_angle(rng.randf() * PI)
		if absf(p.length() - 140.0) < 14.0:
			dir = p.normalized().orthogonal()  # beside the rim road: along it, never across
		var cols := rng.randi_range(4, 7)
		var base := rng.randf_range(2.2, 3.0)
		for sx in [-1.0, 1.0]:
			for c in cols:
				var o := dir * ((c - (cols - 1) * 0.5) * 1.15)
				var q := Vector2((p.x + o.x) * sx, p.y + o.y)
				_column(q, ground_min(q.x, q.y, 1.0) - 0.5, base + 0.9 * float(c % 2) + 0.5, 0.7, basalt, 1.7)
	# broken walls along both sides of the rim road (the road itself was open ground end to end)
	for i in 13:
		var a := -PI * 0.5 + PI * (i + 0.5) / 13.0
		var rr := 131.0 if i % 2 == 0 else 149.0
		var p := Vector2.from_angle(a) * rr
		if _crowded_walls(p, false):
			continue
		for sx in [-1.0, 1.0]:
			for c in 5:
				var o := Vector2.from_angle(a).orthogonal() * ((c - 2) * 1.15)
				var q := Vector2((p.x + o.x) * sx, p.y + o.y)
				_column(q, ground_min(q.x, q.y, 1.0) - 0.5, 2.6 + 0.9 * float(c % 2) + 0.5, 0.7, basalt, 1.7)
	# the island: four column pairs on its edge between the causeways, cover at the centre beacon
	for a in [PI * 0.25, PI * 0.75, PI * 1.25, PI * 1.75]:
		for c in 2:
			var q := Vector2.from_angle(a + (c - 0.5) * 0.09) * (ISLAND_R - 2.5)
			_column(q, -0.5, 2.4 + 0.9 * c + 0.5, 0.7, basalt, 1.7)
	_embers()

func _crowded(p: Vector2, r: float) -> bool:
	if p.length() < LAKE_R + r + 6.0:
		return true
	for b in BEACONS:
		if Vector2(absf(p.x), p.y).distance_to(Vector2(absf(b.x), b.y)) < r + 10.0:
			return true
	for team in SPAWNS:
		for s in team:
			if Vector2(absf(p.x), p.y).distance_to(Vector2(absf(s.x), s.y)) < r + 18.0:
				return true
	return absf(p.length() - 140.0) < r + 4.0  # keep the rim road clear

## Walls: off the lava ring, beacons, spawn lines (north-south, 5 x 8 m) and the rim road itself.
func _crowded_walls(p: Vector2, road := true) -> bool:
	if p.length() < LAKE_R + 10.0 or (road and absf(p.length() - 140.0) < 7.0):
		return true
	for b in BEACONS:
		if Vector2(absf(p.x), p.y).distance_to(Vector2(absf(b.x), b.y)) < 15.0:
			return true
	for team in SPAWNS:
		for s in team:
			if absf(absf(p.x) - absf(s.x)) < 12.0 and absf(p.y - s.y) < 26.0:
				return true
	return false

## 16 x 16 px of crusted lava: bright channels between dark plates (chunky like T440).
func _lava_tex() -> ImageTexture:
	var r := RandomNumberGenerator.new()
	r.seed = 4601
	var img := Image.create(16, 16, false, Image.FORMAT_RGB8)
	for y in 16:
		for x in 16:
			var v := 0.5 + 0.5 * sin(x * 0.9 + sin(y * 0.7) * 2.0) * cos(y * 0.8 - x * 0.3)
			var c := Color(1.0, 0.75, 0.3).lerp(Color(0.35, 0.08, 0.03), smoothstep(0.35, 0.7, v + r.randf_range(-0.1, 0.1)))
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

func _sky() -> void:
	var env := own_environment()
	if env == null:
		return
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color("#3a2420")
	sm.sky_horizon_color = Color("#a0502a")
	sm.sky_curve = 0.2
	sm.ground_horizon_color = Color("#5a2a18")
	sm.ground_bottom_color = Color("#1a1210")
	sm.sun_angle_max = 6.0
	sm.sun_curve = 0.05
	own_sky(env).sky_material = sm
	env.fog_enabled = true
	env.fog_light_color = Color("#6a3422")
	env.fog_density = 0.0011
	env.fog_sky_affect = 0.5
	env.ambient_light_color = Color("#b07a62")
	env.ambient_light_energy = 0.8
	var sun := get_parent().get_node_or_null("Sun") as DirectionalLight3D
	if sun != null:
		sun.light_color = Color(1.0, 0.72, 0.55)
		sun.light_energy = 0.95

## Embers rising off the lava (GRAPHICS > AMBIENT EFFECTS, off headless).
func _embers() -> void:
	if not Game.settings.get("map_effects", true) or DisplayServer.get_name() == "headless":
		return
	var fx := CPUParticles3D.new()
	fx.name = "Embers"
	fx.amount = 120
	fx.lifetime = 6.0
	fx.preprocess = 6.0
	fx.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	fx.emission_sphere_radius = LAKE_R
	fx.position.y = LAVA_Y
	fx.direction = Vector3.UP
	fx.spread = 25.0
	fx.gravity = Vector3(0.4, 0.6, 0)
	fx.initial_velocity_min = 1.0
	fx.initial_velocity_max = 2.5
	var q := QuadMesh.new()
	q.size = Vector2(0.15, 0.15)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_color = Color(1.0, 0.55, 0.15)
	m.disable_fog = true
	q.material = m
	fx.mesh = q
	add_child(fx)
