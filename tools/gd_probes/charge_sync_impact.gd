extends Node
# T473 probe (the charge's snapshot sync, from B147's lunge_sync_impact): the owner's predicted
# Taurus runs ~a round trip ahead of the server's copy, so it meets a wall first; its impact must
# STAND while the server's snapshots still show the charge behind it, and drop once the server's own
# clock passes the impact still charging (the server met nothing there). A server ram or pull-up we
# didn't have (its RPC late) ends ours there; a new charge the server set off out of our pull-up is
# taken up; a charge we never started starts on the server's clock.

const Charge := preload("res://resources/abilities/Charge.tres")

func _fail(msg: String) -> void:
	push_error("[probe] charge_sync_impact FAIL: " + msg)
	get_tree().quit(1)

func _ready() -> void:
	var md: Resource = load("res://resources/mechs/Taurus.tres")
	var m: Node3D = md.scene.instantiate()
	add_child(m)
	m.set_physics_process(false)
	m.call("configure_abilities", [Charge])
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	var lead := 18  # ticks: the 160 ms link's round trip
	var fwd := Vector3.FORWARD
	# A: we hit a wall at 1.5; the server's snapshot (a round trip old) still charges at 1.2
	m.call("_lunge_begin", fwd, 1.5, 0.9)
	m.call("_lunge_impact")
	m.call("_lunge_sync", {"lt": 1.2, "ld": fwd, "lv": 0.9, "le": -1.0, "lh": false}, lead)
	if not m.get("_lunge_hit") or not m.get("lunging"):
		_fail("our wall impact was dropped by a snapshot from before the server's copy got there")
		return
	# B: the server's own clock is past our impact, still charging: ours was local -> charge on
	m.call("_lunge_sync", {"lt": 1.6, "ld": fwd, "lv": 0.9, "le": -1.0, "lh": false}, lead)
	if m.get("_lunge_hit") or not m.call("charging") or absf(float(m.get("lunge_t")) - (1.6 + lead * dt)) > 0.001:
		_fail("the server charged past our impact point and ours stayed stopped (hit=%s, lunge_t %.3f)" % [m.get("_lunge_hit"), m.get("lunge_t")])
		return
	# C: the server rammed something we didn't (its RPC late): stop there too
	m.call("_lunge_begin", fwd, 1.0, 0.9)
	m.call("_lunge_sync", {"lt": 1.2, "ld": fwd, "lv": 0.9, "le": 1.1, "lh": true}, 0)
	if not m.get("_lunge_hit") or absf(float(m.get("_charge_end_t")) - 1.1) > 0.001:
		_fail("the server's charge hit something and ours charged on")
		return
	# D: the server pulled up (its RPC late): bleed off from there
	m.call("_lunge_begin", fwd, 1.0, 0.9)
	m.call("_lunge_sync", {"lt": 1.3, "ld": fwd, "lv": 0.9, "le": 1.25, "lh": false}, 0)
	if m.get("_lunge_hit") or m.call("charging") or absf(float(m.get("_charge_end_t")) - 1.25) > 0.001:
		_fail("the server pulled up and ours charged on (end %.3f)" % float(m.get("_charge_end_t")))
		return
	# E: a new charge the server set off out of that pull-up (its _rpc_lunge late): take it up
	m.call("_lunge_sync", {"lt": 0.1, "ld": Vector3.RIGHT, "lv": 3.0, "le": -1.0, "lh": false}, lead)
	if not m.call("charging") or absf(float(m.get("_charge_v0")) - 3.0) > 0.001 or absf(float(m.get("lunge_t")) - (0.1 + lead * dt)) > 0.001:
		_fail("a new charge out of a pull-up wasn't taken up (charging %s, v0 %.2f, t %.3f)" % [m.call("charging"), m.get("_charge_v0"), m.get("lunge_t")])
		return
	# F: one we never started: start on the server's clock
	m.call("_lunge_end")
	m.set("_lunge_begin_ms", -100000)
	m.call("_lunge_sync", {"lt": 0.5, "ld": fwd, "lv": 0.9, "le": -1.0, "lh": false}, lead)
	if not m.call("charging") or absf(float(m.get("lunge_t")) - (0.5 + lead * dt)) > 0.001:
		_fail("a charge we never started didn't start from the snapshot")
		return
	print("[probe] charge_sync_impact done")
	m.free()
	get_tree().quit(0)
