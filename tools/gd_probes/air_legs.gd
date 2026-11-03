extends Node
# T174 probe (HUMAN_FOUND_ISSUES 'Pegasus's legs move really fast while airborne'): a
# jump_heal launches at 3.75x walk speed, and the walk cycle ran off horizontal speed,
# so the legs spun ~6 cycles/s mid-air. Airborne legs must hold still in a tuck, and
# walk again after landing.

const BipedLegs := preload("res://scripts/BipedLegs.gd")

func _fail(msg: String) -> void:
	push_error("[probe] air_legs: " + msg)

func _ready() -> void:
	var peg: Resource = load("res://resources/mechs/Pegasus.tres")
	Game.mp_active_match["roster"] = []  # Arena sets up SP from the loadout (T184)
	Game.loadout["squad"] = [peg.resource_path]
	Game.loadout["team_size"] = 1
	var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arena)
	for i in 2:
		await get_tree().process_frame
	if arena.get("_start_pick_open"):  # T187: keep slot 0, as a player would
		arena.get("hud").squad_slot_selected.emit(0)
	for i in 90:
		await get_tree().physics_frame
	var m: CharacterBody3D = arena.get("player_mech")
	var legs: Node = m.get_node("Legs")
	m.invincible = true
	m.call("_activate_ability", m.get("_abilities")[0])  # jump_heal
	var air := 0
	var phase_at := 0.0
	var spin := 0.0
	var tucked := false
	for i in 300:
		await get_tree().physics_frame
		if m.is_on_floor():
			if air > 0:
				break
			continue
		air += 1
		if air > 15:  # 0.25 s up: past the stair-drop grace, tuck under way
			spin += absf(angle_difference(phase_at, legs.get("_phase")))
		phase_at = legs.get("_phase")
		if air == 45:
			tucked = legs.get_node("LeftHip").rotation.x > BipedLegs.REST_HIP + 0.3 \
				and legs.get_node("RightHip").rotation.x > BipedLegs.REST_HIP + 0.15
	if air < 45:
		_fail("Pegasus jump never left the floor long enough (%d ticks)" % air)
	if spin > 0.05:
		_fail("walk cycle ran %.2f rad while airborne" % spin)
	if not tucked:
		_fail("legs not tucked 0.75 s into the jump")
	for i in 60:  # back on the ground for 1 s: tuck released
		await get_tree().physics_frame
	var blend = legs.get("_air")
	if blend == null or float(blend) > 0.01:
		_fail("legs still tucked 1 s after landing (air blend %s)" % blend)
	print("[probe] air_legs done (airborne %d ticks, spin %.3f rad)" % [air, spin])
	get_tree().quit(0)
