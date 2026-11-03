extends Node
# T198 probe: a bot burns through its 5-mech squad like a human. Each death brings the
# next squad mech back after Arena.BOT_RESPAWN_S, under a unique name, still driven by
# the same AI; the team is out (match over) only after the last one. Before T198 a bot
# had 1 life: in this 1v1 the first kill ended the match.

func _fail(msg: String) -> void:
	push_error("[probe] bot_squad: " + msg)

func _ready() -> void:
	Game.mp_active_match["roster"] = []  # Arena sets up SP from the loadout
	Game.loadout["team_size"] = 1
	var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arena)
	for i in 60:
		await get_tree().physics_frame
	arena.get("player_mech").invincible = true
	var bot: Node = arena.get_node("BotPlayer_1_0")
	var names := {}
	var kills := 0
	for k in 5:
		var m: Node = bot.get("pawn")
		if m == null or m.get("is_dead"):
			_fail("no live bot mech before kill %d" % (k + 1))
			break
		if names.has(m.name):
			_fail("respawned mech reuses the name %s" % m.name)
		names[m.name] = true
		m.take_damage(1e9)
		kills += 1
		if k == 4:
			break
		for i in 30:
			await get_tree().physics_frame
		if arena.get("_match_over"):
			_fail("match ended after kill %d of 5 (bot had no squad)" % kills)
			break
		for i in int(arena.BOT_RESPAWN_S * 60) + 30:
			await get_tree().physics_frame
		var nm: Node = bot.get("pawn")
		if nm == null or nm == m or nm.get("is_dead") or nm.get("_input_source") == null:
			_fail("no respawned, AI-driven bot mech after kill %d" % kills)
			break
	for i in 5:
		await get_tree().physics_frame
	if kills == 5 and not arena.get("_match_over"):
		_fail("match still running after the bot's last squad mech died")
	print("[probe] bot_squad done (kills %d, mechs %s, over=%s)" % [kills, names.keys(), arena.get("_match_over")])
	get_tree().quit(0)
