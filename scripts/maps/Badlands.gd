extends MapScene
# T211: Badlands. 320 m square (Math Temple's bowl is ~190 m across): rolling hills, two
# winding canyons (trenches you enter at their shallow ends -- covered routes past the
# centre), decrepit ruins (broken walls of uneven height, collapsed roof slabs, rubble)
# instead of Math Temple's precision. Point-symmetric for fairness: 5 beacons (V18),
# 3 spawn points per team at the north / south ends. Terrain = an analytic height
# function (ground_y), meshed on a 2 m grid with trimesh collision -> the navmesh bakes
# from it (Arena's nav_source group, V55). Everything seeded: same map on every peer.

const HALF := 160.0     # half the side, metres
const CELL := 2.0       # terrain grid
const EDGE := 22.0      # berm width at the boundary
const BEACONS := [Vector2(0, 0), Vector2(-85, 45), Vector2(85, -45), Vector2(85, 60), Vector2(-85, -60)]
const SPAWNS := [[Vector2(-60, 132), Vector2(0, 138), Vector2(60, 132)],
	[Vector2(60, -132), Vector2(0, -138), Vector2(-60, -132)]]
const CANYONS := [  # polylines; depth tapers to 0 at both ends (the way in)
	[Vector2(-140, 22), Vector2(-92, 8), Vector2(-45, -12), Vector2(-12, -38)],
	[Vector2(140, -22), Vector2(92, -8), Vector2(45, 12), Vector2(12, 38)],
]
const CANYON_W := 15.0
const CANYON_D := 9.0
const SAND := Color("#b08a5a")
const ROCK := Color("#7d6a55")
const DUST := Color("#5e4a38")
const CONCRETE := Color("#7a7064")
const RUST := Color("#6b3a22")

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

# ---- terrain ----

func _hills(x: float, z: float) -> float:
	return 6.0 * sin(x * 0.021 + 0.7) * cos(z * 0.017 - 0.3) + 3.0 * sin(x * 0.047 + z * 0.031) \
		+ 1.5 * sin(x * 0.11 - z * 0.083)

func _canyon_cut(x: float, z: float) -> float:
	var cut := 0.0
	var p := Vector2(x, z)
	for line in CANYONS:
		var total := 0.0
		for k in line.size() - 1:
			total += (line[k] as Vector2).distance_to(line[k + 1])
		var along := 0.0
		for k in line.size() - 1:
			var a: Vector2 = line[k]
			var b: Vector2 = line[k + 1]
			var seg := b - a
			var t := clampf((p - a).dot(seg) / seg.length_squared(), 0.0, 1.0)
			var d := p.distance_to(a + seg * t)
			var u := (along + seg.length() * t) / total            # 0..1 along the canyon
			var taper := smoothstep(0.0, 0.18, u) * smoothstep(1.0, 0.82, u)
			cut = maxf(cut, CANYON_D * taper * smoothstep(CANYON_W, CANYON_W * 0.45, d))
			along += seg.length()
	return cut

func _raw(x: float, z: float) -> float:
	var h := _hills(x, z) - _canyon_cut(x, z)
	var edge := maxf(absf(x), absf(z)) - (HALF - EDGE)  # berm rising to the boundary
	if edge > 0.0:
		h += 18.0 * smoothstep(0.0, EDGE, edge)
	return h

## Floor height: the terrain with beacon pads and spawn areas flattened.
func ground_y(x: float, z: float) -> float:
	var h := _raw(x, z)
	var p := Vector2(x, z)
	for b in BEACONS:
		h = lerpf(h, _raw(b.x, b.y), smoothstep(14.0, 7.0, p.distance_to(b)))
	for team in SPAWNS:
		for s in team:
			h = lerpf(h, _hills(s.x, s.y), smoothstep(28.0, 20.0, p.distance_to(s)))
	return h

func build() -> void:
	_terrain()
	_boundary()
	var rng := RandomNumberGenerator.new()
	rng.seed = 211
	# ruins: a few near each flank beacon and along the routes, none on a beacon pad / spawn
	# point-symmetric pairs (fair cover); a ruined-town cluster on each flank
	var half_spots := [Vector2(-30, 30), Vector2(-110, 70), Vector2(60, 95), Vector2(-40, -70),
		Vector2(-115, -20), Vector2(20, 105), Vector2(-62, 20), Vector2(-100, 38), Vector2(-70, 68),
		Vector2(-120, 100), Vector2(10, 62), Vector2(40, 28)]
	var spots: Array = []
	for v in half_spots:
		spots.append(v)
		spots.append(-v)
	for s in spots:
		_ruin(s, rng)
	_wrecks_and_scrub(spots)

