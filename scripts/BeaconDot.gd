extends Control
# Circular beacon indicator drawn in _draw().
# Ring color = ownership state. Inner arc = capture progress (clockwise from 12).

var state: int = 0
var progress: float = 0.0
var cap_team: int = -1

const _NEUTRAL := Color(0.4, 0.4, 0.4)
const _CONTESTED := Color(1.0, 0.85, 0.0)

func _draw() -> void:
	var c := size * 0.5
	var r: float = minf(c.x, c.y) - 2.0
	var s: int = clampi(state, 0, 3)
	var ring: Color = _NEUTRAL if s == 0 else _CONTESTED if s == 3 else Game.team_color(s - 1)  # T506
	draw_arc(c, r, 0.0, TAU, 48, ring, 2.0, false)
	if progress > 0.001 and cap_team >= 0 and cap_team < 2:
		var col: Color = Game.team_color(cap_team)
		var a0: float = -PI * 0.5
		draw_arc(c, r - 3.0, a0, a0 + TAU * progress, 48, col, 3.0, false)
