extends Node
# T551 art review: Tracer Rounds -- the player's MG firing with tracers on, from the player's camera.
#   xvfb-run -a -s "-screen 0 1280x720x24" ~/bin/godot --resolution 1280x720 res://tools/art/tracer_shot.tscn -- <out.png>
func _ready() -> void:
	Game.loadout["team_size"] = 3
	Game.setup_sp_match()
	var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arena)
	for i in 2:
		await get_tree().process_frame
	if arena.get("_start_pick_open"):
		arena.get("hud").squad_slot_selected.emit(0)
		arena.get("hud").spawn_selected.emit(0)
	for i in 20:
		await get_tree().physics_frame
	var me: Node3D = arena.get("player_mech")
	var slot = load("res://scripts/WeaponSlotDef.gd").new()
	slot.slot_size = 0
	slot.position = Vector3(0.7, 1.5, 0.3)
	slot.weapon_scene = load("res://scenes/weapons/MachineGunLight.tscn")
	me.call("configure_weapons", [slot])
	me.set("pilot_skills", {"spread_reduction": 1, "tracer_rounds": 1})
	me.set("tracers_on", true)
	arena.get("hud").call("tracer_notice", true)
	me.set("_camera_pitch", 0.12)  # over the maze walls, so the rounds fly a while
	me.global_rotation.y += 0.5
	var w: Node = me.get_weapons()[0]
	for i in 24:
		if i % 3 == 0:
			w.call("_do_fire")
		await get_tree().physics_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_cmdline_user_args()[0])
	get_tree().quit(0)