func _terrain() -> void:
	var n := int(HALF * 2.0 / CELL) + 1
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	for j in n:
		for i in n:
			var x := -HALF + i * CELL
			var z := -HALF + j * CELL
			var y := ground_y(x, z)
			verts.append(Vector3(x, y, z))
			var c := SAND.lerp(ROCK, clampf((y - 2.0) / 10.0, 0.0, 1.0))
			c = c.lerp(DUST, clampf(_canyon_cut(x, z) / CANYON_D, 0.0, 1.0))
			c = c.darkened(0.08 * sin(x * 0.37) * cos(z * 0.29) + 0.04)  # mottling
			cols.append(c)
	for j in n - 1:
		for i in n - 1:
			var a := j * n + i
			for k in [a, a + 1, a + n, a + 1, a + n + 1, a + n]:  # clockwise from above = front (Godot)
				st.set_color(cols[k])
				st.add_vertex(verts[k])
	st.generate_normals()
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.95
	pixelate(mat, 211, FLOOR_TEXEL_M)  # T440: sand / grit, chunky pixels (was a soft noise)
	mi.material_override = mat
	add_child(mi)
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	col.shape = mesh.create_trimesh_shape()
	body.add_child(col)
	add_child(body)

func _boundary() -> void:  # invisible walls on top of the berm
	edge_half = HALF  # T405: fog curtains along them
	for side in [[Vector3(0, 20, -HALF), Vector3(HALF * 2.0, 40, 2)], [Vector3(0, 20, HALF), Vector3(HALF * 2.0, 40, 2)],
			[Vector3(-HALF, 20, 0), Vector3(2, 40, HALF * 2.0)], [Vector3(HALF, 20, 0), Vector3(2, 40, HALF * 2.0)]]:
		var body := StaticBody3D.new()
		var col := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = side[1]
		col.shape = box
		body.add_child(col)
		body.position = side[0]
		add_child(body)

# ---- T448: bricks, wrecks, scrub ----
# User 2026-11-17: yes to "an adobe-brick pixel texture plus a few rusted vehicle hulks or dead
# shrubs between the ruins". Bricks: one 16 x 16 px greyscale tile (15 cm pixels, T440's chunky
# size) shared by every ruin, tinted by the ruin's wall colour; world triplanar so it merges.
# Hulks and scrub are visual only (no colliders: the layout, bot paths and map_stuck stay as they
# were; a mech wades through a knee-high wreck), half sunk in the sand, from their own RNG.
var _bricks: ImageTexture

func _brick_mat(c: Color) -> StandardMaterial3D:
	if _bricks == null:
		var r := RandomNumberGenerator.new()
		r.seed = 2112
		var img := Image.create(16, 16, false, Image.FORMAT_RGB8)
		for row in 4:  # 4 courses of 4 px: 3 px of brick + 1 px of mortar; 8 px bricks, staggered
			var shades := [r.randf_range(0.78, 1.0), r.randf_range(0.78, 1.0)]
			for y in range(row * 4, row * 4 + 4):
				for x in 16:
					var xs := (x + (4 if row % 2 else 0)) % 16
					var v: float = 0.68 if y == row * 4 + 3 or xs % 8 == 0 else shades[xs / 8] - r.randf_range(0.0, 0.06)
					img.set_pixel(x, y, Color(v, v, v))
		img.generate_mipmaps()
		_bricks = ImageTexture.create_from_image(img)
	var m := _mat(c.lightened(0.15))  # the tile's average is ~0.85: keep the walls' tone
	m.albedo_texture = _bricks
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE / 2.4
	return m

func _wrecks_and_scrub(spots: Array) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 2113
	var paints := [_mat(RUST), _mat(RUST.lightened(0.15)), _mat(Color("#4a4f52"))]
	var glass := _mat(Color("#1d2226"))
	var scrub := _mat(Color("#5b4a35"))
	for k in spots.size():
		if k % 4:
			continue  # a hulk by every other mirrored pair of ruins, mirrored itself (fair look both sides)
		var a := r.randf() * TAU
		var d := r.randf_range(16.0, 22.0)
		var yaw := r.randf() * PI
		var paint: Material = paints[k / 2 % paints.size()]
		for s in [1.0, -1.0]:
			var p: Vector2 = (spots[k] as Vector2) * s + Vector2(cos(a), sin(a)) * d * s
			if not _clear_of_play(p):
				continue
			_hulk(p, yaw + (0.0 if s > 0.0 else PI), paint, glass)
	for k in 90:  # dead scrub: clumps of splayed twigs
		var p := Vector2(r.randf_range(-HALF + EDGE, HALF - EDGE), r.randf_range(-HALF + EDGE, HALF - EDGE))
		var twigs := r.randi_range(4, 6)
		var size := r.randf_range(0.8, 1.6)
		if not _clear_of_play(p):
			continue
		var g := ground_min(p.x, p.y, size * 0.5)
		for t in twigs:
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.08, size, 0.08)
			mi.mesh = bm
			mi.material_override = scrub
			var rot := Vector3(0.5 + 0.25 * (t % 2), t * TAU / twigs, 0.0)
			mi.position = Vector3(p.x, g - 0.05 - MapScene.box_low(bm.size, rot), p.y)
			mi.rotation = rot
			add_child(mi)

