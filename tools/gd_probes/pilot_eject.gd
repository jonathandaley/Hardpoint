extends Node
# T267 probe (HUMAN_FOUND 2026-11-05 "bots should eject on death like players"; user: "death
# explosion launches a rocket canister skyward at a slight curved angle, leaving a trail of
# smoke. When a player dies, camera should launch upward with it for .5-1 seconds before
# switching to the mech picker"): a destroyed BOT fires a canister that climbs, bends sideways
# and trails smoke; when OUR mech dies a camera rides the canister up, and the mech picker
# opens only after ~0.5-1 s.

func _fail(msg: String) -> void:
	push_error("[probe] pilot_eject FAIL: " + msg)
	get_tree().quit(1)

func _pods(arena: Node) -> Array:
	return arena.get_children().filter(func(n): return String(n.name).begins_with("EjectPod"))

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Game.mp_active_match["roster"] = []
	Game.loadout["team_size"] = 2
	var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arena)
	for i in 2:
		await get_tree().process_frame
	if arena.get("_start_pick_open"):
		arena.get("hud").squad_slot_selected.emit(0)
		arena.get("hud").spawn_selected.emit(0)
	for i in 10:
		await get_tree().physics_frame
	var me: Node = arena.get("player_mech")
	var bot: Node = arena.get("_team_mechs")[1 - int(me.get("team"))][0]
	bot.set("invincible", false)
	bot.call("take_damage", 99999.0, null)
	await get_tree().process_frame
	var pods := _pods(arena)
	if pods.is_empty():
		_fail("a destroyed bot fired no canister")
		return
	var pod: Node3D = pods[0]
	var p0 := pod.global_position
	var before := arena.get_children().size()
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 600:
		await get_tree().process_frame
	# the trail: smoke puffs left behind in the world below the canister
	var smoking: bool = arena.get_children().slice(before).filter(func(n): return n is MeshInstance3D and (n as Node3D).global_position.y < pod.global_position.y - 1.0).size() >= 5
	var d := pod.global_position - p0
	if d.y < 5.0 or Vector2(d.x, d.z).length() < 0.3 or not smoking:
		_fail("canister climbed %.1f m, drifted %.2f m, smoke %s in 0.6 s (want > 5 m up, curving, smoking)" % [d.y, Vector2(d.x, d.z).length(), smoking])
		return
	# our own death: ride, then the picker
	var hud: Node = arena.get("hud")
	me.set("invincible", false)
	me.call("take_damage", 99999.0, null)
	await get_tree().process_frame
	var cam := get_viewport().get_camera_3d()
	if cam == null or String(cam.name) != "PodRideCam":
		_fail("no camera ride after our death (current camera %s)" % (cam.name if cam else "none"))
		return
	var y0 := cam.global_position.y
	var picker_at := -1
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 1500 and picker_at < 0:
		await get_tree().process_frame
		var pk = hud.get("_squad_picker")
		if pk != null and is_instance_valid(pk):
			picker_at = Time.get_ticks_msec() - t0
	if picker_at < 450 or picker_at > 1300:
		_fail("mech picker opened after %d ms (want ~0.5-1 s after the death)" % picker_at)
		return
	if not is_instance_valid(cam) or cam.global_position.y - y0 < 3.0:
		_fail("the death camera didn't climb with the canister (%.1f m)" % ((cam.global_position.y - y0) if is_instance_valid(cam) else -1.0))
		return
	print("[probe] pilot_eject done (bot canister +%.1f m / %.2f m sideways; picker after %d ms)" % [d.y, Vector2(d.x, d.z).length(), picker_at])
	get_tree().quit(0)
