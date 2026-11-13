extends Node
# T369 probe (HUMAN_FOUND 2026-11-09: "Bots in hangar point their weapons 30 degrees down, should
# be level"): display mechs (lineup + detail diorama) hold every gun level -- the in-match gun
# tilt (T329 / T353) aimed them at their own unused camera's view, clamped down at TILT_MAX.

func _fail(msg: String) -> void:
	push_error("[probe] hangar_guns_level: " + msg)

func _tilts(m: Node) -> Array:
	var out: Array = []
	for hp in m.get("torso").get_children():
		if hp.name.begins_with("Hardpoint"):
			out.append(snappedf((hp as Node3D).rotation.x, 0.01))
	return out

func _level(m: Node, what: String) -> void:
	var ts := _tilts(m)
	if ts.is_empty():
		_fail("%s has no hardpoints" % what)
	for t in ts:
		if absf(t) > 0.01:
			_fail("%s guns tilt %s rad (want level)" % [what, ts])
			return

func _ready() -> void:
	var h: Node = load("res://scenes/ui/Hangar.tscn").instantiate()
	get_tree().root.add_child.call_deferred(h)
	for i in 10:
		await get_tree().process_frame
	var seen := 0
	for m in h.get("_squad_nodes"):
		if m != null:
			_level(m, "lineup mech %s" % m.name)
			seen += 1
	if seen == 0:
		_fail("no lineup mechs")
	h._on_slot_btn_pressed(0)
	for i in 10:
		await get_tree().process_frame
	_level(h.get("_diorama_mech_node"), "diorama mech")
	print("[probe] hangar_guns_level done")
	get_tree().quit(0)
