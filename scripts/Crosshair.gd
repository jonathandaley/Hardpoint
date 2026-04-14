extends Control

const DOT_RADIUS  := 1.5
const GAP         := 4.0
const LINE_LEN    := 5.0
const LINE_WIDTH  := 1.0
const COLOR       := Color(1.0, 1.0, 1.0, 0.9)

func _draw() -> void:
	var c := size * 0.5
	draw_circle(c, DOT_RADIUS, COLOR)
	# up
	draw_line(c + Vector2(0, -(GAP + LINE_LEN)), c + Vector2(0, -GAP), COLOR, LINE_WIDTH)
	# down
	draw_line(c + Vector2(0,  GAP), c + Vector2(0,  GAP + LINE_LEN), COLOR, LINE_WIDTH)
	# left
	draw_line(c + Vector2(-(GAP + LINE_LEN), 0), c + Vector2(-GAP, 0), COLOR, LINE_WIDTH)
	# right
	draw_line(c + Vector2( GAP, 0), c + Vector2( GAP + LINE_LEN, 0), COLOR, LINE_WIDTH)
