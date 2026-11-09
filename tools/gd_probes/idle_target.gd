extends Node
# T219 probe (HUMAN_FOUND_ISSUES: "bots still don't always see the closest opponent when
# idle"): an Elite bot already on a far enemy (60 m, hurt to 40%, picked earlier) with a
# fresh one standing 25 m away in the open must switch to the near one within one target
# refresh (2 s). (T190 covers point-blank, < 15 m; this is the range between, where the
# +2 switching hysteresis kept the old far target.) Runs at Hard: the same AI as Elite, fixed rosters.

func _fail(msg: String) -> void:
	push_error("[probe] idle_target: " + msg)

func _ready() -> void:
	Game.loadout["team_size"] = 2
	# B133: Hard, not Elite -- the same AI (T282), but Elite rosters draw the pilots' kits (T350) and
	# (T365) regular ones random mechs: an Everest subject found no clear 60 m sight line at all (1 run
	# in 6). So every bot flies a fixed squad here: Pegasus with rifles.
	Game.settings["bot_difficulty"] = 3
	Game.loadout["mode"] = "beacons"
	Game.setup_sp_match()
	for e in Game.mp_active_match["roster"]:
		if int(e["peer_id"]) == 0:
			var peg := "res://resources/mechs/Pegasus.tres"
			e["squad"] = range(5).map(func(_i): return {"mech": peg, "weapons": ["res://scenes/weapons/RifleLight.tscn", "res://scenes/weapons/RifleLight.tscn"]})
	var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arena)
	for i in 2:
		await get_tree().process_frame
	if arena.get("_start_pick_open"):
		arena.get("hud").squad_slot_selected.emit(0)
		arena.get("hud").spawn_selected.emit(0)
	for i in 30:
		await get_tree().physics_frame
	var subj_p: Node = arena.get_node("BotPlayer_1_0")
	var subj: Node3D = subj_p.get("pawn")
	var ai: Node = subj_p.get("input_source")
	arena.get_node("BotPlayer_1_1").get("pawn").process_mode = Node.PROCESS_MODE_DISABLED  # no help
	var near: Node3D = arena.get("player_mech")
	var far: Node3D = arena.get("_team_mechs")[0][1]
	for e in [near, far]:
		e.invincible = true
		# stand still, never shoot -- an inert input, not a disabled node: a process-disabled body
		# leaves physics, and the sight-line rays went straight through it (B133; cf. B126)
		var src: Node = load("res://scripts/InputSource.gd").new()
		add_child(src)
		e.set_input_source(src)
	subj.process_mode = Node.PROCESS_MODE_DISABLED  # park the subject in the open centre
	subj.global_position = Vector3(5.1, 1.0, 11.2)
	var fwd := -subj.global_transform.basis.z
	for k in 24:  # far: 60 m off and in sight too
		far.global_position = subj.global_position + fwd.rotated(Vector3.UP, -0.3 - k * 0.26) * 60.0 + Vector3.UP * 3.0
		if ai._los_to(subj, far):
			break
	for k in 24:  # a spot 25 m off that the bot can see (in the open, not behind a column)
		near.global_position = subj.global_position + fwd.rotated(Vector3.UP, 0.3 + k * 0.26) * 25.0 + Vector3.UP * 0.5
		if ai._los_to(subj, near):
			break
	if not ai._los_to(subj, near) or not ai._los_to(subj, far):
		var why: Array = []
		for e in [near, far]:
			var q := PhysicsRayQueryParameters3D.create(subj.global_position + Vector3(0, 2.0, 0), e.global_position + Vector3(0, 1.5, 0))
			q.exclude = subj.get_exclude_rids()
			var hit := subj.get_world_3d().direct_space_state.intersect_ray(q)
			why.append("%s %s at %s: ray hits %s" % [e.name, String(e.get_meta("spawn", ["?"])[0]).get_file(), e.global_position.snapped(Vector3.ONE * 0.1),
				(hit["collider"] as Node).name if not hit.is_empty() else "nothing"])
		_fail("setup: no clear sight line to both enemies (subject %s; %s)" % [String(subj.get_meta("spawn", ["?"])[0]).get_file(), "; ".join(why)])
	far.health = far.max_health * 0.4
	ai.set("_target", far)  # what it had been watching
	ai.set("_target_refresh", 0.0)
	subj.process_mode = Node.PROCESS_MODE_INHERIT
	var picked: Node = null
	for i in 150:
		await get_tree().physics_frame
		subj.global_position = Vector3(5.1, subj.global_position.y, 11.2)  # idle: hold position
		picked = ai.get("_target")
	if picked != near:
		_fail("idle bot stayed on %s, not the closest enemy (25 m) over a hurt one at 60 m" % (picked.name if picked else "nothing"))
	print("[probe] idle_target done (target %s, score near %.1f / far %.1f)" % [picked.name if picked else "-",
		ai._score(subj, near), ai._score(subj, far)])
	get_tree().quit(0)
