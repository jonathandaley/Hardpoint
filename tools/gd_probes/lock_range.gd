extends Node
# T334 probe (HUMAN_FOUND 2026-11-05: "All lock-on weapons should not lock on until the weapon is
# within range. Square reticle should still be visible at any range."): an enemy in the crosshair
# beyond the lock weapon's range gets the red box (lock_eligible) but no lock, however long we
# hold on it; brought within range it locks.

const SlotDef := preload("res://scripts/WeaponSlotDef.gd")

class Src extends "res://scripts/InputSource.gd":  # holds the aim still
	var aim := Vector2.ZERO
	func get_abs_aim():
		return aim

func _fail(msg: String) -> void:
	push_error("[probe] lock_range FAIL: " + msg)
	get_tree().quit(1)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Game.mp_active_match["roster"] = []
	Game.loadout["team_size"] = 1
	Game.loadout["sp_bots"] = [0, 1]
	Game.loadout["mode"] = "beacons"
	var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arena)
	for i in 2:
		await get_tree().process_frame
	if arena.get("_start_pick_open"):
		arena.get("hud").squad_slot_selected.emit(0)
		arena.get("hud").spawn_selected.emit(0)
	for i in 10:
		await get_tree().physics_frame
	var me: CharacterBody3D = arena.get("player_mech")
	var enemy: Node3D = arena.get("_team_mechs")[1 - int(me.get("team"))][0]
	enemy.disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
	enemy.process_mode = Node.PROCESS_MODE_DISABLED
	me.invincible = true
	var src := Src.new()
	me.add_child(src)
	me.set_input_source(src)
	src.aim = Vector2((me.get("torso") as Node3D).rotation.y, 0.0)
	var slot := SlotDef.new()
	slot.slot_size = 0
	slot.position = Vector3(0, 2.0, 0)
	slot.weapon_scene = load("res://scenes/weapons/ArcWeaponLight.tscn")
	me.configure_weapons([slot])
	await get_tree().physics_frame
	var rng: float = me.get_weapons()[0].get("range")
	var cam: Camera3D = me.get("camera")
	var got := {}
	for d in [rng + 25.0, rng - 25.0]:
		var boxed := false
		var locked := false
		for i in int(me.get("_lock_time") * 60.0) + 60:
			var fwd: Vector3 = -cam.global_transform.basis.z
			var p: Vector3 = me.global_position + Vector3(fwd.x, 0.0, fwd.z).normalized() * d
			var at: Vector3 = cam.global_position + fwd * cam.global_position.distance_to(p)
			enemy.global_position = at - (enemy.call("center_mass") - enemy.global_position)
			await get_tree().physics_frame
			boxed = boxed or bool(me.get("lock_eligible"))
			locked = locked or me.get("locked_target") == enemy
		got[d] = [boxed, locked]
	var far: Array = got[rng + 25.0]
	var near: Array = got[rng - 25.0]
	if not far[0]:
		_fail("no red box on an enemy %.0f m off (beyond range %.0f)" % [rng + 25.0, rng])
		return
	if far[1]:
		_fail("locked an enemy %.0f m off, beyond the weapon's %.0f m" % [rng + 25.0, rng])
		return
	if not near[1]:
		_fail("no lock on an enemy %.0f m off, within range %.0f" % [rng - 25.0, rng])
		return
	print("[probe] lock_range done (range %.0f: box + no lock at %.0f m, lock at %.0f m)" % [rng, rng + 25.0, rng - 25.0])
	get_tree().quit(0)
