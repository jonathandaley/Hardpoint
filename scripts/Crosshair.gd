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

# T276 + T309 (user: "thin the center even more ... use the fractional pixels to make it super
# accurate. The points can come in toward the center a bit if they can get thin enough"): no
# centre dot; each arm runs from LINE_WIDTH wide at the old arm end (REACH from the centre) to a
# hairline at the centre, narrowing on a concave curve (TAPER_POW), drawn as short antialiased
# segments so sub-pixel widths fade instead of dropping out (the 640x360 canvas is drawn at
# screen resolution: 0.5 unit = 1.5 px at 1080p). The dark rim only lines the outer half and
# thins to nothing, so the inner hairline stays clear over the target.
const REACH := LINE_WIDTH * 0.5 + GAP + LINE_LEN
const TAPER_POW := 1.6
const RIM := 0.5        # extra half-width of the dark rim at the outer end (was a full unit)
const ARM_STEPS := 10

## [distance from centre, colour half-width, rim extra half-width] from the outer end inward.
static func arm_profile() -> Array:
	var out: Array = []
	for k in ARM_STEPS + 1:
		var d := REACH * (1.0 - float(k) / ARM_STEPS)
		var f := d / REACH
		out.append([d, LINE_WIDTH * 0.5 * pow(f, TAPER_POW), RIM * clampf((f - 0.5) * 2.0, 0.0, 1.0)])
	return out

func _draw() -> void:
	var c := size * 0.5
	var prof := arm_profile()
	for layer in 2:  # 0 = rim under, 1 = colour on top
		for dir: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
			for k in prof.size() - 1:
				var a: Array = prof[k]
				var b: Array = prof[k + 1]
				var hw: float = (float(a[1]) + float(b[1])) * 0.5 + (((float(a[2]) + float(b[2])) * 0.5) if layer == 0 else 0.0)
				if layer == 0 and float(a[2]) <= 0.0:
					continue
				draw_line(c + dir * float(a[0]), c + dir * float(b[0]), OUTLINE if layer == 0 else COLOR, hw * 2.0, true)

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
