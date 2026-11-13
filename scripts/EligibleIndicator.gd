extends Control

# T257 (HUMAN_FOUND_ISSUES 2026-11-05 "square corners, 4pc"): the soft-lock box is four
# square corner pieces instead of a full red square. Lock-on brackets are separate (HUD).
const SQ_COLOR := Color(1.0, 0.0, 0.0, 0.85)
const SQ_WIDTH := 1.5
const CORNER := 0.3  # each arm, as a fraction of the box side

static func corner_lines(s: Vector2) -> PackedVector2Array:
	var a := s * CORNER
	var out := PackedVector2Array()
	for c: Vector2 in [Vector2.ZERO, Vector2(s.x, 0), s, Vector2(0, s.y)]:
		var dx := a.x if c.x == 0.0 else -a.x
		var dy := a.y if c.y == 0.0 else -a.y
		out.append(c); out.append(c + Vector2(dx, 0))
		out.append(c); out.append(c + Vector2(0, dy))
	return out

# T408 (HUMAN_FOUND: "Targeting reticle should be grey if no equipped weapon is within range"): HUD sets it
const OUT_OF_RANGE := Color(0.6, 0.6, 0.6, 0.7)
var color := SQ_COLOR

func _draw() -> void:
	draw_multiline(corner_lines(size), color, SQ_WIDTH)
