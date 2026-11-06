extends Node
# T275 probe (HUMAN_FOUND 2026-11-05: "Team size should not be in hangar -- it's part of
# setting up a match now"): the hangar screen has no TEAM SIZE picker (label or NvN readout).

func _ready() -> void:
	var h: Node = load("res://scenes/ui/Hangar.tscn").instantiate()
	add_child(h)
	for i in 3:
		await get_tree().process_frame
	var hits: Array = []
	for n in h.find_children("*", "Label", true, false):
		var t: String = (n as Label).text
		if t == "TEAM SIZE" or (t.length() <= 5 and t.contains("v") and t.left(1).is_valid_int() and t.right(1).is_valid_int()):
			hits.append(t)
	if not hits.is_empty():
		push_error("[probe] hangar_no_team_size FAIL: hangar still shows %s" % str(hits))
		get_tree().quit(1)
		return
	print("[probe] hangar_no_team_size done")
	get_tree().quit(0)
