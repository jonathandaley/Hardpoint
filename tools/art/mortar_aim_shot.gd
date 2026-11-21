extends Node
# T549 art review: the player's mortar aim marker (arrow + ground target) from the player's camera, on bare
# ground and with an enemy standing on the spot.
#   xvfb-run -a -s "-screen 0 1280x720x24" ~/bin/godot --resolution 1280x720 \
#     res://tools/art/mortar_aim_shot.tscn -- <out_prefix>
func _shot(path: String) -> void:
	for i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)

func _ready() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
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
	slot.slot_size = 1
	slot.position = Vector3(0.7, 1.5, 0.3)
	slot.weapon_scene = load("res://scenes/weapons/MortarHeavy.tscn")
	me.call("configure_weapons", [slot])
	me.set("lob_range", 24.0)
	for i in 5:
		await get_tree().physics_frame
	await _shot(out + "_ground.png")
	var mg: Node = me.get_weapons()[0]
	var foe: Node3D = arena.get("_team_mechs")[1][0]
	foe.set_physics_process(false)
	foe.global_position = mg.call("aim_point")
	await _shot(out + "_mech.png")
	foe.global_position += Vector3(0, -50, 0)  # out of the way
	me.set("lob_range", 9.0)
	await _shot(out + "_near.png")
	get_tree().quit(0)
