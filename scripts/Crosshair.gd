extends Control

const GAP_POS      := 1.0  # down, right
const GAP_NEG      := 2.0  # up, left
const LINE_LEN     := 3.0
const LINE_WIDTH   := 1.0
const COLOR        := Color(1.0, 1.0, 1.0, 0.9)

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
	var c := (size * 0.5).round()
	draw_rect(Rect2(c - Vector2(LINE_WIDTH * 0.5, LINE_WIDTH * 0.5), Vector2(LINE_WIDTH, LINE_WIDTH)), COLOR)
	draw_line(c + Vector2(0, -(GAP_NEG + LINE_LEN)), c + Vector2(0, -GAP_NEG),            COLOR, LINE_WIDTH)
	draw_line(c + Vector2(0,  GAP_POS),              c + Vector2(0,  GAP_POS + LINE_LEN), COLOR, LINE_WIDTH)
	draw_line(c + Vector2(-(GAP_NEG + LINE_LEN), 0), c + Vector2(-GAP_NEG, 0),            COLOR, LINE_WIDTH)
	draw_line(c + Vector2( GAP_POS, 0),              c + Vector2( GAP_POS + LINE_LEN, 0), COLOR, LINE_WIDTH)

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
				var corner := c + Vector2(sx * dist, sy * dist)
				draw_line(corner, corner + Vector2(-sx * arm, 0.0), lk_color, LINE_WIDTH)
				draw_line(corner, corner + Vector2(0.0, -sy * arm), lk_color, LINE_WIDTH)

	if _hit_timer > 0.0:
		for d: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			var dn := d.normalized()
			draw_line(c + dn * HIT_GAP, c + dn * (HIT_GAP + HIT_LEN), HIT_COLOR, HIT_WIDTH)
