extends Control

const SQ_COLOR := Color(1.0, 0.0, 0.0, 0.85)
const SQ_WIDTH := 1.5

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), SQ_COLOR, false, SQ_WIDTH)
