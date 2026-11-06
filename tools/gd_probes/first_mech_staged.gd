extends Node
# T279 probe (HUMAN_FOUND 2026-11-05: "Don't spawn the first mech until it's picked (currently
# spawns the first mech then switches)"): while the start pick is open our first mech is not in
# the world (hidden, no collision, not targetable); picking another mech + spawn never shows it;
# keeping it (slot 0, first spawn) puts it in the world.

func _fail(msg: String) -> void:
	push_error("[probe] first_mech_staged FAIL: " + msg)
	get_tree().quit(1)

func _arena() -> Node:
	Game.mp_active_match["roster"] = []
	Game.loadout["team_size"] = 1
	var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arena)
	for i in 3:
		await get_tree().process_frame
	return arena

func _in_world(m: Node) -> bool:
	return m.visible and not (m.get_node("CollisionShape3D") as CollisionShape3D).disabled and not m.get("is_stealthy")

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var arena: Node = await _arena()
	if not arena.get("_start_pick_open"):
		_fail("no start pick (the default squad has several mechs)")
		return
	var first: Node = arena.get("player_mech")
	await get_tree().physics_frame
	if _in_world(first):
		_fail("the first mech is in the world before it was picked")
		return
	var hud: Node = arena.get("hud")
	hud.squad_slot_selected.emit(1)
	hud.spawn_selected.emit(1)
	for i in 20:
		await get_tree().physics_frame
		if is_instance_valid(first) and first.visible:
			_fail("the unpicked first mech showed up during the swap")
			return
	var now: Node = arena.get("player_mech")
	if now == first or not _in_world(now):
		_fail("the picked mech isn't in the world")
		return
	arena.queue_free()
	await get_tree().process_frame
	# keep: slot 0 at the first spawn
	arena = await _arena()
	first = arena.get("player_mech")
	arena.get("hud").squad_slot_selected.emit(0)
	arena.get("hud").spawn_selected.emit(0)
	for i in 5:
		await get_tree().physics_frame
	if not _in_world(first):
		_fail("keeping the first mech didn't put it in the world")
		return
	print("[probe] first_mech_staged done")
	get_tree().quit(0)
