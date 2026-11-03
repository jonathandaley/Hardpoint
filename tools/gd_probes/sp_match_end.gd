extends Node
# B74 probe: an SP match must show its result screen on the frame it ends. SP runs on
# an OfflineMultiplayerPeer, so has_multiplayer_peer() is true and Arena._on_match_ended
# took the MP branch: no result screen (match_ended_mp isn't wired in SP), mechs frozen,
# and a 30 s lobby deadline. The user's case: allies die, then the player (team wipe).

func _ready() -> void:
	Game.mp_active_match["roster"] = []  # SP path
	Game.loadout["mech_def"] = load("res://resources/mechs/Hippogriff.tres")
	var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arena)
	for i in 120:
		await get_tree().physics_frame
	var team0: Array = arena.get("_team_mechs")[0]
	for i in range(team0.size() - 1, -1, -1):  # player (index 0) dies last
		team0[i].take_damage(1e9)
	for i in 2:
		await get_tree().process_frame
	var hud: Node = arena.get("hud")
	var result := hud.find_children("*", "Label", true, false).any(
		func(l: Label) -> bool: return l.visible and l.text == "YOU LOSE")
	if not arena.get("_match_over"):
		push_error("[probe] sp_match_end: team wipe did not end the match")
	if not result:
		push_error("[probe] sp_match_end: no result screen after the match ended")
	if Game._mp_return_deadline > 0.0:
		push_error("[probe] sp_match_end: SP armed the MP return-to-lobby deadline")
	print("[probe] sp_match_end done (over=%s result=%s deadline=%.1f)" % [arena.get("_match_over"), result, Game._mp_return_deadline])
	get_tree().quit(0)
