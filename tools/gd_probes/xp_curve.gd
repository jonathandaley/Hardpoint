extends Node3D
# T536 probe (user 2026-11-20: "Xp during a match is good, have it count healing (of teammates) as well. Maybe
# have xp-per-level increase by 10% per level."): level_for_xp on the 1.1x curve (99 -> 1, 100 -> 2, 1358 ->
# 10, 5116 -> 20 = max); match_xp = 5 a kill + 5 a capture + 1 / 100 dealt + 1 / 50 healed; a field repair
# tick credits the healer with what its teammates actually got, never itself.
const MD := preload("res://resources/mechs/Heron.tres")

func _mech(team: int, at: Vector3) -> Node:
	var m: Node3D = MD.scene.instantiate()
	add_child(m)
	m.set_physics_process(false)
	m.set("team", team)
	m.global_position = at
	return m

func _ready() -> void:
	var bad: Array = []
	for c in [[0, 1], [99, 1], [100, 2], [209, 2], [210, 3], [1358, 10], [5115, 19], [5116, 20], [99999, 20]]:
		if Game.level_for_xp(c[0]) != c[1]:
			bad.append("level_for_xp(%d) = %d, want %d" % [c[0], Game.level_for_xp(c[0]), c[1]])
	var mx: int = Game.match_xp({"kills": 4, "captures": 3, "dealt": 2000.0, "healed": 500.0})
	if mx != 65:
		bad.append("match_xp(4 kills, 3 caps, 2000 dealt, 500 healed) = %d, want 65" % mx)
	if Game.match_xp({}) != 0:
		bad.append("match_xp({}) = %d" % Game.match_xp({}))
	var heron := _mech(0, Vector3.ZERO)
	var mate := _mech(0, Vector3(5, 0, 0))
	var foe := _mech(1, Vector3(-5, 0, 0))
	for m in [heron, mate, foe]:
		m.set("max_health", 500.0)
	heron.set("health", 100.0)   # hurt itself: healing itself must not count
	mate.set("health", 495.0)    # 5 HP short: only 5 counts however much the tick gives
	foe.set("health", 100.0)     # another team: not healed
	heron.call("_field_repair_tick", 1.0)
	var got: float = heron.get("healed_others_total")
	if absf(got - 5.0) > 0.01:
		bad.append("one field repair tick credited %.2f HP (want 5: the teammate's missing 5, not the Heron's own)" % got)
	if float(foe.get("health")) != 100.0:
		bad.append("the field repair healed another team (%.1f)" % float(foe.get("health")))
	if not bad.is_empty():
		push_error("[probe] xp_curve FAIL: " + "; ".join(bad))
		get_tree().quit(1)
		return
	print("[probe] xp_curve done (lv 10 at 1358 XP, lv 20 at 5116; match XP 65; field repair credited 5)")
	get_tree().quit(0)
