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

func _draw() -> void:
	# T168: pixel-aligned + symmetric. The old version centred 1-px marks on a pixel
	# corner (blurry dot) and offset the gaps 2/1 px, so the cross looked shifted.
	var w := LINE_WIDTH
	var p := (size * 0.5 - Vector2(w, w) * 0.5).floor()  # top-left of the centre dot
	var c := p + Vector2(w, w) * 0.5                    # geometric centre (brackets, hit X)
	var marks: Array[Rect2] = [
		Rect2(p.x, p.y, w, w),                          # centre dot
		Rect2(p.x, p.y - GAP - LINE_LEN, w, LINE_LEN),  # up
		Rect2(p.x, p.y + w + GAP, w, LINE_LEN),         # down
		Rect2(p.x - GAP - LINE_LEN, p.y, LINE_LEN, w),  # left
		Rect2(p.x + w + GAP, p.y, LINE_LEN, w),         # right
	]
	for r in marks:
		draw_rect(r.grow(1.0), OUTLINE)
	for r in marks:
		draw_rect(r, COLOR)

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
