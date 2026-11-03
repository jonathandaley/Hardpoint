extends Node
# T193 probe: Settings -> Shadows BLOB (default) turns the sun's shadows off and puts a
# disc on the ground under every mech (hidden while stealthed); FULL keeps the pre-T193
# sun shadows and no discs.

func _fail(msg: String) -> void:
	push_error("[probe] blob_shadow: " + msg)

func _arena() -> Node:
	Game.mp_active_match["roster"] = []
	var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arena)
	for i in 2:
		await get_tree().process_frame
	if arena.get("_start_pick_open"):
		arena.get("hud").squad_slot_selected.emit(0)
	for i in 90:
		await get_tree().physics_frame
	return arena

func _blob(m: Node) -> MeshInstance3D:
	for c in m.get_children():
		if c is MeshInstance3D and c.has_method("_material"):
			return c
	return null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Game.loadout["team_size"] = 2
	Game.settings["shadows"] = "blob"
	var arena: Node = await _arena()
	if arena.get_node("Sun").shadow_enabled:
		_fail("BLOB mode left the sun casting shadows")
	var checked := 0
	for m in get_tree().get_nodes_in_group("mechs"):
		var b := _blob(m)
		if b == null or not b.visible:
			_fail("%s has no visible blob shadow" % m.name)
			continue
		var feet: Vector3 = (m as Node3D).global_position
		var flat := Vector2(b.global_position.x - feet.x, b.global_position.z - feet.z).length()
		if flat > 0.2 or absf(b.global_position.y - feet.y) > 1.0:
			_fail("%s blob is %.2f m off in plan, %.2f m off in height" % [m.name, flat, b.global_position.y - feet.y])
		checked += 1
	var m0: Node = arena.get("player_mech")
	m0.set("is_stealthy", true)
	for i in 2:  # process_frame fires before _process: the blob updates on the frame after
		await get_tree().process_frame
	if _blob(m0).visible:
		_fail("blob shadow shows a stealthed mech")
	m0.set("is_stealthy", false)
	arena.queue_free()
	await get_tree().process_frame
	Game.settings["shadows"] = "full"
	arena = await _arena()
	if not arena.get_node("Sun").shadow_enabled:
		_fail("FULL mode lost the sun's shadows")
	for m in get_tree().get_nodes_in_group("mechs"):
		if _blob(m) != null:
			_fail("FULL mode still adds blob shadows (%s)" % m.name)
			break
	print("[probe] blob_shadow done (%d mechs with discs)" % checked)
	get_tree().quit(0)
