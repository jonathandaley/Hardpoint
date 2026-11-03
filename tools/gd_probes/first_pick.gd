extends Node
# T187 probe: the squad picker opens before the first fight (SP: match paused), a pick
# swaps the slot-0 mech for the chosen one without costing a life, and slot 0 goes back
# to the pool (offered again at the next death). Squad: Slip 175, Hornet 450, Hippogriff
# 500, Vesuvius 1000, Pegasus 300 HP -- max_health identifies which mech you're in.

const SQUAD := ["Slip", "Hornet", "Hippogriff", "Vesuvius", "Pegasus"]

func _fail(msg: String) -> void:
	push_error("[probe] first_pick: " + msg)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # runs while the start picker pauses SP
	Game.mp_active_match["roster"] = []
	Game.loadout["team_size"] = 1
	Game.loadout["squad"] = SQUAD.map(func(n: String) -> String: return "res://resources/mechs/%s.tres" % n)
	var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arena)
	for i in 10:
		await get_tree().process_frame
	var hud: Node = arena.get("hud")
	var player: Node = arena.get("_player")
	if not arena.get("_start_pick_open"):
		_fail("no squad picker at match start")
	elif not get_tree().paused:
		_fail("SP did not pause while the first mech is picked")
	var first: Node = arena.get("player_mech")
	hud.squad_slot_selected.emit(3)  # what the VESUVIUS button does
	hud.spawn_selected.emit(0)
	for i in 10:
		await get_tree().physics_frame
	var now: Node = arena.get("player_mech")
	var used: Array = arena.get("_peer_slot_used")[1]
	if get_tree().paused:
		_fail("still paused after the pick")
	if now == first or now.max_health != 1000.0:
		_fail("pick 3 (Vesuvius) did not swap the mech (now %s HP)" % now.max_health)
	if first.visible or not first.get("is_dead"):
		_fail("the slot-0 mech is still in the match")
	if player.get("lives") != 5:
		_fail("the swap cost a life (lives %d)" % player.get("lives"))
	if used != [false, false, false, true, false]:
		_fail("slot bookkeeping after the swap: %s" % [used])
	now.take_damage(1e9)  # the next death offers slot 0 again
	for i in 3:
		await get_tree().process_frame
	hud.squad_slot_selected.emit(0)
	hud.spawn_selected.emit(0)
	for i in 10:
		await get_tree().physics_frame
	var back: Node = arena.get("player_mech")
	if back == now or back.max_health != 175.0 or player.get("lives") != 4:
		_fail("slot 0 (Slip) not available after the swap (HP %s, lives %d)" % [back.max_health, player.get("lives")])
	print("[probe] first_pick done (swap -> %s HP, then %s HP, lives %d)" % [now.max_health, back.max_health, player.get("lives")])
	get_tree().paused = false
	get_tree().quit(0)
