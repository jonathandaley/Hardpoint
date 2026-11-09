extends Node
# T347 probe (HUMAN_FOUND 2026-11-08: "skill tree visual: a real branching tree -- a root system
# with the lowest tiers at the top, like the Age of Empires II tech tree"): the hangar's pilot tab
# draws every skill as a node, roots on the top row and each skill a row below its deepest parent,
# a line from every parent to its child, nodes inside the panel and not overlapping; clicking a
# node you can buy unlocks the skill.

func _fail(msg: String) -> void:
	push_error("[probe] skill_tree FAIL: " + msg)
	get_tree().quit(1)

func _ready() -> void:
	Game.profile["level"] = 5
	Game.profile["skills"] = {"health": 2}
	Game.profile["coins"] = 0
	var h: Node = load("res://scenes/ui/Hangar.tscn").instantiate()
	get_tree().root.add_child.call_deferred(h)
	for i in 3:
		await get_tree().process_frame
	h.call("_build_progression_nodes")
	await get_tree().process_frame
	var tree: Node = (h.get("_prog_nodes_container") as Node).find_child("SkillTree", true, false)
	if tree == null:
		_fail("no SkillTree on the pilot tab (still a list?)")
		return
	var bad: Array = []
	var y := {}
	var rects: Array = []
	for key in Game.SKILL_TREE:
		var n := tree.find_child("Skill_%s" % key, false, false) as Control
		if n == null:
			bad.append("no node for %s" % key)
			continue
		y[key] = n.position.y
		var r := Rect2(n.position, n.size)
		if r.position.x < 0.0 or r.end.x > 640.0:
			bad.append("%s sticks out of the panel (%s)" % [key, r])
		for o in rects:
			if r.intersects(o):
				bad.append("%s overlaps another node" % key)
		rects.append(r)
	for key in Game.SKILL_TREE:
		var parents: Array = Game.SKILL_TREE[key].get("parents", [])
		if parents.is_empty() and y.get(key, -1.0) > y.values().min() + 0.5:
			bad.append("root %s isn't on the top row" % key)
		for p in parents:
			if y.has(key) and y.has(p) and y[key] <= y[p]:
				bad.append("%s isn't below its parent %s" % [key, p])
			if tree.find_child("Edge_%s_%s" % [p, key], false, false) == null:
				bad.append("no line %s -> %s" % [p, key])
	if not bad.is_empty():
		_fail("; ".join(bad))
		return
	# clicking a buyable node buys it (health owned -> repair_rate unlockable, 1 SP)
	var node := tree.find_child("Skill_repair_rate", false, false) as Button
	if node == null or node.disabled:
		_fail("Repair Rate isn't buyable from its node with Health owned")
		return
	node.pressed.emit()
	await get_tree().process_frame
	if Game.skill_level("repair_rate") != 1:
		_fail("clicking the Repair Rate node didn't unlock it")
		return
	print("[probe] skill_tree done (%d rows)" % (int((y.values().max() - y.values().min()) / 38.0) + 1))
	get_tree().quit(0)
