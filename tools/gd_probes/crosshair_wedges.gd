extends Node
# T276 + T309 probe (HUMAN_FOUND 2026-11-05: crosshair "too hard to see through"; user on T276:
# "thin the center even more ... use the fractional pixels to make it super accurate"): no
# centre dot (no filled rects); each arm is LINE_WIDTH wide at the old arm end and narrows,
# never widening, to a hairline (< 0.3 unit) near the centre; the dark rim is gone well before
# the colour thins out (no rim on the inner half), so the centre stays clear.

func _fail(msg: String) -> void:
	push_error("[probe] crosshair_wedges FAIL: " + msg)
	get_tree().quit(1)

func _ready() -> void:
	var script: Script = load("res://scripts/Crosshair.gd")
	if script.source_code.contains("draw_rect("):
		_fail("still draws rects (the centre dot / square arms)")
		return
	if not script.source_code.contains("func arm_profile"):
		_fail("no arm_profile() (T309 taper)")
		return
	var consts: Dictionary = script.get_script_constant_map()
	var w: float = consts["LINE_WIDTH"]
	var reach: float = w * 0.5 + float(consts["GAP"]) + float(consts["LINE_LEN"])
	var prof: Array = script.call("arm_profile")
	if absf(float(prof[0][0]) - reach) > 0.01 or absf(float(prof[0][1]) * 2.0 - w) > 0.01:
		_fail("outer end %.2f wide at %.2f, want %.2f wide at the old arm end %.2f" % [float(prof[0][1]) * 2.0, float(prof[0][0]), w, reach])
		return
	var last_w := INF
	for p: Array in prof:
		var width: float = float(p[1]) * 2.0
		if width > last_w + 0.0001:
			_fail("arm widens toward the centre at %.2f" % float(p[0]))
			return
		last_w = width
		if float(p[0]) < reach * 0.5 and float(p[2]) > 0.0:
			_fail("dark rim reaches the inner half (at %.2f)" % float(p[0]))
			return
	var near: Array = []
	for p: Array in prof:
		if float(p[0]) > 0.0 and float(p[0]) <= reach * 0.25:
			near.append(p)
	if near.is_empty() or float(near[0][1]) * 2.0 >= 0.3:
		_fail("arm still %.2f unit wide near the centre, want a hairline < 0.3" % (float(near[0][1]) * 2.0 if not near.is_empty() else -1.0))
		return
	print("[probe] crosshair_wedges done (%.2f wide outside -> %.3f at %.2f from the centre)" % [w, float(near[0][1]) * 2.0, float(near[0][0])])
	get_tree().quit(0)
