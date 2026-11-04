extends Control
# T202: north-up top-down minimap (world +X right, world -Z up). Corner widget
# during play; the HUD enlarges it as the spawn picker (T203). Draws the map
# outline, beacons coloured from the local player's side (own blue, enemy red,
# neutral grey, contested yellow), every live mech that isn't stealthed, and the
# local mech as a heading triangle.

const ALLY      := Color(0.2, 0.5, 1.0)
const ENEMY     := Color(1.0, 0.3, 0.2)
const NEUTRAL   := Color(0.6, 0.6, 0.6)
const CONTESTED := Color(1.0, 0.85, 0.0)
const REDRAW_S  := 0.1

var arena: Node = null                    # reads _team_mechs + player_mech
var local_team := 0
var center := Vector2.ZERO                # world XZ of the map centre
var half := 100.0                         # metres from the centre to the map edge
var outline := PackedVector2Array()       # world XZ boundary polygon
var beacons: Array = []
var bg_alpha := 0.55                      # the spawn picker darkens it (T203)
var features: Array = []                  # T239: world-XZ footprint polygons (walls, buildings, trees, rocks)
var _t := 0.0

const FEATURE_COLOR := Color(1, 1, 1, 0.16)

# T239 (HUMAN_FOUND_ISSUES 2026-11-04: "minimal terrain features on the minimap"): the
# footprints of the map's solid colliders, taken once from its geometry -- no per-map code.
# Skipped: shapes under 1 m tall (floors, pads, steps), anything covering a quarter of the
# map or more (floor and ceiling slabs, terrain), and concave terrain meshes.
func set_features(map: Node) -> void:
	features.clear()
	if map == null:
		return
	var max_area := half * half  # (2 half)^2 / 4
	for col in map.find_children("*", "CollisionShape3D", true, false):
		var cs := col as CollisionShape3D
		if cs.disabled or cs.shape == null or not (cs.get_parent() is StaticBody3D):
			continue
		var pts := _shape_points(cs)
		if pts.is_empty():
			continue
		var lo := INF
		var hi := -INF
		var flat := PackedVector2Array()
		for p in pts:
			lo = minf(lo, p.y)
			hi = maxf(hi, p.y)
			flat.append(Vector2(p.x, p.z))
		if hi - lo < 1.0:
			continue
		var hull := Geometry2D.convex_hull(flat)
		if hull.size() < 3:
			continue
		var area := 0.0
		for i in hull.size() - 1:
			area += hull[i].cross(hull[i + 1])
		if absf(area) * 0.5 >= max_area:
			continue
		hull.remove_at(hull.size() - 1)  # convex_hull closes the loop; draw_colored_polygon doesn't want that
		features.append(hull)

# World-space points outlining a shape (box corners, capsule end circles, convex points).
static func _shape_points(cs: CollisionShape3D) -> PackedVector3Array:
	var xf := cs.global_transform
	var out := PackedVector3Array()
	var sh := cs.shape
	if sh is BoxShape3D:
		var e: Vector3 = (sh as BoxShape3D).size * 0.5
		for sx in [-1, 1]:
			for sy in [-1, 1]:
				for sz in [-1, 1]:
					out.append(xf * Vector3(e.x * sx, e.y * sy, e.z * sz))
	elif sh is CapsuleShape3D or sh is CylinderShape3D:
		var r: float = sh.radius
		var hh: float = (sh.height * 0.5 - (r if sh is CapsuleShape3D else 0.0))
		for end in [-1.0, 1.0]:
			for k in 8:
				var a := k * TAU / 8.0
				out.append(xf * Vector3(cos(a) * r, end * (hh + (r if sh is CapsuleShape3D else 0.0)), sin(a) * r))
	elif sh is ConvexPolygonShape3D:
		for p in (sh as ConvexPolygonShape3D).points:
			out.append(xf * p)
	return out

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func to_map(p: Vector3) -> Vector2:
	return size * 0.5 + (Vector2(p.x, p.z) - center) / half * (minf(size.x, size.y) * 0.5)

func team_color(team: int) -> Color:
	return ALLY if team == local_team else ENEMY

func beacon_color(b: Node) -> Color:
	var s: int = b.get("state")
	if s == 1 or s == 2:
		return team_color(s - 1)
	return CONTESTED if s == 3 else NEUTRAL

# Mechs the map shows: alive, in the world, not stealthed.
func shown_mechs() -> Array:
	var out: Array = []
	if arena == null:
		return out
	for t in 2:
		for m in arena.get("_team_mechs")[t]:
			if is_instance_valid(m) and m.is_inside_tree() and m.visible \
					and not m.get("is_dead") and not m.get("is_stealthy"):
				out.append(m)
	return out

func _process(delta: float) -> void:
	_t += delta
	if _t >= REDRAW_S:
		_t = 0.0
		queue_redraw()

func _draw() -> void:
	var k: float = minf(size.x, size.y) / 100.0   # marker scale: 1 at corner size
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, bg_alpha))
	for f in features:  # T239: faint terrain under everything else
		var poly := PackedVector2Array()
		for w in f:
			poly.append(to_map(Vector3(w.x, 0.0, w.y)))
		draw_colored_polygon(poly, FEATURE_COLOR)
	if outline.size() > 1:
		var pts := PackedVector2Array()
		for w in outline:
			pts.append(to_map(Vector3(w.x, 0.0, w.y)))
		pts.append(pts[0])
		draw_polyline(pts, Color(1, 1, 1, 0.35), 1.5)
	for b in beacons:
		if is_instance_valid(b):
			var c := to_map(b.global_position)
			draw_circle(c, 4.0 * k, beacon_color(b))
			draw_arc(c, 4.0 * k, 0.0, TAU, 20, Color(0, 0, 0, 0.8), 1.0)
	var me: Node = arena.get("player_mech") if arena != null else null
	for m in shown_mechs():
		if m != me:
			draw_circle(to_map(m.global_position), 2.0 * k, team_color(m.get("team")))
	if is_instance_valid(me) and me.is_inside_tree() and not me.get("is_dead"):  # own mech even stealthed
		var torso: Node3D = me.get("torso")
		var f3: Vector3 = -(torso if torso != null else me as Node3D).global_transform.basis.z
		var f := Vector2(f3.x, f3.z).normalized()
		var c := to_map(me.global_position)
		var s := Vector2(-f.y, f.x)
		draw_colored_polygon(PackedVector2Array([c + f * 5.0 * k, c - f * 3.0 * k + s * 3.0 * k,
			c - f * 3.0 * k - s * 3.0 * k]), Color(1, 1, 1))
