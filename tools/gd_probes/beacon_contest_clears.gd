extends Node3D
# B116 / T297 probe (HUMAN_FOUND 2026-11-05: "Beacon contested in stealth stays contested
# indefinitely"): a beacon contested by both teams goes back to its owner's state as soon as
# only one team -- or none -- is left in the zone (it stayed CONTESTED until the next capture).

class Body extends Node3D:
	var team := 0
	var is_dead := false

func _ready() -> void:
	var b: Node3D = (load("res://scenes/beacon/Beacon.tscn") as PackedScene).instantiate()
	add_child(b)
	await get_tree().process_frame
	b.set_process(false)  # drive _update_capture by hand
	var a := Body.new()
	a.team = 0
	var e := Body.new()
	e.team = 1
	for m in [a, e]:
		add_child(m)
		m.add_to_group("mechs")
		b.call("_on_body_entered", m)
	b.call("_update_capture", 0.1)
	var msg := ""
	if int(b.get("state")) != 3:  # State.CONTESTED
		msg = "two teams in the zone didn't contest it (state %d)" % int(b.get("state"))
	b.call("_on_body_exited", e)  # team 1 leaves (or cloaks away)
	b.call("_update_capture", 0.1)
	if msg == "" and int(b.get("state")) == 3:
		msg = "still CONTESTED after team 1 left the zone"
	b.call("_on_body_exited", a)
	b.call("_update_capture", 0.1)
	if msg == "" and int(b.get("state")) == 3:
		msg = "still CONTESTED with the zone empty"
	if msg != "":
		push_error("[probe] beacon_contest_clears FAIL: " + msg)
		get_tree().quit(1)
		return
	print("[probe] beacon_contest_clears done")
	get_tree().quit(0)
