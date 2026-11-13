extends Node
# T373 art review: a shielded enemy 18 m ahead, shield half full -- the blue bar under its health bar.
#   xvfb-run -a -s "-screen 0 1280x720x24" ~/bin/godot --resolution 1280x720 \
#     res://tools/art/shield_bar_shot.tscn -- <out.png>

func _fail(msg: String) -> void:
	push_error("shield_bar_shot: " + msg)

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
	var stop: Node = load("res://scripts/InputSource.gd").new()  # inert: the enemy stands still
	add_child(stop)
	enemy.call("set_input_source", stop)
	var cam: Camera3D = me.get("camera")
	enemy.global_position = cam.global_position + (-cam.global_transform.basis.z * Vector3(1, 0, 1)).normalized() * 18.0
	enemy.global_position.y = me.global_position.y
	var es: Node = enemy.get_node("EnergyShield")
	var hud: Node = arena.get("hud")
	if not es.get("_active"):  # no shield on this mech: none drawn
		for i in 5:
			await get_tree().process_frame
		for r in hud.find_children("ShieldBar", "ColorRect", true, false):
			if r.visible:
				_fail("a shield bar shows for a mech without a shield")
		enemy.call("configure_energy_shield", true, 200.0, 10.0, 5.0)
	es.set("shield_hp", float(es.max_shield_hp) * 0.5)
	es.set("_regen_timer", 60.0)
	for i in 5:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_cmdline_user_args()[0])
	get_tree().quit(0)
