extends Node
# T485 probe (HUMAN_FOUND 2026-11-18: "Caldera looks great, but the center bridge has a flicker that looks
# like two materials at the same height. Falling into the lava should kill you."): a mech dropped into
# the lava dies; one on the causeway lives; the island and causeway tops sit off the terrain (y 0) and
# off each other (no two surfaces at one height).

const InputSource := preload("res://scripts/InputSource.gd")

func _fail(msg: String) -> void:
	push_error("[probe] caldera_lava FAIL: " + msg)
	get_tree().quit(1)

func _down(at: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 20.0, at + Vector3.DOWN * 20.0)
	var hit := get_viewport().get_world_3d().direct_space_state.intersect_ray(q)
	return float(hit.position.y) if not hit.is_empty() else -999.0

func _ready() -> void:
	Game.mp_active_match["roster"] = []
	Game.loadout["team_size"] = 2
	Game.loadout["map_def"] = load("res://resources/maps/Caldera.tres")
	var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arena)
	for i in 2:
		await get_tree().process_frame
	if arena.get("_start_pick_open"):
		arena.get("hud").squad_slot_selected.emit(0)
		arena.get("hud").spawn_selected.emit(0)
	for i in 10:
		await get_tree().physics_frame
	var bad: Array = []
	var island := _down(Vector3(0, 0, 0))
	var cause := _down(Vector3(25, 0, 0))
	if absf(island) < 0.02 or absf(cause) < 0.02 or absf(island - cause) < 0.02:
		bad.append("tops at island %.3f / causeway %.3f: coplanar with the terrain (0) or each other" % [island, cause])
	var foes: Array = arena.get("_team_mechs")[1]
	var lava: Node3D = foes[0]
	var safe: Node3D = foes[1]
	for m in [lava, safe]:
		var src: Node = InputSource.new()
		add_child(src)
		m.call("set_input_source", src)
		m.set("invincible", false)
	lava.global_position = Vector3(0, -2.5, 27)  # r 27: over the lava bed, off the causeways
	safe.global_position = Vector3(25, cause + 0.6, 0)
	for i in 30:
		await get_tree().physics_frame
	if not lava.get("is_dead"):
		bad.append("a mech in the lava (y %.1f) is alive at %.0f HP" % [lava.global_position.y, float(lava.get("health"))])
	if safe.get("is_dead"):
		bad.append("a mech on the causeway died")
	if not bad.is_empty():
		_fail("; ".join(bad))
		return
	print("[probe] caldera_lava done (island top %.2f, causeway %.2f)" % [island, cause])
	get_tree().quit(0)
