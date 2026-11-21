extends Node
# T550 probe (user 2026-11-21: "Info box on pilot skills with details."): every skill has a description;
# every skill node carries an "i"; pressing it on the pilot tab opens the info box with the skill's name,
# description and numbers -- locked: per level + the SP price + what it needs; upgrading: now -> next +
# the coin price; maxed: the total -- inside the 640x360 screen; the same "i" again closes it.

func _fail(msg: String) -> void:
	push_error("[probe] skill_info FAIL: " + msg)
	get_tree().quit(1)

func _ready() -> void:
	Game.profile["level"] = 30
	Game.profile["coins"] = 1234
	Game.profile["skills"] = {"health": 3, "damage": 12}
	var h: Node = load("res://scenes/ui/Hangar.tscn").instantiate()
	get_tree().root.add_child.call_deferred(h)
	for i in 3:
		await get_tree().process_frame
	h.call("_show_tab", 1)
	h.call("_build_progression_nodes")
	await get_tree().process_frame
	var bad: Array = []
	var tree: Node = h.get("_prog_nodes_container")
	for key in Game.SKILL_TREE:
		if String(Game.SKILL_TREE[key].get("desc", "")).length() < 15:
			bad.append("%s has no description" % key)
		var n := tree.find_child("Skill_%s" % key, true, false) as Button
		if n == null or n.get_node_or_null("Info") == null:
			bad.append("%s: no node / no \"i\"" % key)
	# [key, words its box must hold]
	for c in [["health", ["HEALTH", "level 3 / 12", "+6%", "LEVEL 4  +8%", "300 coins", "hit points"]],
			["damage", ["level 12 / 12", "+18%", "maxed"]],
			["contested_hold", ["NEEDS  Beacon Capture", "1 skill point", "+0.5 s"]],
			["move_speed", ["NEEDS ONE OF  Damage, Health"]],
			["scope_zoom", ["150 m", "not lock-on"]]]:
		var info := tree.find_child("Skill_%s" % c[0], true, false).get_node("Info") as Button
		info.pressed.emit()
		for i in 2:
			await get_tree().process_frame
		var ib: Control = h.get("_info_box")
		var txt: String = h.call("info_box_text")
		if ib == null or not ib.is_visible_in_tree():
			bad.append("%s: the info box didn't open" % c[0])
			continue
		for w in c[1]:
			if not txt.contains(w):
				bad.append("%s box lacks \"%s\": %s" % [c[0], w, txt.replace("\n", " / ")])
		var r := ib.get_global_rect()
		if r.position.x < 0.0 or r.position.y < 0.0 or r.end.x > 640.5 or r.end.y > 360.5:
			bad.append("%s box off screen at %s" % [c[0], r])
		info.pressed.emit()
		await get_tree().process_frame
		if ib.visible:
			bad.append("%s: its \"i\" again didn't close the box" % c[0])
	if not bad.is_empty():
		_fail("; ".join(bad))
		return
	print("[probe] skill_info done (%d skills described; locked / upgrading / maxed boxes on screen)" % Game.SKILL_TREE.size())
	get_tree().quit(0)
