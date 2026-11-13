extends Node
# T408 probe (HUMAN_FOUND, queued 2026-11-13: "Targeting reticle should be grey if no equipped weapon
# is within range. There should be no max distance at which it appears."): an enemy in the crosshair
# gets the box at 300 m (past the old 200 m search), grey because nothing we carry reaches it; at 30 m
# it's red; and no lock builds out of range (T334 stays).

func _fail(msg: String) -> void:
	push_error("[probe] reticle_range FAIL: " + msg)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Game.mp_active_match["roster"] = []
	Game.loadout["team_size"] = 1
	var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arena)
	for i in 2:
		await get_tree().process_frame
	if arena.get("_start_pick_open"):
		arena.get("hud").squad_slot_selected.emit(0)
		arena.get("hud").spawn_selected.emit(0)
	for i in 10:
		await get_tree().physics_frame
	var me: Node3D = arena.get("player_mech")
	var enemy: Node3D = arena.get("_team_mechs")[1 - int(me.get("team"))][0]
	enemy.invincible = true
	var stop: Node = load("res://scripts/InputSource.gd").new()
	add_child(stop)
	enemy.call("set_input_source", stop)
	me.set("_camera_pitch", 0.0)  # level crosshair: 300 m down the default pitch is under the floor
	me.global_position.y += 30.0   # and above the map's clutter (it floats down slowly meanwhile)
	for i in 3:
		await get_tree().process_frame
	var hud: Node = arena.get("hud")
	var box: Control = hud.get("eligible_indicator")
	var reach: float = 0.0
	for w in me.call("get_weapons"):
		reach = maxf(reach, float(w.get("range")))
	for dist in [30.0, 300.0]:
		var cam: Camera3D = me.get("camera")
		var fwd := -cam.global_transform.basis.z
		var cm_off: Vector3 = enemy.call("center_mass") - enemy.global_position
		enemy.global_position = cam.global_position + fwd * dist - cm_off  # centre mass on the crosshair ray
		for i in 20:
			await get_tree().physics_frame
		var shown: bool = box.visible and me.get("lock_eligible_target") == enemy
		var col: Color = box.get("color") if box.get("color") != null else Color(1, 0, 0)
		var grey: bool = absf(col.r - col.g) < 0.1
		if not shown:
			_fail("no reticle box on an enemy in the crosshair %.0f m away" % dist)
		elif dist <= reach and grey:
			_fail("box grey at %.0f m, within reach %.0f m" % [dist, reach])
		elif dist > reach and not grey:
			_fail("box %s at %.0f m, beyond every weapon's %.0f m (want grey)" % [col, dist, reach])
	if me.get("locked_target") == enemy:
		_fail("a lock built on a target out of range")
	print("[probe] reticle_range done (reach %.0f m)" % reach)
	get_tree().quit(0)
