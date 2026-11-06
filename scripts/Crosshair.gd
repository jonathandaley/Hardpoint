extends Control

const GAP          := 2.0  # between the centre dot and each arm (canvas px, symmetric)
const LINE_LEN     := 3.0
const LINE_WIDTH   := 1.0
const COLOR        := Color(1.0, 1.0, 1.0, 0.9)
const OUTLINE      := Color(0.0, 0.0, 0.0, 0.6)  # T168: dark rim so it reads on white walls/snow

const HIT_GAP      := 4.5
const HIT_LEN      := 6.0
const HIT_WIDTH    := 1.5
const HIT_COLOR    := Color(1.0, 0.1, 0.1, 1.0)
const HIT_DURATION := 0.15

const LOCK_ARM_LEN   := 7.0   # length of each L arm
const LOCK_DIST_FAR  := 24.0  # corner distance from center at progress=0
const LOCK_DIST_NEAR := 9.0   # corner distance from center at progress=1
const LOCK_COLOR_MID := Color(1.0, 0.85, 0.0, 0.95)
const LOCK_COLOR_ON  := Color(0.0, 1.0, 0.25, 1.0)

var _hit_timer: float = 0.0
var _lock_progress: float = 0.0

func register_hit() -> void:
	_hit_timer = HIT_DURATION
	queue_redraw()

func set_lock_progress(p: float) -> void:
	if _lock_progress != p:
		_lock_progress = p
		queue_redraw()

func _process(delta: float) -> void:
	if _hit_timer > 0.0:
		_hit_timer -= delta
		queue_redraw()

# T276 (HUMAN_FOUND 2026-11-05, top priority: "too hard to see through. Make it only the
# current width at the edges, and narrow it to a point in the middle"): no centre dot; each
# arm is a wedge, LINE_WIDTH wide at its outer end (where the old arm ended) tapering to a
# point at the centre, so the aim point itself is open. Outline wedges drawn first.
static func arm_wedges(c: Vector2, rim := 0.0) -> Array[PackedVector2Array]:
	var reach := LINE_WIDTH * 0.5 + GAP + LINE_LEN + rim
	var hw := LINE_WIDTH * 0.5 + rim
	var out: Array[PackedVector2Array] = []
	for d: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		var side := Vector2(-d.y, d.x) * hw
		out.append(PackedVector2Array([c + d * reach + side, c + d * reach - side, c]))
	return out

func _draw() -> void:
	var c := size * 0.5
	for poly in arm_wedges(c, 1.0):
		draw_colored_polygon(poly, OUTLINE)
	for poly in arm_wedges(c):
		draw_colored_polygon(poly, COLOR)

	if _lock_progress > 0.0:
		var dist := lerpf(LOCK_DIST_FAR, LOCK_DIST_NEAR, _lock_progress)
		var lk_color: Color
		if _lock_progress < 0.5:
			lk_color = COLOR.lerp(LOCK_COLOR_MID, _lock_progress * 2.0)
		else:
			lk_color = LOCK_COLOR_MID.lerp(LOCK_COLOR_ON, (_lock_progress - 0.5) * 2.0)
		var arm := LOCK_ARM_LEN
		for sx: float in [-1.0, 1.0]:
			for sy: float in [-1.0, 1.0]:
				var corner := c + Vector2(sx * dist, sy * dist).rotated(PI / 4.0)
				var rarm1 := Vector2(-sx * arm, 0.0).rotated(PI / 4.0)
				var rarm2 := Vector2(0.0, -sy * arm).rotated(PI / 4.0)
				draw_line(corner, corner + rarm1, lk_color, LINE_WIDTH)
				draw_line(corner, corner + rarm2, lk_color, LINE_WIDTH)

	if _hit_timer > 0.0:
		for d: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			var dn := d.normalized()
			draw_line(c + dn * HIT_GAP, c + dn * (HIT_GAP + HIT_LEN), HIT_COLOR, HIT_WIDTH)
