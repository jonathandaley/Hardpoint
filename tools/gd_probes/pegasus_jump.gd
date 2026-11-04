extends Node
# T240 probe (HUMAN_FOUND_ISSUES 2026-11-04: "Pegasus jump should go straight up if he's
# standing still"): a standing jump lands within STILL_M of where it took off; a jump while
# walking forward still carries >= MOVE_M along.

const STILL_M := 0.3
const MOVE_M := 4.0

class Src extends "res://scripts/InputSource.gd":
	var dir := Vector2.ZERO
	func get_move_direction() -> Vector2:
		return dir

func _fail(msg: String) -> void:
	push_error("[probe] pegasus_jump: " + msg)

func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)

func _ready() -> void:
	Game.mp_active_match["roster"] = []
	Game.loadout["team_size"] = 1
	Game.loadout["squad"] = ["res://resources/mechs/Pegasus.tres"]
	var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arena)
	for i in 2:
		await get_tree().process_frame
	if arena.get("_start_pick_open"):
		arena.get("hud").squad_slot_selected.emit(0)
		arena.get("hud").spawn_selected.emit(0)
	for i in 60:
		await get_tree().physics_frame
	var m: CharacterBody3D = arena.get("player_mech")
	m.invincible = true
	var src := Src.new()
	m.add_child(src)
	m.set_input_source(src)
	var jump: Resource = null
	for a in m.get("_abilities"):
		if a.effect_key == "jump_heal":
			jump = a
	var got := []
	for case in [[Vector2.ZERO, "standing"], [Vector2(0, -1), "walking"]]:
		src.dir = case[0]
		for i in 40:  # settle / get up to walking speed
			await get_tree().physics_frame
		var p0 := _flat(m.global_position)
		m.call("_activate_ability", jump)
		var left := false
		for i in 240:
			await get_tree().physics_frame
			if not m.is_on_floor():
				left = true
			elif left:
				break
		var d := _flat(m.global_position).distance_to(p0)
		got.append("%s %.2f m" % [case[1], d])
		if case[0] == Vector2.ZERO and d > STILL_M:
			_fail("a standing jump landed %.2f m from its take-off (want <= %.1f: straight up)" % [d, STILL_M])
		if case[0] != Vector2.ZERO and d < MOVE_M:
			_fail("a walking jump carried only %.2f m (want >= %.1f)" % [d, MOVE_M])
		src.dir = Vector2.ZERO
		for i in 30:
			await get_tree().physics_frame
	print("[probe] pegasus_jump done (%s)" % ", ".join(got))
	get_tree().quit(0)
