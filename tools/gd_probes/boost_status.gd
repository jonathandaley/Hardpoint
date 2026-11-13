extends Node
# T371 probe (HUMAN_FOUND 2026-11-09: "powerups with an ongoing effect get a HUD indicator like
# bogged down"): a running damage / speed boost shows its effect + seconds left under the minimap
# (under BOGGED when wading), and goes away when the boost runs out.

func _fail(msg: String) -> void:
	push_error("[probe] boost_status FAIL: " + msg)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Game.mp_active_match["roster"] = []
	Game.loadout["team_size"] = 1
	var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arena)
	for i in 2:
		await get_tree().process_frame
	if arena.get("_start_pick_open"):
		arena.get("hud").squad_slot_selected.emit(0)
		arena.get("hud").spawn_selected.emit(0)
	for i in 10:
		await get_tree().physics_frame
	var me: Node = arena.get("player_mech")
	var hud: Node = arena.get("hud")
	var mm := hud.get("minimap") as Control
	me.set("damage_boost_s", 9.5)
	me.set("speed_boost_s", 4.2)
	for i in 5:
		await get_tree().process_frame
	var box := hud.find_child("BoostStatus", true, false) as Control
	if box == null or not box.visible:
		_fail("no boost status with two boosts running")
	else:
		var d := box.find_child("Boost_damage", true, false) as Label
		var s := box.find_child("Boost_speed", true, false) as Label
		if d == null or not d.visible or not d.text.contains("DAMAGE") or not d.text.contains("10s"):
			_fail("damage line reads '%s'" % (d.text if d else "none"))
		if s == null or not s.visible or not s.text.contains("SPEED") or not s.text.contains("5s"):
			_fail("speed line reads '%s'" % (s.text if s else "none"))
		var r := mm.get_global_rect()
		var b := box.get_global_rect()
		if b.position.y < r.end.y or b.position.y > r.end.y + 20.0 or absf(b.position.x - r.position.x) > 2.0:
			_fail("status at %s is not just under the minimap %s" % [b, r])
		me.set("terrain_speed", 0.55)  # wading: BOGGED takes the first line, the boosts go under it
		for i in 5:
			await get_tree().process_frame
		var bog := hud.find_child("BogStatus", true, false) as Control
		if bog == null or not bog.visible or box.get_global_rect().position.y < bog.get_global_rect().end.y:
			_fail("boosts not under the BOGGED line (%s vs %s)" % [box.get_global_rect(), bog.get_global_rect() if bog else null])
		me.set("terrain_speed", 1.0)
	me.set("damage_boost_s", 0.0)
	me.set("speed_boost_s", 0.0)
	me.call("remove_modifier", "walk_speed")
	for i in 5:
		await get_tree().process_frame
	if box != null and box.visible:
		_fail("status still shown with no boost running")
	print("[probe] boost_status done")
	get_tree().quit(0)
