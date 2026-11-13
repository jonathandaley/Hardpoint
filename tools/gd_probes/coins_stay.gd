extends Node
# T413 probe (HUMAN_FOUND, queued 2026-11-13: "Coins should not vanish."): a coin on the ground
# stays past PICKUP_LIFE_S; a powerup still goes when its time is up (T383: 2 minutes).

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
	arena.set("powerup_every_s", 100000.0)
	var far := Vector3(0, 400, 0)  # out of everyone's reach
	arena.call("_rpc_spawn_pickup", 9001, "coin", far, 5)
	arena.call("_rpc_spawn_pickup", 9002, "damage", far + Vector3(4, 0, 0), 0)
	var life: float = arena.get_script().get_script_constant_map()["PICKUP_LIFE_S"]
	for id in [9001, 9002]:
		arena.get("_pickups")[id].set("age", life + 1.0)
	for i in 5:
		await get_tree().physics_frame
	var left: Dictionary = arena.get("_pickups")
	if not left.has(9001):
		push_error("[probe] coins_stay: a coin vanished after %.0f s on the ground" % life)
	if left.has(9002):
		push_error("[probe] coins_stay: a powerup outlived its %.0f s" % life)
	print("[probe] coins_stay done")
	get_tree().quit(0)
