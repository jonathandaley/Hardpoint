extends Node
# T276 probe (HUMAN_FOUND 2026-11-05, top priority: crosshair "too hard to see through ...
# only the current width at the edges, and narrow it to a point in the middle"): four arm
# wedges, LINE_WIDTH wide where the old arms ended, each tapering to a point at the centre,
# and no centre dot (no filled rect over the aim point).

func _fail(msg: String) -> void:
	push_error("[probe] crosshair_wedges FAIL: " + msg)
	get_tree().quit(1)

func _ready() -> void:
	var script: Script = load("res://scripts/Crosshair.gd")
	if not script.source_code.contains("func arm_wedges"):
		_fail("no arm_wedges()")
		return
	if script.source_code.contains("draw_rect("):
		_fail("still draws rects (the centre dot / square arms)")
		return
	var c := Vector2(320, 180)
	var w: float = script.get_script_constant_map()["LINE_WIDTH"]
	var reach: float = w * 0.5 + float(script.get_script_constant_map()["GAP"]) + float(script.get_script_constant_map()["LINE_LEN"])
	var polys: Array = script.call("arm_wedges", c)
	if polys.size() != 4:
		_fail("%d arms, want 4" % polys.size())
		return
	for poly: PackedVector2Array in polys:
		if poly.size() != 3 or not poly[2].is_equal_approx(c):
			_fail("arm %s does not taper to the centre" % poly)
			return
		if absf(poly[0].distance_to(poly[1]) - w) > 0.01:
			_fail("arm outer end %.2f wide, want %.2f" % [poly[0].distance_to(poly[1]), w])
			return
		if absf(((poly[0] + poly[1]) * 0.5).distance_to(c) - reach) > 0.01:
			_fail("arm reaches %.2f, want the old arm end %.2f" % [((poly[0] + poly[1]) * 0.5).distance_to(c), reach])
			return
	print("[probe] crosshair_wedges done (4 wedges, %.1f px reach, %.1f px at the edge)" % [reach, w])
	get_tree().quit(0)
