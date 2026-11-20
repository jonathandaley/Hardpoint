extends Node3D
# T523 probe (user 2026-11-19: "Graphics upgrade, option in menu: better sparks, bullets, smoke, explosions,
# etc. Still not super heavy, but make it sparkle."): FANCY EFFECTS off = the plain pieces exactly (6
# sparks, no smoke, 1 tracer beam); on = more (10 arcing sparks + 2 smoke puffs, a tracer with a core, a
# smoke column on a death) -- all in the FxPool's three MultiMeshes.

func _fail(msg: String) -> void:
	push_error("[probe] fx_fancy FAIL: " + msg)
	get_tree().quit(1)

func _ready() -> void:
	for i in 2:
		await get_tree().process_frame
	var fx: Node = VFX._fx()
	if fx == null:
		_fail("no FxPool")
		return
	var bad: Array = []
	var p := Vector3(0, 1, 0)
	Game.settings["fancy_effects"] = false
	var s0: int = fx.spheres().size()
	VFX.hit_sparks(p)
	if fx.spheres().size() - s0 != 6 or fx.puffs() != 0:
		bad.append("plain hit: %d sparks, %d puffs (want 6, 0)" % [fx.spheres().size() - s0, fx.puffs()])
	var b0: int = fx.beams().size()
	VFX.tracer(p, p + Vector3(10, 0, 0))
	if fx.beams().size() - b0 != 1:
		bad.append("plain tracer: %d beams (want 1)" % (fx.beams().size() - b0))
	Game.settings["fancy_effects"] = true
	s0 = fx.spheres().size()
	VFX.hit_sparks(p)
	if fx.spheres().size() - s0 != 10 or fx.puffs() != 2:
		bad.append("fancy hit: %d sparks, %d puffs (want 10, 2)" % [fx.spheres().size() - s0, fx.puffs()])
	b0 = fx.beams().size()
	VFX.tracer(p, p + Vector3(10, 0, 0))
	if fx.beams().size() - b0 != 2:
		bad.append("fancy tracer: %d beams (want 2: the beam and its core)" % (fx.beams().size() - b0))
	var pf0: int = fx.puffs()
	VFX.death_explosion(p)
	if fx.puffs() - pf0 != 8:
		bad.append("fancy death: %d smoke puffs (want 8)" % (fx.puffs() - pf0))
	var mm := fx.find_children("*", "MultiMeshInstance3D", false, false)
	if mm.size() != 3:
		bad.append("%d MultiMeshes in the pool (want 3: spheres, boxes, smoke)" % mm.size())
	Game.settings["fancy_effects"] = false
	if not bad.is_empty():
		_fail("; ".join(bad))
		return
	print("[probe] fx_fancy done")
	get_tree().quit(0)
