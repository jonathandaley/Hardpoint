extends Node
# T256 + T274 probe (HUMAN_FOUND_ISSUES 2026-11-05: "rangefinder in hud"; user: "only show
# distance to an enemy that's in the targeting reticle. So no range shown looking at a wall"):
# with an enemy straight ahead 25 m from our mech the HUD reads ~25 m beside the crosshair;
# with that enemy moved far off the crosshair (nothing in the reticle) it shows nothing.

const AHEAD := 25.0

class AimSrc extends "res://scripts/InputSource.gd":
	var aim := Vector2.ZERO
	func get_abs_aim():
		return aim
	func is_human_input() -> bool:  # the soft-lock (reticle) only updates for a human pilot
		return true

func _fail(msg: String) -> void:
	push_error("[probe] rangefinder: " + msg)

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
	for t in 2:
		for m in arena.get("_team_mechs")[t]:
			m.invincible = true
			if m != me:  # frozen but still solid (PROCESS_MODE_DISABLED would drop it from physics)
				m.set_physics_process(false)
				m.set_process(false)
	var src := AimSrc.new()
	me.add_child(src)
	me.set_input_source(src)
	src.aim = Vector2((me.get("torso") as Node3D).rotation.y, 0.0)  # level crosshair
	for i in 30:
		await get_tree().physics_frame
	var cam: Camera3D = me.get("camera")
	var fwd := -cam.global_transform.basis.z
	# put the enemy's body on the crosshair ray, AHEAD m (flat) from our mech
	var flat := Vector3(fwd.x, 0, fwd.z).normalized()
	var at := me.global_position + flat * AHEAD
	var along := (at - cam.global_position).dot(flat) / maxf(0.01, Vector3(fwd.x, 0, fwd.z).length())
	enemy.global_position = Vector3(at.x, (cam.global_position + fwd * along).y - 1.2, at.z)
	for i in 10:
		await get_tree().process_frame
	var lbl := arena.get("hud").find_child("Rangefinder", true, false) as Label
	if lbl == null or not lbl.visible:
		_fail("no rangefinder on the HUD")
	else:
		var d := lbl.text.to_float()
		if absf(d - AHEAD) > 4.0:
			_fail("rangefinder reads '%s' with an enemy %.0f m ahead" % [lbl.text, AHEAD])
		var read := lbl.text
		enemy.global_position = me.global_position + Vector3(-flat.z, 0, flat.x) * 40.0  # 90 deg off the crosshair
		for i in 10:
			await get_tree().physics_frame
		if lbl.visible:
			_fail("rangefinder still shows '%s' with no enemy in the reticle" % lbl.text)
		print("[probe] rangefinder done (%s; hidden with no enemy in the reticle)" % read)
	get_tree().quit(0)
