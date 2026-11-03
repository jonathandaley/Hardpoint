extends Node
# T196 probe (HUMAN_FOUND_ISSUES: "the mech blocks too much of the view while aiming";
# user picked over-the-shoulder): the player's camera sits beside the torso, so the mech
# is left of the crosshair (screen centre); V (swap_shoulder) moves it to the other side.

func _fail(msg: String) -> void:
	push_error("[probe] shoulder_cam: " + msg)

func _side(m: Node) -> float:  # mech's screen x relative to the crosshair, in viewport widths
	var cam: Camera3D = m.get("camera")
	var w := get_viewport().get_visible_rect().size.x
	return (cam.unproject_position((m.get("torso") as Node3D).global_position) .x - w * 0.5) / w

func _press_v() -> void:
	var ev := InputEventAction.new()
	ev.action = "swap_shoulder"
	ev.pressed = true
	Input.parse_input_event(ev)
	await get_tree().process_frame
	ev = InputEventAction.new()
	ev.action = "swap_shoulder"
	ev.pressed = false
	Input.parse_input_event(ev)

func _ready() -> void:
	Game.mp_active_match["roster"] = []
	Game.loadout["team_size"] = 1
	Game.shoulder = 1.0
	var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arena)
	for i in 2:
		await get_tree().process_frame
	if arena.get("_start_pick_open"):
		arena.get("hud").squad_slot_selected.emit(0)
		arena.get("hud").spawn_selected.emit(0)
	for i in 60:
		await get_tree().process_frame
	var m: Node = arena.get("player_mech")
	m.invincible = true
	var arm: Node3D = m.get("camera_arm")
	var right_x := arm.position.x
	var right_side := _side(m)
	if right_x < 1.0 or right_side > -0.03:
		_fail("camera not over the right shoulder (arm x %.2f, mech at %.2f of the screen from centre)" % [right_x, right_side])
	await _press_v()
	for i in 60:
		await get_tree().process_frame
	var left_x := arm.position.x
	var left_side := _side(m)
	if left_x > -1.0 or left_side < 0.03:
		_fail("V did not swap to the left shoulder (arm x %.2f, mech at %.2f)" % [left_x, left_side])
	print("[probe] shoulder_cam done (arm x %.2f -> %.2f, mech %.2f -> %.2f of the screen)" % [right_x, left_x, right_side, left_side])
	Game.shoulder = 1.0
	get_tree().quit(0)
