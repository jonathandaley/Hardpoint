extends Node
# T432 probe (user 2026-11-16: "The new buttons to rotate a mech in the mech picker show in hangar
# view"): the preview's < > buttons show only with the mech picker's preview, not on the squad view.

func _ready() -> void:
	var h: Node = load("res://scenes/ui/Hangar.tscn").instantiate()
	add_child(h)
	for i in 3:
		await get_tree().process_frame
	var bad: Array = []
	for n in ["PreviewLeft", "PreviewRight"]:
		var b: Control = h.find_child(n, true, false)
		if b == null:
			bad.append("no %s" % n)
			continue
		h.call("_show_squad_screen")
		if b.is_visible_in_tree():
			bad.append("%s visible on the squad (hangar) view" % n)
		h.call("_show_detail_screen", 0)
		if not b.is_visible_in_tree():
			bad.append("%s hidden in the mech picker" % n)
		h.call("_show_squad_screen")
		if b.is_visible_in_tree():
			bad.append("%s still visible back on the squad view" % n)
	if not bad.is_empty():
		push_error("[probe] preview_buttons FAIL: " + "; ".join(bad))
		get_tree().quit(1)
		return
	print("[probe] preview_buttons done")
	get_tree().quit(0)