func _clear_of_play(p: Vector2) -> bool:
	for b in BEACONS:
		if p.distance_to(b) < 14.0:
			return false
	for team in SPAWNS:
		for s in team:
			if p.distance_to(s) < 20.0:
				return false
	return absf(p.x) < HALF - EDGE and absf(p.y) < HALF - EDGE

## A rusted car hulk: body + cabin + a dark window band, sunk 0.4 m and tilted with the ground.
func _hulk(p: Vector2, yaw: float, paint: Material, glass: Material) -> void:
	var holder := Node3D.new()
	var g := ground_min(p.x, p.y, 2.4)
	holder.position = Vector3(p.x, g - 0.4, p.y)
	holder.rotation = Vector3(0.06, yaw, -0.08)
	for part in [[Vector3(4.4, 1.1, 1.9), Vector3(0, 0.55, 0), paint],
			[Vector3(2.2, 0.8, 1.7), Vector3(-0.3, 1.5, 0), paint],
			[Vector3(2.0, 0.45, 1.75), Vector3(-0.3, 1.45, 0), glass]]:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = part[0]
		mi.mesh = bm
		mi.material_override = part[2]
		mi.position = part[1]
		holder.add_child(mi)
	add_child(holder)

# ---- ruins ----

func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	return m

func _block(size: Vector3, pos: Vector3, rot_y: float, mat: Material, tilt := Vector3.ZERO) -> void:
	var body := StaticBody3D.new()
	body.add_to_group(&"ruins")
	body.position = pos
	body.rotation = Vector3(tilt.x, rot_y, tilt.z)
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	col.shape = box
	body.add_child(col)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	body.add_child(mi)
	add_child(body)

# T288 (HUMAN_FOUND 2026-11-05: "Badlands should have some decrepit windows in the buildings"):
# some tall wall segments are built around a window hole -- sill, two side piers, and a lintel
# that has fallen out of some (a ragged notch). Its own RNG per segment (hash of the spot), so
# the rest of the map's layout stream is untouched. Returns false when the segment stays solid.
func _window_wall(c: Vector3, along: Vector3, x_long: bool, seg_len: float, h: float, rot: float, mat: Material) -> bool:
	if h < 5.0 or seg_len < 3.0:
		return false
	var wr := RandomNumberGenerator.new()
	wr.seed = hash([snappedf(c.x, 0.01), snappedf(c.z, 0.01)])
	if wr.randf() > 0.6:
		return false
	var g := ground_y(c.x, c.z) - 0.3
	var sill := wr.randf_range(2.2, 2.8)
	var ww := minf(seg_len * wr.randf_range(0.35, 0.5), 2.0)  # window width
	var wh := minf(h - sill - 0.6, wr.randf_range(1.4, 2.2))  # window height
	var pier := (seg_len - ww) * 0.5
	var dims := func(len_along: float, height: float) -> Vector3:
		return Vector3(len_along, height, 0.7) if x_long else Vector3(0.7, height, len_along)
	_block(dims.call(seg_len, sill), Vector3(c.x, g + sill * 0.5, c.z), rot, mat)  # sill wall
	for sgn in [-1.0, 1.0]:  # piers either side of the hole
		var pc: Vector3 = c + along * sgn * (ww * 0.5 + pier * 0.5)
		_block(dims.call(pier, wh), Vector3(pc.x, g + sill + wh * 0.5, pc.z), rot, mat)
	var top := h - sill - wh
	if top > 0.3 and wr.randf() > 0.35:  # lintel + wall above; missing on ~1 in 3: a broken notch
		_block(dims.call(seg_len, top), Vector3(c.x, g + sill + wh + top * 0.5, c.z), rot, mat)
	window_count += 1
	return true

