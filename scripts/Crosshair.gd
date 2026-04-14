extends Control

const DOT_RADIUS   := 0.5
const GAP          := 2.0
const LINE_LEN     := 2.5
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
	var c := size * 0.5
	draw_circle(c, DOT_RADIUS, COLOR)
	draw_line(c + Vector2(0, -(GAP + LINE_LEN)), c + Vector2(0, -GAP),          COLOR, LINE_WIDTH)
	draw_line(c + Vector2(0,  GAP),              c + Vector2(0,  GAP + LINE_LEN), COLOR, LINE_WIDTH)
	draw_line(c + Vector2(-(GAP + LINE_LEN), 0), c + Vector2(-GAP, 0),           COLOR, LINE_WIDTH)
	draw_line(c + Vector2( GAP, 0),              c + Vector2( GAP + LINE_LEN, 0), COLOR, LINE_WIDTH)

	if _hit_timer > 0.0:
		for d: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			var dn := d.normalized()
			draw_line(c + dn * HIT_GAP, c + dn * (HIT_GAP + HIT_LEN), HIT_COLOR, LINE_WIDTH)
