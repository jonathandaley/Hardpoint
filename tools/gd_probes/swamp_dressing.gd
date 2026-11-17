extends Node
# T446 probe (user 2026-11-17: yes to Swamp's dressing, "keep the moody fog"): Swamp has reeds at
# the water's edge, lily pads on open water, moss on its dead trees and an AMBIENT EFFECTS setting for
# the fireflies -- and the fog is exactly what it was (colour, density) and nothing new collides
# (the colliders are the same count as before).
const FOG := Color("#4b5440")
const FOG_DENSITY := 0.012
const BODIES_BEFORE := 132  # Swamp at f451454 (before T446)

func _fail(msg: String) -> void:
	push_error("[probe] swamp_dressing: " + msg)

func _ready() -> void:
	Game.mp_active_match["roster"] = []
	Game.loadout["team_size"] = 1
	Game.loadout["map_def"] = load("res://resources/maps/Swamp.tres")
	var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arena)
	for i in 2:
		await get_tree().process_frame
	var map: Node = arena.get("_map")
	var bad := 0
	var reeds := 0
	var pads := 0
	var moss := 0
	var bodies := 0
	for n in map.find_children("*", "", true, false):
		if n is CollisionShape3D:
			bodies += 1
		if not n is MeshInstance3D:
			continue
		var mi := n as MeshInstance3D
		if mi.mesh is BoxMesh and (mi.mesh as BoxMesh).size.x < 0.1 and (mi.mesh as BoxMesh).size.y > 1.0:
			reeds += 1
		elif mi.mesh is CylinderMesh and (mi.mesh as CylinderMesh).height < 0.05:
			pads += 1
		elif mi.mesh is BoxMesh and (mi.mesh as BoxMesh).size.z < 0.07 and mi.get_parent() is StaticBody3D:
			moss += 1
	var env := (arena.get_node("WorldEnvironment") as WorldEnvironment).environment
	if not env.fog_light_color.is_equal_approx(FOG) or not is_equal_approx(env.fog_density, FOG_DENSITY) or not env.fog_enabled:
		bad += 1
		_fail("the fog changed: %s / %.4f (user: keep the moody fog)" % [env.fog_light_color, env.fog_density])
	if reeds < 200 or pads < 30 or moss < 100:
		bad += 1
		_fail("dressing thin: %d reeds, %d lily pads, %d moss strands" % [reeds, pads, moss])
	if not Game.settings.has("map_effects"):
		bad += 1
		_fail("no map_effects setting (the fireflies' off-switch)")
	if bodies != BODIES_BEFORE:
		bad += 1
		_fail("colliders changed: %d, was %d" % [bodies, BODIES_BEFORE])
	print("[probe] swamp_dressing: %d reeds, %d pads, %d moss, %d colliders: %s" % [reeds, pads, moss, bodies, "PASS" if bad == 0 else "FAIL %d" % bad])
	get_tree().quit(1 if bad else 0)