# T439 (user 2026-11-17: floating pieces): the slab used to sit at base + 0.45 full_h in the middle
# of the ruin whatever the walls did, so some hung in the air. Now its low end is in the ground
# and its high end leans on the back wall (side 2, local -z): against the inner face of the
# tallest segment under it, or on top of it when that segment is lower than the slab can reach.
# No plain back segment under it: the slab lies nearly flat in the rubble.
func _collapsed_roof(at: Vector2, w: float, d: float, rot: float, tilt: float, tops: Array, mat: Material) -> void:
	var size := Vector3(w * 0.8, 0.45, d * 0.6)
	var length := size.z
	var basis := Basis(Vector3.UP, rot)
	var low_xz: Vector3 = Vector3(at.x, 0, at.y) + basis * Vector3(0, 0, -d * 0.5 + 0.35 + length)
	var g_low := ground_min(low_xz.x, low_xz.z, size.x * 0.5) - 0.2
	var on_top := false
	if tops.is_empty():
		tilt = 0.06
	else:
		var top: float = tops.max()
		var reach := sin(tilt) * length + cos(tilt) * size.y  # rise of the high top edge
		if reach > top - g_low:  # the wall is lower than the slab's reach: rest on its top
			tilt = asin(clampf((top - g_low) / length, 0.0, 1.0))  # its underside on the top
			on_top = true
	# centre along local z: the high end at the wall's inner face (or 0.4 m onto its top)
	var zc := -d * 0.5 + 0.35 + cos(tilt) * length * 0.5 + sin(tilt) * size.y * 0.5 - (0.4 if on_top else 0.0)
	var yc := g_low + sin(tilt) * length * 0.5 + cos(tilt) * size.y * 0.5
	var c: Vector3 = Vector3(at.x, 0, at.y) + basis * Vector3(0, 0, zc)
	_block(size, Vector3(c.x, yc, c.z), rot, mat, Vector3(tilt, 0, 0))

var window_count := 0  # T288: how many window holes this build cut (probe)

func _ruin(at: Vector2, rng: RandomNumberGenerator) -> void:
	var w := rng.randf_range(12.0, 22.0)
	var d := rng.randf_range(10.0, 18.0)
	var rot := rng.randf_range(0.0, PI)
	var basis := Basis(Vector3.UP, rot)
	var wall_mat := _brick_mat(CONCRETE.darkened(rng.randf_range(0.0, 0.25)))  # T448: adobe bricks
	var rust_mat := _mat(RUST.darkened(rng.randf_range(0.0, 0.2)))
	var full_h := rng.randf_range(6.0, 11.0)
	# 4 walls, each in 4 segments of uneven height; some segments gone (breaches, doors)
	var back_tops: Array = []  # T439: top y of each plain segment of the back wall (side 2)
	for side in 4:
		var length: float = w if side % 2 == 0 else d
		var off: Vector3 = basis * (Vector3(0, 0, d * 0.5) if side == 0 else Vector3(0, 0, -d * 0.5) if side == 2
			else Vector3(w * 0.5, 0, 0) if side == 1 else Vector3(-w * 0.5, 0, 0))
		var along: Vector3 = basis * (Vector3.RIGHT if side % 2 == 0 else Vector3.BACK)
		var segs := 5
		for k in segs:
			if rng.randf() < 0.28:
				continue  # breach
			var h := full_h * rng.randf_range(0.25, 1.0)
			var seg_len := length / segs - 0.15
			var c := Vector3(at.x, 0, at.y) + off + along * ((float(k) + 0.5) / segs - 0.5) * length
			if not _window_wall(c, along, side % 2 == 0, seg_len, h, rot, wall_mat):
				_block(Vector3(seg_len, h, 0.7) if side % 2 == 0 else Vector3(0.7, h, seg_len),
					Vector3(c.x, ground_y(c.x, c.z) + h * 0.5 - 0.3, c.z), rot, wall_mat)
				if side == 2 and absf(((float(k) + 0.5) / segs - 0.5) * length) < w * 0.4:
					back_tops.append(ground_y(c.x, c.z) - 0.3 + h)
	if rng.randf() < 0.6:  # collapsed roof: a slab resting on one wall, tilted to the ground
		var tilt := deg_to_rad(rng.randf_range(14.0, 26.0))
		_collapsed_roof(at, w, d, rot, tilt, back_tops, rust_mat)
	for k in rng.randi_range(4, 8):  # rubble
		var r := Vector2(rng.randf_range(-w, w), rng.randf_range(-d, d)) * 0.7
		var s := Vector3(rng.randf_range(0.6, 2.0), rng.randf_range(0.4, 1.2), rng.randf_range(0.6, 2.0))
		var p := at + r
		_block(s, Vector3(p.x, ground_y(p.x, p.y) + s.y * 0.35, p.y), rng.randf() * PI,
			wall_mat if k % 3 else rust_mat, Vector3(rng.randf_range(-0.3, 0.3), 0, rng.randf_range(-0.3, 0.3)))
