class_name StatBar
extends Control
# T537 (user 2026-11-20: "Weapon and mech descriptions should have a visual added to their basic stats: a
# sliding scale that shows each's stats on a linear scale compared to the current minimum and maximum
# available." + "compare each weapon only to its own slot size"): a chunky bar beside a stat line. Filled
# from the left up to the value's place between the lowest and highest of its kind (a sliver for the
# lowest); a value that is a range (damage low - high) draws as the span between its two places.

const W := 60.0
const H := 6.0
const TRACK := Color(0.16, 0.18, 0.21)
const FILL := Color(0.86, 0.66, 0.24)  # the hangar's amber
const SPAN_LEAD := Color(0.86, 0.66, 0.24, 0.35)

var lo := 0.0  # 0..1, the value (or the range's low end)
var hi := 0.0  # 0..1, the range's high end (= lo for a single value)

static func make(v_lo: float, v_hi: float, min_v: float, max_v: float) -> StatBar:
	var b := StatBar.new()
	var span := maxf(max_v - min_v, 0.0001)
	b.lo = clampf((v_lo - min_v) / span, 0.0, 1.0)
	b.hi = clampf((v_hi - min_v) / span, 0.0, 1.0)
	b.custom_minimum_size = Vector2(W, H)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(W, H)), TRACK)
	var x_hi := maxf(2.0, roundf(W * hi))  # whole pixels: chunky, never blurred
	if hi > lo + 0.001:
		var x_lo := roundf(W * lo)
		draw_rect(Rect2(0, 0, x_lo, H), SPAN_LEAD)
		draw_rect(Rect2(x_lo, 0, maxf(2.0, x_hi - x_lo), H), FILL)
	else:
		draw_rect(Rect2(0, 0, x_hi, H), FILL)
