extends Node
# T280 probe (HUMAN_FOUND 2026-11-05: "Beacon capture count at end of match is wrong ...
# everyone on each team gets counted for every beacon"): when our mech alone captures a beacon,
# our match-stats row shows 1 capture and our teammates' rows 0 (each pilot is credited only for
# beacons its mechs stood in when they flipped).

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Game.mp_active_match["roster"] = []
	Game.loadout["team_size"] = 3
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
	var beacon: Node = get_tree().get_nodes_in_group("beacons")[0]
	beacon.set_process(false)  # drive the capture by hand: only our mech in the zone
	beacon.set("_capturers", {})
	beacon.call("_on_body_entered", me)
	for i in 200:
		beacon.call("_update_capture", 0.05)
		if int(beacon.get("owner_team")) == int(me.get("team")):
			break
	var msg := ""
	if int(beacon.get("owner_team")) != int(me.get("team")):
		msg = "the beacon never flipped to our team"
	else:
		var stats: Array = arena.call("_build_mp_stats")
		var my_ri: int = int(me.get("roster_idx"))
		var rows := []
		for ri in stats.size():
			var e: Dictionary = stats[ri]
			if int(e.get("team", -1)) == int(me.get("team")):
				rows.append([ri, int(e.get("captures", 0))])
		for r in rows:
			var want := 1 if r[0] == my_ri else 0
			if r[1] != want:
				msg = "row %d shows %d captures, want %d (rows %s, ours %d)" % [r[0], r[1], want, str(rows), my_ri]
				break
	if msg != "":
		push_error("[probe] capture_credit FAIL: " + msg)
		get_tree().quit(1)
		return
	print("[probe] capture_credit done")
	get_tree().quit(0)
