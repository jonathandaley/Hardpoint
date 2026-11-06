extends Node
# T325 probe (HUMAN_FOUND 2026-11-05 late: bots get names from a preset list, shown like players'
# -- the callsign above the health bar): a 5v5 SP roster gives every slot a callsign (the player
# keeps theirs), bots' from BotNames with no repeats; three rosters in a row repeat no bot name
# (the deck); an enemy in view shows its callsign over its health bar.

const BotNames := preload("res://scripts/BotNames.gd")

func _fail(msg: String) -> void:
	push_error("[probe] bot_names FAIL: " + msg)
	get_tree().quit(1)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Game.loadout["team_size"] = 5
	Game.loadout["sp_bots"] = [4, 5]
	Game.loadout["mode"] = "beacons"
	var seen := {}
	for r in 3:
		Game.setup_sp_match()
		var roster: Array = Game.mp_active_match["roster"]
		for e in roster:
			var nm := str(e.get("name", ""))
			if nm == "":
				_fail("roster slot %d (peer %d) has no callsign" % [e["slot_idx"], e["peer_id"]])
				return
			if int(e["peer_id"]) == 0:
				if not BotNames.NAMES.has(nm):
					_fail("bot callsign '%s' isn't from the list" % nm)
					return
				if seen.has(nm):
					_fail("bot callsign '%s' repeated within %d rosters" % [nm, r + 1])
					return
				seen[nm] = true
			elif nm != str(Game.profile.get("pilot_name", "Pilot")):
				_fail("the player's callsign '%s' isn't theirs" % nm)
				return
	# in a match: an enemy in front of us shows its callsign over its bar
	Game.mp_active_match["roster"] = []
	Game.loadout["team_size"] = 1
	Game.loadout["sp_bots"] = [0, 1]
	var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arena)
	for i in 2:
		await get_tree().process_frame
	if arena.get("_start_pick_open"):
		arena.get("hud").squad_slot_selected.emit(0)
		arena.get("hud").spawn_selected.emit(0)
	for i in 5:
		await get_tree().physics_frame
	var me: Node3D = arena.get("player_mech")
	var enemy: Node3D = arena.get("_team_mechs")[1 - int(me.get("team"))][0]
	enemy.disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
	enemy.process_mode = Node.PROCESS_MODE_DISABLED
	var cam: Camera3D = me.get("camera")
	var fwd: Vector3 = -cam.global_transform.basis.z
	enemy.global_position = me.global_position + Vector3(fwd.x, 0.0, fwd.z).normalized() * 20.0
	for i in 10:
		await get_tree().process_frame
	var want := str(Game.mp_active_match["roster"][int(enemy.get("roster_idx"))].get("name", ""))
	var shown := false
	for t in arena.get("hud").get("_name_tags"):
		shown = shown or ((t as Label).visible and (t as Label).text == want)
	if not shown:
		_fail("no visible callsign '%s' over the enemy's health bar" % want)
		return
	print("[probe] bot_names done (%d bot names over 3 rosters, '%s' over the enemy bar)" % [seen.size(), want])
	get_tree().quit(0)
