extends Node
# T197 probe (HUMAN_FOUND_ISSUES: "Pegasus doesn't jump correctly some of the time, it
# might be when it's on a slope"): a jump launched with rising ground / a step just
# ahead must still fly. The step-up check ran after the jump in the same tick, saw the
# rise ahead as a step and zeroed velocity.y -- the jump became a 0.37 m step.

func _fail(msg: String) -> void:
	push_error("[probe] jump_slope: " + msg)

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
	var fwd: Vector3 = -(m.get("torso") as Node3D).global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	# a 0.3 m ledge just ahead: what the shin ray sees on an uphill slope or at a step
	var ledge := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.0, 0.3, 1.0)
	col.shape = box
	ledge.add_child(col)
	arena.add_child(ledge)
	ledge.global_position = m.global_position + fwd * 1.0 + Vector3.UP * 0.15
	ledge.look_at(ledge.global_position + fwd, Vector3.UP)
	for i in 3:
		await get_tree().physics_frame
	var jump: Resource = null
	for a in m.get("_abilities"):
		if a.effect_key == "jump_heal":
			jump = a
	if jump == null:
		_fail("Pegasus has no jump_heal ability")
		get_tree().quit(0)
		return
	var y0 := m.global_position.y
	m.call("_activate_ability", jump)
	var peak := 0.0
	for i in 60:
		await get_tree().physics_frame
		peak = maxf(peak, m.global_position.y - y0)
	if peak < 3.0:
		_fail("jump with a rise ahead peaked at %.2f m (a step-up ate it)" % peak)
	print("[probe] jump_slope done (peak %.2f m)" % peak)
	get_tree().quit(0)
