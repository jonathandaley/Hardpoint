extends Node
# T262 probe (HUMAN_FOUND_ISSUES 2026-11-05: "Machine gun barrel should start glowing as
# ramp-up increases, red-hot at max speed"): holding the MG trigger, its BarrelGlow shows
# and brightens with the fire rate, red-hot at max; it fades out after release. Clients
# ramp from the replicated loop on/off (_remote_firing).
# T378 (HUMAN_FOUND 2026-11-09): holding the trigger while reloading doesn't heat the barrel, and a
# shooter that just stops (a bot: no trigger release) still tells clients the burst ended.

const SlotDef := preload("res://scripts/WeaponSlotDef.gd")

func _fail(msg: String) -> void:
	push_error("[probe] mg_glow FAIL: " + msg)
	get_tree().quit(1)

class AimSrc extends "res://scripts/InputSource.gd":
	var aim := Vector2.ZERO
	var firing := false
	func get_abs_aim():
		return aim
	func is_firing_primary() -> bool:
		return firing

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Game.mp_active_match["roster"] = []
	Game.loadout["team_size"] = 1
	var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arena)
	for i in 2:
		await get_tree().process_frame
	get_tree().current_scene = arena  # shots go under the current scene
	if arena.get("_start_pick_open"):
		arena.get("hud").squad_slot_selected.emit(0)
		arena.get("hud").spawn_selected.emit(0)
	for i in 10:
		await get_tree().physics_frame
	for t in 2:
		for m in arena.get("_team_mechs")[t]:
			m.invincible = true
			if m != arena.get("player_mech"):
				m.process_mode = Node.PROCESS_MODE_DISABLED
	var me: CharacterBody3D = arena.get("player_mech")
	var src := AimSrc.new()
	me.add_child(src)
	me.set_input_source(src)
	src.aim = Vector2(0.0, 0.4)  # pitched up: open sky above the arena
	var scene: PackedScene = load("res://scenes/weapons/MachineGunLight.tscn")
	var slot := SlotDef.new()
	slot.slot_size = 0
	slot.position = Vector3(0, 2.0, 0)
	slot.weapon_scene = scene
	me.configure_weapons([slot])
	for i in 5:
		await get_tree().physics_frame
	var w: Node = me.get_weapons()[0]
	src.firing = true
	var mid_r := -1.0
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 4000 and float(w.call("get_heat")) < 0.99:
		await get_tree().process_frame
		var g: MeshInstance3D = w.get_node_or_null("BarrelGlow")
		if mid_r < 0.0 and g != null and float(w.call("get_heat")) > 0.4 and float(w.call("get_heat")) < 0.6:
			mid_r = (g.mesh.surface_get_material(0) as StandardMaterial3D).albedo_color.r
	await get_tree().process_frame
	var glow: MeshInstance3D = w.get_node_or_null("BarrelGlow")
	if glow == null or not glow.visible:
		_fail("no visible BarrelGlow at heat %.2f" % float(w.call("get_heat")))
		return
	var hot: Color = (glow.mesh.surface_get_material(0) as StandardMaterial3D).albedo_color
	if float(w.call("get_heat")) < 0.99 or hot.r < 0.9:
		_fail("not red-hot at max rate: heat %.2f colour %s" % [float(w.call("get_heat")), hot])
		return
	if mid_r < 0.0 or mid_r >= hot.r * 0.8:
		_fail("glow does not build with the ramp (mid %.2f vs max %.2f)" % [mid_r, hot.r])
		return
	src.firing = false
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 2000 and glow.visible:
		await get_tree().process_frame
	if glow.visible:
		_fail("barrel still glowing 2 s after release (heat %.2f)" % float(w.call("get_heat")))
		return
	# a bot-like stop: firing again, then the input just ends with no release call
	src.firing = true
	for i in 30:
		await get_tree().physics_frame
	if not w.get("_loop_on_remote"):
		_fail("the loop never went 'on' for clients while firing")
		return
	me.set("_was_firing_primary", false)  # Mech won't call on_fire_release
	src.firing = false
	for i in 5:
		await get_tree().physics_frame
	if w.get("_loop_on_remote"):
		_fail("a shooter that stopped without a release still tells clients it's firing")
		return
	# holding the trigger on an empty magazine (reloading) doesn't heat the barrel
	for i in 60:
		await get_tree().physics_frame
	w.set("ammo", 0)
	src.firing = true
	for i in 60:
		await get_tree().physics_frame
	var reload_heat := float(w.call("get_heat"))
	src.firing = false
	if reload_heat > 0.05:
		_fail("barrel heats to %.2f while reloading (trigger held, no shots)" % reload_heat)
		return
	if not (load("res://scripts/MachineGun.gd") as Script).source_code.contains("_remote_firing = on"):
		_fail("clients do not ramp from the loop on/off RPC")
		return
	print("[probe] mg_glow done (mid r %.2f, hot %s)" % [mid_r, hot])
	get_tree().quit(0)
