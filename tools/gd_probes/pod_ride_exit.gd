extends Node
# T559 probe (chaos_12): a player's mech died right at a match end and its pilot clicked BACK TO LOBBY
# inside the 0.75 s pod ride; Arena._ride_pod ran on with the Arena out of the tree (engine errors from
# get_global_transform, then a SCRIPT ERROR on a null get_tree()). The ride must stop when the Arena
# leaves: no engine error from here to the quit (crash_scan rules).

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
	var pod := Node3D.new()
	arena.add_child(pod)
	pod.global_position = Vector3(0, 6, 0)
	arena.call("_ride_pod", pod)  # a coroutine: runs to its first await
	await get_tree().process_frame
	get_tree().root.remove_child(arena)  # what the scene change does to it
	await get_tree().create_timer(1.0).timeout  # past POD_RIDE_S (real time)
	arena.queue_free()
	await get_tree().process_frame
	print("[probe] pod_ride_exit done")
	get_tree().quit(0)
