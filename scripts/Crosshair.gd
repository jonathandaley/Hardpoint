extends Control

const GAP_POS      := 1.0  # down, right
const GAP_NEG      := 2.0  # up, left
const LINE_LEN     := 3.0
const LINE_WIDTH   := 1.0
const COLOR        := Color(1.0, 1.0, 1.0, 0.9)

const HIT_GAP      := 3.0
const HIT_LEN      := 4.0
const HIT_COLOR    := Color(1.0, 0.1, 0.1, 1.0)
const HIT_DURATION := 0.15

var _hit_timer: float = 0.0

func register_hit() -> void:
	_hit_timer = HIT_DURATION
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

	if _hit_timer > 0.0:
		for d: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			var dn := d.normalized()
			draw_line(c + dn * HIT_GAP, c + dn * (HIT_GAP + HIT_LEN), HIT_COLOR, LINE_WIDTH)
