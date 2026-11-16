extends Node
# B147 probe (T404 lunge v2): the owner's predicted Taurus runs ~a round trip ahead of the server's
# copy, so it meets a wall first. Its impact must STAND while the server's snapshots still show the
# dash behind it (it used to be dropped every snapshot: back into the wall, 0.1 m stop-start); it is
# dropped only once the server's own clock passes the impact still dashing (the server met nothing
# there); and a server impact we didn't have settles ours.

func _fail(msg: String) -> void:
	push_error("[probe] lunge_sync_impact FAIL: " + msg)
	get_tree().quit(1)

func _ready() -> void:
	var md: Resource = load("res://resources/mechs/Taurus.tres")
	var m: Node3D = md.scene.instantiate()
	add_child(m)
	m.set_physics_process(false)
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	var settle0: float = Mech.LUNGE_WINDUP_S + Mech.LUNGE_DASH_S + Mech.LUNGE_STOP_S
	var hit_t := 0.833
	var lead := 18  # ticks: the 160 ms link's round trip
	# A: we hit a wall at 0.833; the server's snapshot (a round trip old) still dashes at 0.60
	m.call("_lunge_begin", Vector3.FORWARD, hit_t)
	m.call("_lunge_impact")
	m.call("_lunge_sync", {"lt": 0.60}, lead)
	if not m.get("_lunge_hit") or float(m.get("lunge_t")) < settle0 - 0.001:
		_fail("our wall impact was dropped by a snapshot from before the server's copy got there (hit=%s, lunge_t %.3f)" % [m.get("_lunge_hit"), m.get("lunge_t")])
		return
	# B: the server's own clock is past our impact, still dashing: ours was local -> dash on
	m.call("_lunge_sync", {"lt": hit_t + 0.1}, lead)
	if m.get("_lunge_hit") or absf(float(m.get("lunge_t")) - (hit_t + 0.1 + lead * dt)) > 0.001:
		_fail("the server dashed past our impact point and we stayed settled (hit=%s, lunge_t %.3f)" % [m.get("_lunge_hit"), m.get("lunge_t")])
		return
	# C: the server hit something we didn't: settle too
	m.call("_lunge_begin", Vector3.FORWARD, 0.7)
	m.call("_lunge_sync", {"lt": settle0 + 0.01}, 0)
	if not m.get("_lunge_hit"):
		_fail("the server's lunge settled (it hit something) and ours dashed on")
		return
	print("[probe] lunge_sync_impact done")
	m.free()
	get_tree().quit(0)
