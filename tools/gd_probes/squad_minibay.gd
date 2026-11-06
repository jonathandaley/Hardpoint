extends Node
# T323 probe (HUMAN_FOUND 2026-11-05 late: "The mech picker for matches should look like a
# miniature version of the hangar ... Just enough to see what weapons they have equipped so you
# can tell the difference between mechs with the same name in the squad"): the in-match picker
# shows one card per available mech with a 3D model carrying that slot's weapons -- two Pegasus
# with different guns show different guns -- and a card's button picks that slot.

func _fail(msg: String) -> void:
	push_error("[probe] squad_minibay FAIL: " + msg)
	get_tree().quit(1)

func _guns(card: Node) -> Array:
	var out := []
	for w in card.find_children("*", "", true, false):
		if w.has_method("fire") and w.get("owner_mech") != null:
			out.append(String(w.scene_file_path).get_file())
	out.sort()
	return out

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Game.loadout["team_size"] = 1
	Game.loadout["sp_bots"] = [0, 1]
	Game.loadout["mode"] = "deathmatch"
	Game.setup_sp_match()
	var peg := "res://resources/mechs/Pegasus.tres"
	var a := ["res://scenes/weapons/RifleLight.tscn", "res://scenes/weapons/RifleLight.tscn"]
	var b := ["res://scenes/weapons/LaserCannonLight.tscn", "res://scenes/weapons/LaserCannonLight.tscn"]
	for e in Game.mp_active_match["roster"]:
		if int(e["peer_id"]) != 0:
			e["squad"] = [{"mech": peg, "weapons": a}, {"mech": peg, "weapons": b}]
	var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arena)
	for i in 4:
		await get_tree().process_frame
	var hud: Node = arena.get("hud")
	var row: Node = hud.find_child("MechCards", true, false)
	if row == null:
		_fail("the picker has no mech cards (plain buttons?)")
		return
	var cards: Array = row.get_children()
	if cards.size() != 2:
		_fail("%d cards for a 2-mech squad" % cards.size())
		return
	var g0 := _guns(cards[0])
	var g1 := _guns(cards[1])
	if g0.is_empty() or g1.is_empty():
		_fail("a card shows no weapons (%s / %s)" % [g0, g1])
		return
	if g0 == g1:
		_fail("two Pegasus with different guns look the same (%s)" % [g0])
		return
	if not g0.has("RifleLight.tscn") or not g1.has("LaserCannonLight.tscn"):
		_fail("cards carry %s / %s, not their slots' weapons" % [g0, g1])
		return
	if cards[0].find_children("*", "SubViewport", true, false).is_empty():
		_fail("card 0 has no 3D view")
		return
	var picked := [-1]
	hud.squad_slot_selected.connect(func(i: int) -> void: picked[0] = i)
	(cards[1].find_children("*", "Button", true, false)[0] as Button).pressed.emit()
	if picked[0] != 1:
		_fail("card 1's button picked slot %d" % picked[0])
		return
	print("[probe] squad_minibay done (%s | %s)" % [g0, g1])
	get_tree().quit(0)
