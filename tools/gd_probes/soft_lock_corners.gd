extends Node
# T257: the soft-lock indicator draws four corner pieces (8 segments) and leaves the
# middle of every edge open.

func _ready() -> void:
	var script: Script = load("res://scripts/EligibleIndicator.gd")
	if not script.source_code.contains("func corner_lines"):
		push_error("[probe] soft_lock_corners FAIL: no corner_lines()")
		get_tree().quit(1); return
	var s := Vector2(19, 19)
	var pts: PackedVector2Array = script.call("corner_lines", s)
	if pts.size() != 16:
		push_error("[probe] soft_lock_corners FAIL: %d points, want 16" % pts.size())
		get_tree().quit(1); return
	for mid: Vector2 in [Vector2(s.x / 2, 0), Vector2(s.x, s.y / 2), Vector2(s.x / 2, s.y), Vector2(0, s.y / 2)]:
		for i in range(0, pts.size(), 2):
			if Geometry2D.get_closest_point_to_segment(mid, pts[i], pts[i + 1]).distance_to(mid) < 0.5:
				push_error("[probe] soft_lock_corners FAIL: edge middle %s is drawn" % mid)
				get_tree().quit(1); return
	print("[probe] soft_lock_corners done")
	get_tree().quit(0)
