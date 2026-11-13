extends Node
# T347 probe (HUMAN_FOUND 2026-11-08: "skill tree visual: a real branching tree -- a root system
# with the lowest tiers at the top, like the Age of Empires II tech tree"): the hangar's pilot tab
# draws every skill as a node, roots on the top row and each skill a row below its deepest parent,
# a line from every parent to its child, nodes inside the panel and not overlapping; clicking a
# node you can buy unlocks the skill.
# T375 (HUMAN_FOUND 2026-11-09: "cramped and messy ... only right angles in the connecting lines, no
# angled lines. Lines should only go to direct children/parents"; user 2026-11-12: available skills
# short of coins "not greyed out, but have the cost to upgrade in red"): every skill has its own grid
# cell; lines are horizontal / vertical runs that cross no other node, drawn to direct parents only;
# an affordable-or-not skill stays enabled, its price red when short.

func _fail(msg: String) -> void:
	push_error("[probe] skill_tree FAIL: " + msg)
	get_tree().quit(1)

## Direct parents (the ones that get a line): not a parent another parent already descends from.
func _direct(key: String) -> Array:
	var ps: Array = Game.SKILL_TREE[key].get("parents", [])
	return ps.filter(func(p): return not ps.any(func(q): return q != p and _descends(q, p)))

func _descends(key: String, ancestor: String) -> bool:
	for p in Game.SKILL_TREE[key].get("parents", []):
		if p == ancestor or _descends(p, ancestor):
			return true
	return false

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
			var drawn: Array = _direct(key)
			var edge := tree.find_child("Edge_%s_%s" % [p, key], false, false) as Line2D
			if p in drawn and edge == null:
				bad.append("no line %s -> %s" % [p, key])
			elif not p in drawn and edge != null:
				bad.append("a line %s -> %s skips a generation (via %s)" % [p, key, drawn])
			if edge == null:
				continue
			for i in edge.points.size() - 1:
				var a: Vector2 = edge.points[i]
				var b: Vector2 = edge.points[i + 1]
				if absf(a.x - b.x) > 0.01 and absf(a.y - b.y) > 0.01:
					bad.append("line %s -> %s has an angled run %s-%s" % [p, key, a, b])
				var seg := Rect2(a, Vector2.ZERO).expand(b)
				for other in Game.SKILL_TREE:
					if other == p or other == key:
						continue
					var on := tree.find_child("Skill_%s" % other, false, false) as Control
					if on != null and Rect2(on.position, on.size).grow(-1.0).intersects(seg.grow(0.5)):
						bad.append("line %s -> %s runs across %s" % [p, key, other])
	var grid: Dictionary = (h.get_script() as Script).get_script_constant_map().get("TREE_GRID", {})
	for key in Game.SKILL_TREE:
		if not grid.has(key):
			bad.append("%s has no TREE_GRID cell" % key)
	if not bad.is_empty():
		_fail("; ".join(bad))
		return
	# states: health LV 2 with 0 coins -> enabled, its upgrade price red; repair_rate buyable with SP left
	var hn := tree.find_child("Skill_health", false, false) as Button
	var hc := hn.find_child("Cost", true, false) as Label if hn != null else null
	if hn == null or hn.disabled or hc == null or not hc.has_theme_color_override("font_color") \
			or hc.get_theme_color("font_color").r < 0.9 or hc.get_theme_color("font_color").g > 0.5:
		_fail("Health (LV 2, no coins) should be enabled with its price in red (disabled %s, cost %s)" % [hn.disabled if hn else null, hc.text if hc else null])
		return
	var rn := tree.find_child("Skill_repair_rate", false, false) as Button
	var rc := rn.find_child("Cost", true, false) as Label if rn != null else null
	if rc == null or rc.has_theme_color_override("font_color"):
		_fail("Repair Rate (SP to spare) shows its price as short")
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
	print("[probe] skill_tree done (%d skills)" % y.size())
	get_tree().quit(0)
