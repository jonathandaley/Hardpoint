extends Node
# T332 + T335 probe: each mech flies with its own pilot's skills, from its roster entry, not the
# host's profile -- (a) claimed skills are sanitized (known keys, levels 1..12, unlocks <= level);
# (b) ELITE bots draw named builds (BotNames.ELITE) and their mechs carry them (health scaled,
# repair_rate regen); (c) non-elite bots get nothing although the host's profile is maxed.

const BotNames := preload("res://scripts/BotNames.gd")

func _fail(msg: String) -> void:
	push_error("[probe] pilot_skills FAIL: " + msg)
	get_tree().quit(1)

func _arena(diff: int) -> Node:
	Game.settings["bot_difficulty"] = diff
	Game.mp_active_match["roster"] = []
	Game.loadout["team_size"] = 1
	Game.loadout["sp_bots"] = [0, 3]
	Game.loadout["mode"] = "deathmatch"  # no beacons pulling bots around
	var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arena)
	for i in 2:
		await get_tree().process_frame
	if arena.get("_start_pick_open"):
		arena.get("hud").squad_slot_selected.emit(0)
		arena.get("hud").spawn_selected.emit(0)
	for i in 5:
		await get_tree().physics_frame
	return arena

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var s: Dictionary = Game.sanitize_skills({"health": 99, "bogus": 3, "damage": 5}, 1)
	if s.size() != 1 or s.has("bogus") or int(s.values()[0]) > 12:
		_fail("claimed skills not sanitized: %s" % s)
		return
	Game.profile["level"] = 30
	Game.profile["skills"] = {"health": 12, "move_speed": 12}  # the host's own, maxed
	var arena: Node = await _arena(4)
	var roster: Array = Game.mp_active_match["roster"]
	var regen_m: Node = null
	for m in arena.get("_team_mechs")[1]:
		var e: Dictionary = roster[int(m.roster_idx)]
		var nm := str(e.get("name", ""))
		if not BotNames.ELITE.has(nm):
			_fail("an Elite bot is called '%s', not an ELITE name" % nm)
			return
		var base: float = float(load(m.get_meta("spawn")[0]).get("max_health"))
		var want: float = base * (1.0 + Game.skill_effect_in(BotNames.ELITE[nm], "health"))
		if absf(float(m.max_health) - want) > 0.5:
			_fail("Elite '%s' mech max HP %.0f, want %.0f (its health %d)" % [nm, m.max_health, want, int(BotNames.ELITE[nm].get("health", 0))])
			return
		if m.call("skill", "repair_rate") > 0.0:
			regen_m = m
	if regen_m == null:  # none drawn this time: give the first one Bastion's build
		regen_m = arena.get("_team_mechs")[1][0]
		regen_m.set("pilot_skills", BotNames.ELITE["Bastion"])
	if regen_m != null:  # a repairing elite heals 3 s after its last hit
		regen_m.disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
		regen_m.health = regen_m.max_health * 0.5
		regen_m.set("_no_damage_timer", 3.0)
		var h0: float = regen_m.health
		for i in 30:
			await get_tree().physics_frame
		if float(regen_m.health) <= h0:
			_fail("Elite with repair_rate %.1f didn't regen" % regen_m.call("skill", "repair_rate"))
			return
	arena.queue_free()
	for i in 3:
		await get_tree().process_frame
	# Normal bots: no skills, whatever the host has
	arena = await _arena(1)
	for m in arena.get("_team_mechs")[1]:
		var base: float = float(load(m.get_meta("spawn")[0]).get("max_health"))
		if absf(float(m.max_health) - base) > 0.5:
			_fail("a Normal bot has %.0f max HP (base %.0f): the host's skills leaked onto it" % [m.max_health, base])
			return
	var me: Node = arena.get("player_mech")
	var my_base: float = float(load(me.get_meta("spawn")[0]).get("max_health"))
	if absf(float(me.max_health) - my_base * 1.24) > 0.5:
		_fail("the player's mech has %.0f max HP, want %.0f (health 12)" % [me.max_health, my_base * 1.24])
		return
	print("[probe] pilot_skills done (elite builds on, repair regen, normal bots clean)")
	get_tree().quit(0)
