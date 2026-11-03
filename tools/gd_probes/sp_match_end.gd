extends Node
# B74 probe: an SP match must show its result screen on the frame it ends. SP runs on
# an OfflineMultiplayerPeer, so has_multiplayer_peer() is true and Arena._on_match_ended
# took the MP branch: no result screen (match_ended_mp isn't wired in SP), mechs frozen,
# and a 30 s lobby deadline. The user's case: allies die, then the player (team wipe).
# T184: SP is a local MP match, so the player has squad lives; this is the last one.

func _ready() -> void:
	Game.mp_active_match["roster"] = []  # Arena sets up SP from the loadout (T184)
	Game.loadout["team_size"] = 3
	var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arena)
	for i in 2:
		await get_tree().process_frame
	if arena.get("_start_pick_open"):  # T187: keep slot 0, as a player would
		arena.get("hud").squad_slot_selected.emit(0)
	for i in 120:
		await get_tree().physics_frame
	# T184: bots come from the MP roster (varied mechs), not one bot_def for all
	var bot_mechs := {}
	for p in arena.get("_players"):
		if p != arena.get("_player"):
			bot_mechs[p.get("pawn").scene_file_path + str(p.get("pawn").max_health)] = true
	if bot_mechs.size() < 2:
		push_error("[probe] sp_match_end: every bot runs the same mech")
	for p in arena.get("_players"):  # last mech for everyone on team 0 (bots have squads, T198)
		if p.get("team") == 0:
			p.set("lives", 1)
	var team0: Array = arena.get("_team_mechs")[0]
	for i in range(team0.size() - 1, -1, -1):  # player (index 0) dies last
		team0[i].take_damage(1e9)
	for i in 2:
		await get_tree().process_frame
	var hud: Node = arena.get("hud")
	var result := hud.find_children("*", "Label", true, false).any(
		func(l: Label) -> bool: return l.visible and l.text == "YOU LOSE")
	if not hud.find_children("*", "Button", true, false).any(
			func(b: Button) -> bool: return b.text == "RETURN TO HANGAR"):
		push_error("[probe] sp_match_end: SP result screen has no RETURN TO HANGAR")
	if not arena.get("_match_over"):
		push_error("[probe] sp_match_end: team wipe did not end the match")
	if not result:
		push_error("[probe] sp_match_end: no result screen after the match ended")
	if Game._mp_return_deadline > 0.0:
		push_error("[probe] sp_match_end: SP armed the MP return-to-lobby deadline")
	print("[probe] sp_match_end done (over=%s result=%s deadline=%.1f)" % [arena.get("_match_over"), result, Game._mp_return_deadline])
	get_tree().quit(0)
