extends Node
# T343 probe (HUMAN_FOUND Q6, user: Pegasus "healed full from 20% ... Only happened once"): three
# repair kits on one spot (bots dying close together) used to be taken in the same tick --
# 20% + 3 x 35% = full. Now our mech takes one (20% -> 55%), the others wait on the ground, and
# the next is taken once REPAIR_GAP_S has passed.

func _fail(msg: String) -> void:
	push_error("[probe] repair_stack FAIL: " + msg)
	get_tree().quit(1)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Game.mp_active_match["roster"] = []
	Game.loadout["team_size"] = 1
	Game.loadout["mode"] = "deathmatch"
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
	me.set("invincible", false)
	var spot: Vector3 = me.global_position + Vector3(0, 0, -6)
	for k in 3:
		arena.call("_rpc_spawn_pickup", 900 + k, "repair", spot + Vector3(0.3 * k, 0, 0), 0)
	var full: float = me.get("max_health")
	me.set("health", full * 0.2)
	me.global_position = Vector3(spot.x, me.global_position.y, spot.z)
	for i in 6:
		await get_tree().physics_frame
	var h1: float = me.get("health")
	var left := (arena.get("_pickups") as Dictionary).size()
	if h1 > full * 0.56:
		_fail("walking onto 3 stacked repair kits healed 20%% -> %.0f%% at once (want one kit: 55%%)" % (100.0 * h1 / full))
		return
	if left != 2:
		_fail("%d kits left on the ground after taking one (want 2)" % left)
		return
	await get_tree().create_timer(float(arena.get("REPAIR_GAP_S")) + 0.3, true, true).timeout
	var h2: float = me.get("health")
	if h2 <= h1 + 1.0:
		_fail("the next kit wasn't taken after the gap (%.0f%% -> %.0f%%)" % [100.0 * h1 / full, 100.0 * h2 / full])
		return
	print("[probe] repair_stack done (20%% -> %.0f%% -> %.0f%%)" % [100.0 * h1 / full, 100.0 * h2 / full])
	get_tree().quit(0)
