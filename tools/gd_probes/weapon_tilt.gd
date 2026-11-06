extends Node
# T329 probe (user 2026-11-05: "How hard would it be to make the weapons tilt up and down as they
# aim? If easy, add it to the queue"): a mech's guns pitch with its aim -- level at the camera's
# level-aim pitch, up when aiming up, clamped -- and a remote mech's guns follow the aim pitch
# that rides the snapshot.

func _fail(msg: String) -> void:
	push_error("[probe] weapon_tilt FAIL: " + msg)
	get_tree().quit(1)

func _tilts(m: Node) -> Array:
	var out := []
	for c in (m.get("torso") as Node3D).get_children():
		if String(c.name).begins_with("Hardpoint"):
			out.append(snappedf((c as Node3D).rotation.x, 0.01))
	return out

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Game.mp_active_match["roster"] = []
	Game.loadout["team_size"] = 1
	Game.loadout["sp_bots"] = [0, 1]
	Game.loadout["mode"] = "deathmatch"
	var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arena)
	for i in 2:
		await get_tree().process_frame
	if arena.get("_start_pick_open"):
		arena.get("hud").squad_slot_selected.emit(0)
		arena.get("hud").spawn_selected.emit(0)
	for i in 5:
		await get_tree().physics_frame
	var me: Node = arena.get("player_mech")
	me.set_input_source(null)  # hold the pitch we set
	var neutral: float = float(me.get("TILT_NEUTRAL")) if me.get("TILT_NEUTRAL") != null else -0.3
	for c in [[neutral + 0.3, 0.3], [neutral, 0.0], [-1.2, -0.45]]:
		me.set("_camera_pitch", c[0])
		for i in 2:  # process_frame fires before the nodes' _process
			await get_tree().process_frame
		for t in _tilts(me):
			if absf(t - c[1]) > 0.02:
				_fail("aim pitch %.2f: guns at %s, want %.2f" % [c[0], _tilts(me), c[1]])
				return
	if _tilts(me).is_empty():
		_fail("no hardpoints on the player's mech")
		return
	var bot: Node = arena.get("_team_mechs")[1 - int(me.get("team"))][0]
	bot.set_input_source(null)
	bot.call("receive_snapshot", {"pos": (bot as Node3D).global_position, "quat": (bot as Node3D).global_transform.basis.get_rotation_quaternion(),
		"vel": Vector3.ZERO, "torso_y": (bot.get("torso") as Node3D).rotation.y, "pitch": neutral + 0.2})
	bot.call("_apply_snapshot_interp")
	for i in 2:
		await get_tree().process_frame
	if absf(float(bot.get("_camera_pitch")) - (neutral + 0.2)) > 0.01:
		_fail("a snapshot's aim pitch didn't reach the remote mech (%.2f)" % bot.get("_camera_pitch"))
		return
	for t in _tilts(bot):
		if absf(t - 0.2) > 0.02:
			_fail("remote mech guns at %s, want 0.20" % [_tilts(bot)])
			return
	print("[probe] weapon_tilt done (%s)" % [_tilts(me)])
	get_tree().quit(0)
