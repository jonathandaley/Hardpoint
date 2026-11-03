extends Node
# T190 probe (HUMAN_FOUND_ISSUES: bots "do not switch focus if snuck up on, even at
# point-blank range"): an Elite bot busy with a far, focus-fired target must turn to an
# enemy that appears 4 m behind it within half a second. Before T190 the close enemy lost
# on score (focus + sight bonuses outweigh 0.1/m of distance) and targets were re-picked
# only every 2 s.

func _ready() -> void:
	Game.loadout["team_size"] = 2
	Game.settings["bot_difficulty"] = 4
	Game.mp_active_match["roster"] = []
	var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arena)
	for i in 2:
		await get_tree().process_frame
	if arena.get("_start_pick_open"):
		arena.get("hud").squad_slot_selected.emit(0)
		arena.get("hud").spawn_selected.emit(0)
	for i in 30:
		await get_tree().physics_frame
	var far: Node3D = arena.get("player_mech")  # parked at team 0's spawn, ~110 m off
	far.invincible = true
	far.process_mode = Node.PROCESS_MODE_DISABLED
	var sneak: Node3D = arena.get("_team_mechs")[0][1]  # team 0's bot
	sneak.process_mode = Node.PROCESS_MODE_DISABLED  # walks up silently, never shoots
	var subj_p: Node = arena.get_node("BotPlayer_1_0")
	var mate_p: Node = arena.get_node("BotPlayer_1_1")
	var subj: Node3D = subj_p.get("pawn")
	var ai: Node = subj_p.get("input_source")
	for p in [subj_p, mate_p]:  # both on the far target: focus fire
		p.get("input_source").set("_target", far)
		p.get("input_source").set("_target_refresh", 2.0)
	sneak.global_position = subj.global_position + subj.global_transform.basis.z * 4.0 + Vector3.UP * 0.2
	var switched := -1
	for i in 30:
		await get_tree().physics_frame
		if ai.get("_target") == sneak:
			switched = i
			break
	if switched < 0:
		push_error("[probe] point_blank: bot kept its far focus target with an enemy 4 m behind it (target %s)"
			% (ai.get("_target").name if ai.get("_target") else "none"))
	print("[probe] point_blank done (switched after %d ticks)" % switched)
	get_tree().quit(0)
