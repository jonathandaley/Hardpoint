extends Node
# T350 probe (HUMAN_FOUND 2026-11-08: "Elites definitely should have preset hangars ... modified AI
# with personality ... a hangar that makes sense with their abilities and playstyles"): every Elite
# kit names real mechs and only weapons that fit their slots; an Elite match's named bots fly their
# own kit and carry their personality into the AI (role, fighting distance); below Elite nothing
# changes. T377: each Elite has a beacons hangar ("squad") and a death match one ("squad_dm"); a
# match flies the one for its mode.

const Lobby := preload("res://scripts/Lobby.gd")
const BotNames := preload("res://scripts/BotNames.gd")

func _fail(msg: String) -> void:
	push_error("[probe] elite_kits FAIL: " + msg)
	get_tree().quit(1)

func _ready() -> void:
	var bad: Array = []
	for name in BotNames.ELITE.keys():
		if not BotNames.ELITE_KIT.has(name):
			bad.append("%s has no kit" % name)
			continue
		var kit: Dictionary = BotNames.ELITE_KIT[name]
		for key in ["squad", "squad_dm"]:
			if not kit.has(key):
				bad.append("%s has no %s" % [name, key])
				continue
			var squad: Array = Lobby.kit_squad(kit[key])
			if squad.size() != 5:
				bad.append("%s %s: %d mechs" % [name, key, squad.size()])
			for i in squad.size():
				var fam: String = kit[key][i][1]
				for p in squad[i]["weapons"]:
					if not String(p).get_file().to_upper().begins_with(fam.replace("MG", "MACHINEGUN").replace("MISSILE", "MISSILELAUNCHER").replace("ROCKET", "ROCKETLAUNCHER").replace("LASER", "LASERCANNON").replace("ARC", "ARCWEAPON").replace("AERIAL", "AERIALSTRIKE")):
						bad.append("%s %s: %s slot got %s for %s" % [name, key, kit[key][i][0], String(p).get_file(), fam])
		if kit.get("squad_dm") == kit["squad"]:
			bad.append("%s: the death match hangar is the beacons one" % name)
	if not bad.is_empty():
		_fail("; ".join(bad))
		return
	# an Elite match
	Game.settings["bot_difficulty"] = 4
	Game.loadout["team_size"] = 3
	Game.loadout["mode"] = "deathmatch"
	Game.mp_active_match["roster"] = []
	Game.setup_sp_match()
	var named := 0
	for e in Game.mp_active_match["roster"]:
		if int(e["peer_id"]) != 0:
			continue
		var kit: Dictionary = BotNames.ELITE_KIT.get(e["name"], {})
		if kit.is_empty():
			bad.append("Elite bot %s has no kit" % e["name"])
			continue
		named += 1
		if (e["squad"] as Array).map(func(s): return s["mech"]) != (kit.get("squad_dm", []) as Array).map(func(k): return "res://resources/mechs/%s.tres" % k[0]):
			bad.append("%s flies %s, not its kit" % [e["name"], (e["squad"] as Array).map(func(s): return String(s["mech"]).get_file())])
		if e.get("personality", {}) != kit["personality"]:
			bad.append("%s carries no personality" % e["name"])
	var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arena)
	for i in 2:
		await get_tree().process_frame
	if arena.get("_start_pick_open"):
		arena.get("hud").squad_slot_selected.emit(0)
		arena.get("hud").spawn_selected.emit(0)
	for i in 10:
		await get_tree().physics_frame
	var roster: Array = Game.mp_active_match["roster"]
	for t in 2:
		for m in arena.get("_team_mechs")[t]:
			var ri: int = int(m.get("roster_idx"))
			if ri < 0 or int(roster[ri]["peer_id"]) != 0:
				continue
			var src: Node = m.get("_input_source")
			var want: Dictionary = roster[ri].get("personality", {})
			if src == null or src.get("personality") != want:
				bad.append("%s's AI has personality %s, want %s" % [roster[ri]["name"], src.get("personality") if src else null, want])
			elif src.get("role") != want.get("role"):
				bad.append("%s's AI plays %s, want %s" % [roster[ri]["name"], src.get("role"), want.get("role")])
	# T377: a beacons match flies the beacons hangar
	Game.loadout["mode"] = "beacons"
	Game.mp_active_match["roster"] = []
	Game.setup_sp_match()
	for e in Game.mp_active_match["roster"]:
		var kit: Dictionary = BotNames.ELITE_KIT.get(e["name"], {})
		if int(e["peer_id"]) == 0 and not kit.is_empty() and (e["squad"] as Array).map(func(s): return s["mech"]) != (kit["squad"] as Array).map(func(k): return "res://resources/mechs/%s.tres" % k[0]):
			bad.append("%s flies %s in a beacons match, not its beacons kit" % [e["name"], (e["squad"] as Array).map(func(s): return String(s["mech"]).get_file())])
	# below Elite: no kits
	Game.settings["bot_difficulty"] = 3
	Game.mp_active_match["roster"] = []
	Game.setup_sp_match()
	for e in Game.mp_active_match["roster"]:
		if int(e["peer_id"]) == 0 and e.has("personality"):
			bad.append("a Hard bot (%s) got an Elite personality" % e["name"])
	if named == 0:
		bad.append("no named Elite bots in an Elite match")
	if not bad.is_empty():
		_fail("; ".join(bad))
		return
	print("[probe] elite_kits done (%d named Elites checked)" % named)
	get_tree().quit(0)
