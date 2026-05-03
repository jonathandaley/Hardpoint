extends Control
# Circular beacon indicator drawn in _draw().
# Ring color = ownership state. Inner arc = capture progress (clockwise from 12).

var state: int = 0
var progress: float = 0.0
var cap_team: int = -1

const _STATE_COLORS: Array = [
	Color(0.4, 0.4, 0.4),
	Color(0.2, 0.5, 1.0),
	Color(1.0, 0.3, 0.2),
	Color(1.0, 0.85, 0.0),
]
const _TEAM_COLORS: Array = [Color(0.2, 0.5, 1.0), Color(1.0, 0.3, 0.2)]

func _draw() -> void:
	var c := size * 0.5
	var r: float = minf(c.x, c.y) - 2.0
	var s: int = clampi(state, 0, 3)
	draw_arc(c, r, 0.0, TAU, 48, _STATE_COLORS[s], 2.0, false)
	if progress > 0.001 and cap_team >= 0 and cap_team < 2:
		var col: Color = _TEAM_COLORS[cap_team]
		var a0: float = -PI * 0.5
		draw_arc(c, r - 3.0, a0, a0 + TAU * progress, 48, col, 3.0, false)
