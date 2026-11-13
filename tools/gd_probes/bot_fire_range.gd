extends Node
# T417 probe (HUMAN_FOUND, queued 2026-11-13: "Normal-level bot shoots missile launcher when out of
# range."): at every difficulty, the distance a bot opens fire from never exceeds its weapon's reach
# (the old 50 m floor for Easy / Normal fired a 30 m missile launcher at 50 m); a rifle bot keeps it.

const SlotDef := preload("res://scripts/WeaponSlotDef.gd")

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
	var bot: Node = arena.get("_team_mechs")[1 - int(me.get("team"))][0]
	var ai: Node = bot.get("_input_source")
	var bad: Array = []
	for wpath in ["res://scenes/weapons/MissileLauncherLight.tscn", "res://scenes/weapons/ShotgunLight.tscn", "res://scenes/weapons/RifleLight.tscn"]:
		var slot := SlotDef.new()
		slot.slot_size = 0
		slot.position = Vector3(0, 2.0, 0)
		slot.weapon_scene = load(wpath)
		bot.call("configure_weapons", [slot])
		var reach := float(bot.call("get_weapons")[0].get("range"))
		for d in 5:
			ai.set("difficulty", d)
			var fr: float = ai.call("_fire_range", bot)
			if fr > reach:
				bad.append("%s at difficulty %d fires from %.0f m, reach %.0f m" % [wpath.get_file(), d, fr, reach])
			if wpath.ends_with("RifleLight.tscn") and d <= 1 and fr < 49.0:
				bad.append("Easy / Normal rifle bots lost their 50 m fire range (%.0f)" % fr)
	if not bad.is_empty():
		push_error("[probe] bot_fire_range FAIL: " + "; ".join(bad))
	print("[probe] bot_fire_range done")
	get_tree().quit(0)
