extends Node
# T161 probe: the single-player pause (Arena._toggle_pause sets get_tree().paused)
# must freeze the match -- match clock, bots, beacons -- while the pause menu
# still works. Pre-T161 Arena set itself PROCESS_MODE_ALWAYS and every child
# inherited it, so pausing froze nothing.

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # the probe itself must run while paused
	Game.mp_active_match["roster"] = []      # Arena sets up SP from the loadout (T184)
	var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arena)
	for i in 2:
		await get_tree().process_frame
	if arena.get("_start_pick_open"):  # T187: keep slot 0, as a player would
		arena.get("hud").squad_slot_selected.emit(0)
		arena.get("hud").spawn_selected.emit(0)
	for i in 180:  # let the match start and bots get moving
		await get_tree().physics_frame
	var match_node: Node = arena.get_node_or_null("BeaconMatch")
	var before := _state(arena, match_node)
	arena.call("_toggle_pause")  # exactly what Esc does
	for i in 120:
		await get_tree().physics_frame
	var during := _state(arena, match_node)
	var moved: Array = []
	for k in before:
		if k != "elapsed" and (before[k] as Vector3).distance_to(during[k]) > 0.01:
			moved.append(k)
	if absf(float(during["elapsed"]) - float(before["elapsed"])) > 0.001:
		push_error("[probe] sp_pause: match clock ran while paused (%.2f -> %.2f s)" % [before["elapsed"], during["elapsed"]])
	if not moved.is_empty():
		push_error("[probe] sp_pause: mechs moved while paused: %s" % str(moved))
	if not arena.get_node("PauseMenu").visible:
		push_error("[probe] sp_pause: pause menu not shown")
	var esc := InputEventAction.new()  # resume the way a player does: Esc while paused
	esc.action = "ui_cancel"
	esc.pressed = true
	Input.parse_input_event(esc)
	for i in 30:
		await get_tree().physics_frame
	if get_tree().paused or arena.get_node("PauseMenu").visible:
		push_error("[probe] sp_pause: Esc while paused did not resume")
	if float(_state(arena, match_node)["elapsed"]) <= float(during["elapsed"]):
		push_error("[probe] sp_pause: match clock did not resume")
	print("[probe] sp_pause done (moved while paused: %d, clock %.2f -> %.2f)" % [moved.size(), before["elapsed"], during["elapsed"]])
	get_tree().paused = false
	get_tree().quit(0)

func _state(arena: Node, match_node: Node) -> Dictionary:
	var d := {"elapsed": match_node.get("elapsed") if match_node != null else 0.0}
	for m in get_tree().get_nodes_in_group("mechs"):
		d[m.name] = (m as Node3D).global_position
	return d
