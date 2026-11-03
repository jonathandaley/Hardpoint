extends Node
# T189 probe (HUMAN_FOUND_ISSUES: "bots do not split up, but rush the center in a group"):
# a 5v5 of Elite bots (the human slot kept out of it) must spread over the beacons. Two
# numbers per team, sampled every second from 5 s to 30 s: the most bots heading for one
# beacon (their claimed objective) and the mean distance between teammate bots. Every
# slot runs a Hornet (2.1 m/s): the roster's 5v5 puts the slow heavies (Everest 0.75 m/s)
# all on one side, and spacing would measure walk speed instead of the AI.

const MAX_SHARE := 2.6    # mean of the per-sample maximum bots on one beacon (old AI: 3-4)
const MIN_SPACING := 12.0  # m, mean pairwise teammate distance, both teams averaged (old AI:
                           # 6-8; new: 16-17 -- on MathTemple one team's two pairs share the
                           # route past the centre for a while, the other spreads ~25 m)

func _ready() -> void:
	Game.loadout["team_size"] = 5
	Game.settings["bot_difficulty"] = 4
	Game.setup_sp_match()
	for e in Game.mp_active_match["roster"]:
		e["squad"] = [{"mech": "res://resources/mechs/Hornet.tres", "weapons": []}]
	var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arena)
	for i in 2:
		await get_tree().process_frame
	if arena.get("_start_pick_open"):
		arena.get("hud").squad_slot_selected.emit(0)
		arena.get("hud").spawn_selected.emit(0)
	var pm: Node = arena.get("player_mech")
	pm.invincible = true
	pm.process_mode = Node.PROCESS_MODE_DISABLED  # parked: the bots alone decide the shape
	var share := [0.0, 0.0]
	var spacing := [0.0, 0.0]
	var samples := 0
	for sec in 30:
		for i in 60:
			await get_tree().physics_frame
		if sec < 5:
			continue
		samples += 1
		for team in 2:
			var claims := {}
			var pos: Array = []
			for p in arena.get("_players"):
				var m: Node = p.get("pawn")
				var ai: Node = p.get("input_source")
				if p.get("team") != team or m == null or m.get("is_dead") or ai == null or not ai.has_method("set_mp_seed"):
					continue
				pos.append((m as Node3D).global_position)
				var b: Variant = ai.get("_claimed_beacon")
				if b != null:
					claims[b] = claims.get(b, 0) + 1
			share[team] += float(claims.values().max() if not claims.is_empty() else 0)
			var sum := 0.0
			var n := 0
			for a in pos.size():
				for c in range(a + 1, pos.size()):
					sum += (pos[a] as Vector3).distance_to(pos[c])
					n += 1
			spacing[team] += sum / n if n > 0 else 0.0
	for team in 2:
		share[team] /= samples
		spacing[team] /= samples
		if share[team] > MAX_SHARE:
			push_error("[probe] bot_spread: team %d crowds one beacon (mean max %.2f bots > %.1f)" % [team, share[team], MAX_SHARE])
	if (spacing[0] + spacing[1]) * 0.5 < MIN_SPACING:
		push_error("[probe] bot_spread: teams move as clumps (mean spacing %.1f m < %.0f)" % [(spacing[0] + spacing[1]) * 0.5, MIN_SPACING])
	print("[probe] bot_spread done (max on one beacon %.2f / %.2f, spacing %.1f / %.1f m)" % [share[0], share[1], spacing[0], spacing[1]])
	get_tree().quit(0)
