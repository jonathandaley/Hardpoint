extends Node
# T524 probe (user 2026-11-19: "I saw a bot shooting a laser into a shallow hill ... its weapons are lower
# and were occluded. Make sure they're drawing sight lines perfectly."): a Hard bot 30 m from a target on
# a flat deck behind a low wall whose top the eye line (2 m up) clears but the gun's line doesn't: it
# sees the target (_los_to) yet won't take the shot, and closes in; with the wall gone it shoots.
const DECK_Y := 400.0

func _fail(msg: String) -> void:
	push_error("[probe] bot_muzzle_los FAIL: " + msg)
	get_tree().quit(1)

func _ready() -> void:
	Game.mp_active_match["roster"] = []
	Game.loadout["team_size"] = 1
	Game.loadout["mode"] = "deathmatch"
	Game.setup_sp_match()
	for e in Game.mp_active_match["roster"]:
		if int(e["peer_id"]) == 0:
			e["squad"] = [{"mech": "res://resources/mechs/Pegasus.tres", "weapons": ["res://scenes/weapons/LaserCannonLight.tscn"]}]
	var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arena)
	for i in 2:
		await get_tree().process_frame
	if arena.get("_start_pick_open"):
		arena.get("hud").squad_slot_selected.emit(0)
		arena.get("hud").spawn_selected.emit(0)
	for i in 10:
		await get_tree().physics_frame
	var deck := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 2, 200)
	cs.shape = box
	deck.add_child(cs)
	arena.add_child(deck)
	deck.global_position = Vector3(0, DECK_Y - 1.0, 0)
	var bot_m: Node3D = arena.get("_team_mechs")[1][0]
	var t: Node3D = arena.get("_team_mechs")[0][0]
	t.set("invincible", true)
	bot_m.global_position = Vector3(0, DECK_Y + 0.5, 0)
	t.global_position = Vector3(0, DECK_Y + 0.5, -30)
	var ai: Node = bot_m.get("_input_source")
	ai.set("difficulty", 3)
	for i in 20:
		await get_tree().physics_frame
	var w: Node = bot_m.get_weapons()[0]
	var mz = w.get("muzzle_local")
	var muzzle_y: float = ((w as Node3D).to_global(mz) if mz is Vector3 else (w as Node3D).global_position).y - DECK_Y
	# the wall top: between the gun's line and the eye line at the wall (5 m in front of the bot)
	var aim_p: Vector3 = t.global_position + Vector3(0, 1.0, 0)
	var eye_y: float = 2.0 + (1.5 - 2.0) * (5.0 / 30.0)
	var gun_y: float = muzzle_y + (1.0 - muzzle_y) * (5.0 / 30.0)
	if eye_y - gun_y < 0.15:
		_fail("setup: gun line %.2f m vs eye line %.2f m at the wall -- no gap to test in" % [gun_y, eye_y])
		return
	var top: float = (eye_y + gun_y) * 0.5
	var wall := StaticBody3D.new()
	var wcs := CollisionShape3D.new()
	var wbox := BoxShape3D.new()
	wbox.size = Vector3(6, top, 0.5)
	wcs.shape = wbox
	wall.add_child(wcs)
	arena.add_child(wall)
	wall.global_position = Vector3(0, DECK_Y + top * 0.5, -5)
	await get_tree().physics_frame
	var bad: Array = []
	ai.set("_target", t)
	ai.set("_muzzle_n", 0)
	if not ai.call("_los_to", bot_m, t):
		bad.append("setup: the eye line doesn't clear the wall (top %.2f, eye %.2f, gun %.2f)" % [top, eye_y, gun_y])
	if ai.call("_shot_worth_taking", bot_m, w, aim_p):
		bad.append("a shot taken with the gun's line into the wall (top %.2f m, gun line %.2f m there)" % [top, gun_y])
	wall.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame
	ai.set("_muzzle_n", 0)
	var aimed: Vector3 = (bot_m as Node3D).global_position  # aim straight: point the torso at the target
	(bot_m.get("torso") as Node3D).look_at(Vector3(t.global_position.x, (bot_m.get("torso") as Node3D).global_position.y, t.global_position.z))
	ai.call("_muzzle_line_clear", bot_m, w, aim_p)
	if not ai.get("_muzzle_clear"):
		bad.append("the gun's line still reads blocked with the wall gone")
	if not bad.is_empty():
		_fail("; ".join(bad))
		return
	print("[probe] bot_muzzle_los done (gun %.2f m up, wall top %.2f m between it and the eye line)" % [muzzle_y, top])
	get_tree().quit(0)
