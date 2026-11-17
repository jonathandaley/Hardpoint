extends Node
# T445 probe (user 2026-11-17: yes to Giza "a sun disc and a gradient ... lighter fog"): Giza's fog
# no longer paints the whole sky (fog_sky_affect < 1: a gradient shows) and is lighter than the
# old 0.0025, and its sun is warmed; none of it carries into the next match (City afterwards has
# the arena's own sun colour, sky and full-sky defaults). Giza uses no Sky of its own (T346 leak).

func _fail(msg: String) -> void:
	push_error("[probe] map_skies: " + msg)

func _arena(map: String) -> Node:
	Game.mp_active_match["roster"] = []
	Game.loadout["team_size"] = 1
	Game.loadout["map_def"] = load("res://resources/maps/%s.tres" % map)
	var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arena)
	for i in 2:
		await get_tree().process_frame
	return arena

func _ready() -> void:
	var bad := 0
	var g: Node = await _arena("Giza")
	var env := (g.get_node("WorldEnvironment") as WorldEnvironment).environment
	var sun := g.get_node("Sun") as DirectionalLight3D
	if env.fog_sky_affect > 0.8 or env.fog_density >= 0.0025:
		bad += 1
		_fail("Giza: fog still paints the sky flat (sky affect %.2f, density %.4f)" % [env.fog_sky_affect, env.fog_density])
	if sun.light_color.b >= sun.light_color.r - 0.1:
		bad += 1
		_fail("Giza: sun not warmed (%s)" % sun.light_color)
	var giza_sky := env.sky
	g.queue_free()
	for i in 3:
		await get_tree().process_frame
	var c: Node = await _arena("City")
	var cenv := (c.get_node("WorldEnvironment") as WorldEnvironment).environment
	var csun := c.get_node("Sun") as DirectionalLight3D
	if not csun.light_color.is_equal_approx(Color(0.90, 0.94, 1.0, 1)):
		bad += 1
		_fail("City after Giza: sun %s, want Arena.tscn's (0.90, 0.94, 1.0)" % csun.light_color)
	var top := (cenv.sky.sky_material as ProceduralSkyMaterial).sky_top_color
	if cenv.sky != giza_sky or not top.is_equal_approx(Color(0.08, 0.10, 0.20, 1)):
		bad += 1
		_fail("City after Giza: sky changed (top %s)" % top)
	c.queue_free()
	for i in 3:
		await get_tree().process_frame
	print("[probe] map_skies: %s" % ("PASS" if bad == 0 else "FAIL %d" % bad))
	get_tree().quit(1 if bad else 0)
