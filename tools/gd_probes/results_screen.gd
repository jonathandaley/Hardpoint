extends Node
# T215 probe: after a 5v5 match the results screen fits the screen -- its button is
# on screen and a real click on it leaves (SP: to the hangar). The user saw the game
# "freeze" on the results: the button sat below the screen edge under a long table
# (SP stuck for good, MP until the 30 s auto-return).

func _fail(msg: String) -> void:
	push_error("[probe] results_screen: " + msg)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Game.mp_active_match["roster"] = []
	Game.loadout["team_size"] = 5
	var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arena)
	for i in 2:
		await get_tree().process_frame
	if arena.get("_start_pick_open"):
		arena.get("hud").squad_slot_selected.emit(0)
		arena.get("hud").spawn_selected.emit(0)
	for i in 30:
		await get_tree().physics_frame
	arena.get("match_node").force_end(0)
	for i in 10:
		await get_tree().process_frame
	var b := arena.get("hud").find_child("BackToLobbyBtn", true, false) as Button
	if b == null:
		_fail("no results button")
		get_tree().quit(0)
		return
	var view := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	var r := b.get_global_rect()
	if not view.encloses(r):
		_fail("results button off screen: %s in %s" % [r, view])
	# a real click at its centre (as tools/mp_harness does) must press it. The real
	# handler changes scene (freeing this probe) -- unhook it and count the press.
	for c in b.pressed.get_connections():
		b.pressed.disconnect(c["callable"])
	var hits := [0]
	b.pressed.connect(func() -> void: hits[0] += 1)
	var at := r.get_center()
	get_viewport().notification(Node.NOTIFICATION_VP_MOUSE_ENTER)
	var mv := InputEventMouseMotion.new()
	mv.position = at
	get_viewport().push_input(mv, true)
	for down in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = down
		ev.position = at
		get_viewport().push_input(ev, true)
	await get_tree().process_frame
	if hits[0] != 1:
		_fail("a click on the results button did not press it")
	print("[probe] results_screen done (button %s, presses %d)" % [r, hits[0]])
	get_tree().quit(0)
