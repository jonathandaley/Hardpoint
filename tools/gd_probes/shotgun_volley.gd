extends Node
# T330 probe (user 2026-11-05: "Game lagged when shot at close range with three heavy shotguns at
# once. Too many particles? Want to make sure that doesn't happen"): three heavy shotguns fired
# point-blank into one mech spawn a bounded number of nodes -- the 75 pellets, plus one hit cue
# (impact sound + spark burst) per blast and one damage sound, not one per pellet, and smoke
# trails on one pellet in five.

const SlotDef := preload("res://scripts/WeaponSlotDef.gd")
const MAX_EXTRA := 200  # nodes beyond the pellets themselves (old: 657 -- sparks, sounds, smoke)

class Src extends "res://scripts/InputSource.gd":  # holds the aim still
	var aim := Vector2.ZERO
	func get_abs_aim():
		return aim

var _added := 0
var _pellets := 0

func _fail(msg: String) -> void:
	push_error("[probe] shotgun_volley FAIL: " + msg)
	get_tree().quit(1)

func _on_added(n: Node) -> void:
	if n is Projectile:
		_pellets += 1
	elif not (n.get_parent() is Projectile):  # a pellet's own mesh is part of the pellet
		_added += 1

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
	enemy.set("invincible", false)
	me.invincible = true
	var src := Src.new()
	me.add_child(src)
	me.set_input_source(src)
	src.aim = Vector2((me.get("torso") as Node3D).rotation.y, 0.0)
	var slots: Array = []
	for x in [-0.8, 0.0, 0.8]:
		var slot := SlotDef.new()
		slot.slot_size = 1
		slot.position = Vector3(x, 2.0, 0)
		slot.weapon_scene = load("res://scenes/weapons/ShotgunHeavy.tscn")
		slots.append(slot)
	me.configure_weapons(slots)
	for i in 3:
		await get_tree().physics_frame
	var cam: Camera3D = me.get("camera")
	var fwd: Vector3 = -cam.global_transform.basis.z
	var p: Vector3 = me.global_position + Vector3(fwd.x, 0.0, fwd.z).normalized() * 6.0
	enemy.global_position = cam.global_position + fwd * cam.global_position.distance_to(p) \
		- (enemy.call("center_mass") - enemy.global_position)
	enemy.set("max_health", 100000.0)
	enemy.set("health", 100000.0)  # survives the volley: every pellet lands on a live mech
	for i in 2:
		await get_tree().physics_frame
	var hp0: float = enemy.get("health")
	get_tree().node_added.connect(_on_added)
	for w in me.get_weapons():
		w.fire()
	for i in 30:
		await get_tree().physics_frame
	get_tree().node_added.disconnect(_on_added)
	var dealt: float = hp0 - float(enemy.get("health"))
	if dealt <= 0.0:
		_fail("setup: the volley didn't hit (pellets %d)" % _pellets)
		return
	var extra := _added
	if extra > MAX_EXTRA:
		_fail("a 3-shotgun point-blank volley spawned %d nodes besides its %d pellets (max %d)" % [extra, _pellets, MAX_EXTRA])
		return
	print("[probe] shotgun_volley done (%d pellets, %d other nodes, %.0f damage)" % [_pellets, extra, dealt])
	get_tree().quit(0)
