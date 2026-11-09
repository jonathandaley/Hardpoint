extends Node
# T364 probe (user 2026-11-09: coins "only need to be awarded at end of match, if bot kills are tracked
# separately ... Bots coin values are good, but players are 0: and both players and bots are worth
# extra coins depending on what they've killed this life"): our kill of a bot is counted (kills +
# kill coins = its difficulty value) but not mixed into picked-up coins; the killer carries a bounty
# of half that; a bot that killed one of ours this life is worth its base plus that bounty; a player's
# mech is worth only its bounty; the match result carries kills + kill coins and the payout adds them.

func _fail(msg: String) -> void:
	push_error("[probe] kill_bounty FAIL: " + msg)
	get_tree().quit(1)

func _kill(victim: Node, killer: Node) -> void:
	victim.set("invincible", false)
	victim.set("last_attacker", killer)
	victim.call("take_damage", 99999.0, null)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Game.mp_active_match["roster"] = []
	Game.loadout["team_size"] = 2
	Game.loadout["mode"] = "deathmatch"
	Game.settings["bot_difficulty"] = 2
	var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arena)
	for i in 2:
		await get_tree().process_frame
	if arena.get("_start_pick_open"):
		arena.get("hud").squad_slot_selected.emit(0)
		arena.get("hud").spawn_selected.emit(0)
	arena.set("powerup_every_s", 1000.0)
	for i in 10:
		await get_tree().physics_frame
	var me: Node = arena.get("player_mech")
	var team: int = int(me.get("team"))
	var mate: Node = arena.get("_team_mechs")[team][1]
	var foes: Array = arena.get("_team_mechs")[1 - team]
	var my_ri: int = int(me.get("roster_idx"))
	var pid: int = int(me.get("owner_peer_id"))
	var base: int = arena.get_script().get_script_constant_map()["DROP_COINS"][2]
	var bad: Array = []
	# 1. our kill of a plain bot: counted, worth its base, not in the picked-up coins; we carry half
	var picked0: int = int(arena.get("coins_picked").get(pid, 0))
	_kill(foes[0], me)
	await get_tree().physics_frame
	if int(arena.get("kills_by_ri").get(my_ri, 0)) != 1 or int(arena.get("kill_coins_by_ri").get(my_ri, 0)) != base:
		bad.append("our kill counted %s kills / %s coins, want 1 / %d" % [arena.get("kills_by_ri").get(my_ri), arena.get("kill_coins_by_ri").get(my_ri), base])
	if int(arena.get("coins_picked").get(pid, 0)) != picked0:
		bad.append("the kill went into the picked-up coins")
	var share: float = arena.get_script().get_script_constant_map()["KILL_BOUNTY_SHARE"]
	if int(me.get("bounty")) != roundi(base * share):
		bad.append("our bounty %s after one kill, want %d" % [me.get("bounty"), roundi(base * share)])
	# 2. a bot that killed our teammate this life is worth its base + its bounty
	var hunter: Node = foes[1]
	_kill(mate, hunter)
	await get_tree().physics_frame
	var hb: int = int(hunter.get("bounty"))
	if hb != roundi(base * share):
		bad.append("a bot that killed a %d-coin bot carries %d, want %d" % [base, hb, roundi(base * share)])
	_kill(hunter, me)
	await get_tree().physics_frame
	if int(arena.get("kill_coins_by_ri").get(my_ri, 0)) != base + base + hb:
		bad.append("killing the hunter paid %d in all, want %d (base + its bounty)" % [int(arena.get("kill_coins_by_ri").get(my_ri, 0)), base + base + hb])
	# 3. a player's mech: base 0, only its bounty -- a bot that kills us gets half of our bounty
	var my_bounty: int = int(me.get("bounty"))
	var bot_ri: int = int(foes[1].get("roster_idx"))
	var before: int = int(arena.get("kill_coins_by_ri").get(bot_ri, 0))
	_kill(me, foes[1])
	await get_tree().physics_frame
	if int(arena.get("kill_coins_by_ri").get(bot_ri, 0)) - before != my_bounty:
		bad.append("killing our mech (bounty %d) earned %d, want just the bounty" % [my_bounty, int(arena.get("kill_coins_by_ri").get(bot_ri, 0)) - before])
	# 4. the match result carries them and the payout adds them
	var stats: Array = arena.call("_build_mp_stats")
	var mine = stats.filter(func(e): return int(e.get("peer_id", -1)) == pid)
	if mine.is_empty() or int(mine[0].get("kills", 0)) != 2 or int(mine[0].get("kill_coins", 0)) != base + base + hb:
		bad.append("match stats carry %s" % [mine])
	else:
		var after: Dictionary = Game._apply_match_to({"coins": 0, "elo": 1000}, team, team, stats, pid)
		var want: int = Game.apply_coin_pickup_bonus(75 + int(mine[0].get("coins", 0)) + int(mine[0]["kill_coins"]))
		if int(after.get("coins", 0)) != want:
			bad.append("the payout gave %d, want %d (win + pickups + kills)" % [int(after.get("coins", 0)), want])
	if not bad.is_empty():
		_fail("; ".join(bad))
		return
	print("[probe] kill_bounty done (base %d, hunter bounty %d, kill coins %d)" % [base, hb, int(arena.get("kill_coins_by_ri").get(my_ri, 0))])
	get_tree().quit(0)
