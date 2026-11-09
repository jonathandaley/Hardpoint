extends Node
# T361 probe (HUMAN_FOUND 2026-11-08 late: "Skill tree should show what it does (e.g., +5% health,
# -> 5.5%) so that the numbers are visible"): every skill row in the hangar's pilot list shows
# its effect in numbers -- per level while locked, now -> next while upgrading, the total at max.

func _fail(msg: String) -> void:
	push_error("[probe] skill_numbers FAIL: " + msg)
	get_tree().quit(1)

func _ready() -> void:
	Game.profile["level"] = 30
	Game.profile["skills"] = {"health": 3, "damage": 12, "repair_rate": 2}
	var h: Node = load("res://scenes/ui/Hangar.tscn").instantiate()
	get_tree().root.add_child.call_deferred(h)
	for i in 3:
		await get_tree().process_frame
	h.call("_build_progression_nodes")
	await get_tree().process_frame
	var box: Node = h.get("_prog_nodes_container")
	var texts := {}  # T347: one tree node per skill; its tooltip carries the full line
	for key in Game.SKILL_TREE:
		var n := box.find_child("Skill_%s" % key, true, false) as Button
		if n != null:
			texts[Game.SKILL_TREE[key]["label"]] = n.tooltip_text + " | " + n.text
	var want := {
		"Health": ["+6%", "+8%"],            # LV 3: now -> next
		"Damage": ["+18%"],                  # LV 12: the total at max
		"Repair Rate": ["+1 HP/s", "+1.5 HP/s"],
		"Contested Hold": ["+0.5 s"],        # locked: per level
		"Spread Reduction": ["+6%"],
	}
	var bad: Array = []
	for k in want:
		if not texts.has(k):
			bad.append("no row for %s" % k)
			continue
		for s in want[k]:
			if not String(texts[k]).contains(s):
				bad.append("%s row \"%s\" lacks %s" % [k, texts[k], s])
	if not bad.is_empty():
		_fail("; ".join(bad))
		return
	print("[probe] skill_numbers done (%s | %s)" % [texts["Health"], texts["Contested Hold"]])
	get_tree().quit(0)
