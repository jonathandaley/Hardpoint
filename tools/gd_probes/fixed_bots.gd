extends Node
# T376 probe: with --fixed-bots=<Mech> (the suite passes Pegasus to every probe) every regular bot
# squad is five of that mech with rifles, so no probe depends on T365's random draw.

func _ready() -> void:
	Game.set("fixed_bots", "Pegasus")  # (set: the probe also runs, red, on code without it)
	Game.settings["bot_difficulty"] = 2
	Game.loadout["team_size"] = 3
	Game.loadout["mode"] = "beacons"
	Game.mp_active_match["roster"] = []
	Game.setup_sp_match()
	var bad: Array = []
	for e in Game.mp_active_match["roster"]:
		if int(e["peer_id"]) != 0:
			continue
		for sq in e["squad"]:
			if String(sq["mech"]).get_file() != "Pegasus.tres" or not String(sq["weapons"][0]).get_file().begins_with("Rifle"):
				bad.append("%s %s" % [String(sq["mech"]).get_file(), String(sq["weapons"][0]).get_file()])
	if not bad.is_empty():
		push_error("[probe] fixed_bots: bots fly %s with --fixed-bots=Pegasus" % ", ".join(bad.slice(0, 5)))
	print("[probe] fixed_bots done")
	get_tree().quit(0)
