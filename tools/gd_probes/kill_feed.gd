extends Node
# T324 probe (HUMAN_FOUND 2026-11-05 late: small kill readout + chat stub under the ability
# marker): destroying an enemy with our weapon puts "<us> > <enemy callsign>" in the HUD feed
# just under the ability marker; a death with no attacker reads "<name> destroyed"; the feed
# keeps the newest 4 lines and drops them after 6 s; a callsign carrying a bbcode tag shows as
# text, not markup.

func _fail(msg: String) -> void:
	push_error("[probe] kill_feed FAIL: " + msg)
	get_tree().quit(1)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Game.loadout["team_size"] = 1
	Game.loadout["sp_bots"] = [0, 2]
	Game.loadout["mode"] = "beacons"
	Game.setup_sp_match()
	for e in Game.mp_active_match["roster"]:  # B135: T365 squads are random -- a shield soaked the 1-damage kill
		if int(e["peer_id"]) == 0:
			e["squad"] = range(5).map(func(_i): return {"mech": "res://resources/mechs/Pegasus.tres", "weapons": ["res://scenes/weapons/RifleLight.tscn", "res://scenes/weapons/RifleLight.tscn"]})
	var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arena)
	for i in 2:
		await get_tree().process_frame
	if arena.get("_start_pick_open"):
		arena.get("hud").squad_slot_selected.emit(0)
		arena.get("hud").spawn_selected.emit(0)
	for i in 5:
		await get_tree().physics_frame
	var hud: Node = arena.get("hud")
	var me: Node = arena.get("player_mech")
	var roster: Array = Game.mp_active_match["roster"]
	var foes: Array = arena.get("_team_mechs")[1 - int(me.get("team"))]
	var foe: Node = foes[0]
	var my_name := str(roster[int(me.get("roster_idx"))]["name"])
	var foe_name := str(roster[int(foe.get("roster_idx"))]["name"])
	foe.health = 1.0  # V28 clamps a hit to 1.5x the weapon's damage
	foe.request_damage(1.0, me.get_weapons()[0])
	for i in 5:
		await get_tree().process_frame
	var feed: RichTextLabel = hud.get("_feed")
	if feed == null or not feed.visible:
		_fail("no kill feed after a kill")
		return
	var txt := feed.get_parsed_text()
	if not (txt.contains(my_name) and txt.contains(foe_name) and txt.find(my_name) < txt.find(foe_name)):
		_fail("feed reads '%s', want '%s > %s'" % [txt, my_name, foe_name])
		return
	var ab: Control = hud.get("ability_label")
	if feed.position.y < ab.offset_bottom or feed.position.x > ab.offset_left + 1.0:
		_fail("feed at %s isn't under the ability marker (%.0f..%.0f)" % [feed.position, ab.offset_top, ab.offset_bottom])
		return
	var other: Node = foes[1]
	other.set("last_attacker", null)
	other.request_damage(other.health + 1.0, null)
	for i in 5:
		await get_tree().process_frame
	if not feed.get_parsed_text().contains(str(roster[int(other.get("roster_idx"))]["name"]) + " destroyed"):
		_fail("an unattributed death isn't '<name> destroyed': '%s'" % feed.get_parsed_text())
		return
	for i in 4:
		hud.add_chat("[b]x[/b]", "line %d [color=red]r[/color]" % i)
	txt = feed.get_parsed_text()
	if txt.count("\n") != 3:
		_fail("the feed holds %d lines, want 4" % (txt.count("\n") + 1))
		return
	if not txt.contains("[b]x[/b]") or not txt.contains("[color=red]"):
		_fail("markup in a name / chat line was applied, not shown: '%s'" % txt)
		return
	for i in 400:  # > 6 s of frames even at a fast headless rate
		await get_tree().process_frame
	await get_tree().create_timer(6.5).timeout
	if feed.visible:
		_fail("the feed didn't clear after 6 s: '%s'" % feed.get_parsed_text())
		return
	print("[probe] kill_feed done ('%s > %s')" % [my_name, foe_name])
	get_tree().quit(0)
