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
var _t := 0.0

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
