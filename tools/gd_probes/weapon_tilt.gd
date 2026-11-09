extends Node
# T329 probe (user 2026-11-05: "make the weapons tilt up and down as they aim") + T353 (HUMAN_FOUND
# 2026-11-08: guns looked "aimed high ... Make sure level camera means level gun"): on an open deck
# high above the map, a level camera holds the guns level (they point at the crosshair's far
# point), aiming up tilts them up, looking down at the deck close by tilts them down to the clamp,
# and a remote mech's guns follow the aim pitch that rides the snapshot.

const DECK_Y := 400.0

func _fail(msg: String) -> void:
	push_error("[probe] weapon_tilt FAIL: " + msg)
	get_tree().quit(1)

func _tilts(m: Node) -> Array:
	var out := []
	for c in (m.get("torso") as Node3D).get_children():
		if String(c.name).begins_with("Hardpoint"):
			out.append(snappedf((c as Node3D).rotation.x, 0.01))
	return out

func _check(m: Node, what: String, lo: float, hi: float) -> bool:
	var ts := _tilts(m)
	if ts.is_empty():
		_fail("no hardpoints (%s)" % what)
		return false
	for t in ts:
		if t < lo or t > hi:
			_fail("%s: guns at %s, want %.2f..%.2f" % [what, ts, lo, hi])
			return false
	return true

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
	var deck := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(800, 2, 800)
	cs.shape = box
	deck.add_child(cs)
	arena.add_child(deck)
	deck.global_position = Vector3(0, DECK_Y - 1.0, 0)
	var me: Node3D = arena.get("player_mech")
	var bot: Node3D = arena.get("_team_mechs")[1 - int(me.get("team"))][0]
	me.global_position = Vector3(-100, DECK_Y + 0.5, 0)
	bot.global_position = Vector3(100, DECK_Y + 0.5, 0)
	me.set_input_source(null)  # hold the pitch we set
	for c in [[0.0, "level camera", -0.06, 0.06], [0.35, "aiming up", 0.2, 0.45], [-1.2, "looking down at the deck", -0.46, -0.44]]:
		me.set("_camera_pitch", c[0])
		for i in 3:  # process_frame fires before the nodes' _process; the camera arm follows in _process
			await get_tree().process_frame
		if not _check(me, "%s (pitch %.2f)" % [c[1], c[0]], c[2], c[3]):
			return
	bot.set_input_source(null)
	bot.call("receive_snapshot", {"pos": bot.global_position, "quat": bot.global_transform.basis.get_rotation_quaternion(),
		"vel": Vector3.ZERO, "torso_y": (bot.get("torso") as Node3D).rotation.y, "pitch": 0.35})
	bot.call("_apply_snapshot_interp")
	for i in 3:
		await get_tree().process_frame
	if absf(float(bot.get("_camera_pitch")) - 0.35) > 0.01:
		_fail("a snapshot's aim pitch didn't reach the remote mech (%.2f)" % bot.get("_camera_pitch"))
		return
	if not _check(bot, "remote mech aiming up", 0.2, 0.45):
		return
	print("[probe] weapon_tilt done (%s)" % [_tilts(me)])
	get_tree().quit(0)
