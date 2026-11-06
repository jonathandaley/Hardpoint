extends Node
# T278 probe (HUMAN_FOUND 2026-11-05: "Self destruct option in esc menu, just kill the current
# mech"): Esc -> SELF DESTRUCT closes the menu (and unpauses SP), our mech dies a normal death
# (a life spent, the mech picker follows); a self-destruct request from another peer can only
# ever kill that peer's own mech.

func _fail(msg: String) -> void:
	push_error("[probe] self_destruct FAIL: " + msg)
	get_tree().quit(1)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Game.mp_active_match["roster"] = []
	Game.loadout["team_size"] = 2
	var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arena)
	for i in 2:
		await get_tree().process_frame
	if arena.get("_start_pick_open"):
		arena.get("hud").squad_slot_selected.emit(0)
		arena.get("hud").spawn_selected.emit(0)
	for i in 20:
		await get_tree().physics_frame
	var me: Node = arena.get("player_mech")
	var others: Array = []
	for t in 2:
		for m in arena.get("_team_mechs")[t]:
			if m != me:
				others.append(m)
	# someone else's request (pid 99) kills nobody -- not us, not a bot
	arena.call("_self_destruct", 99)
	if me.get("is_dead") or others.any(func(m): return m.get("is_dead")):
		_fail("a stranger's self-destruct killed a mech")
		return
	var lives0: int = arena.get("_player").get("lives")
	arena.call("_toggle_pause")
	var btn := arena.get("pause_menu").find_child("SelfDestructButton", true, false) as Button
	if btn == null:
		_fail("no SELF DESTRUCT in the pause menu")
		return
	btn.pressed.emit()
	await get_tree().process_frame
	if arena.get("pause_menu").visible or get_tree().paused:
		_fail("the pause menu stayed open / the game stayed paused")
		return
	if not me.get("is_dead"):
		_fail("SELF DESTRUCT didn't kill our mech")
		return
	var t0 := Time.get_ticks_msec()
	var picker = null
	while Time.get_ticks_msec() - t0 < 1500 and not (picker != null and is_instance_valid(picker)):
		await get_tree().process_frame
		picker = arena.get("hud").get("_squad_picker")
	if not (picker != null and is_instance_valid(picker)) or int(arena.get("_player").get("lives")) != lives0 - 1:
		_fail("not a normal death (picker %s, lives %d -> %d)" % [picker != null, lives0, int(arena.get("_player").get("lives"))])
		return
	print("[probe] self_destruct done")
	get_tree().quit(0)
