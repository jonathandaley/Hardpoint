extends Node

# --- public API ---

# T525: every piece below is an instance in the arena's FxPool (two MultiMeshes: 2 draw calls in all)
# -- same shapes, sizes, colours and timings as the node-per-piece effects it replaced.
var _fx_pool: Node = null

## T523 (user 2026-11-19: "Graphics upgrade, option in menu: better sparks, bullets, smoke, explosions, etc.
## Still not super heavy, but make it sparkle. Keep the chunky pixel look, just make it fancier."): GRAPHICS >
## FANCY EFFECTS (off by default: the potato). Same low-poly pieces, more of them: arcing sparks with a hot
## core, smoke puffs (one see-through MultiMesh more: +1 draw call), brighter tracers, a smoke column.
func fancy() -> bool:
	return bool(Game.settings.get("fancy_effects", false))

func _fx() -> Node:
	var scene := get_tree().current_scene
	if scene == null or Game.dedicated:
		return null
	if not is_instance_valid(_fx_pool) or _fx_pool.get_parent() != scene:
		_fx_pool = load("res://scripts/FxPool.gd").new()
		scene.add_child(_fx_pool)
	return _fx_pool

# T317: radius (m) -- WeaponBase sizes it to the barrel; 0.26 was the old one-size flash.
func muzzle_flash(pos: Vector3, color: Color = Color(1.0, 0.80, 0.30), broadcast: bool = false, radius: float = 0.26) -> void:
	if broadcast and multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_rpc_muzzle_flash.rpc(pos, color, radius)
	var fx := _fx()
	if fx != null:
		fx.sphere(pos, pos, radius, 0.0, color, 6.0, 6.0, 0.12)  # shrinks away
		if fancy():  # T523: a few hot flecks thrown off the flash
			for i in 3:
				var d := Vector3(randf_range(-1.0, 1.0), randf_range(-0.2, 0.6), randf_range(-1.0, 1.0)).normalized()  # cosmetic
				fx.sphere(pos, pos + d * radius * 3.0, radius * 0.18, 0.0, color.lightened(0.5), 0.0, 0.0, 0.1, 0.0, 0.08)

@rpc("authority", "unreliable")
func _rpc_muzzle_flash(pos: Vector3, color: Color, radius: float) -> void:
	if multiplayer.is_server():
		return
	muzzle_flash(pos, color, false, radius)

# T260: width (m) for thick beams; the beam holds, then fades out (alpha) and thins.
func tracer(from: Vector3, to: Vector3, color: Color = Color(0.75, 0.5, 1.0), duration: float = 0.35, broadcast: bool = false, width: float = 0.04) -> void:
	if from.distance_to(to) < 0.01:
		return
	if broadcast and multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_rpc_tracer.rpc(from, to, color, duration, width)
	var fx := _fx()
	if fx != null:
		if fancy():  # T523: a touch wider, with a bright core
			fx.beam(from, to, width * 1.4, width * 0.4, color, 4.0, duration)
			fx.beam(from, to, width * 0.45, width * 0.1, color.lightened(0.7), 4.0, duration * 0.6)
		else:
			fx.beam(from, to, width, width * 0.3, color, 4.0, duration)

@rpc("authority", "unreliable")
func _rpc_tracer(from: Vector3, to: Vector3, color: Color, duration: float, width: float) -> void:
	if multiplayer.is_server():
		return
	tracer(from, to, color, duration, false, width)

func hit_sparks(pos: Vector3, color: Color = Color(1.0, 0.55, 0.15), broadcast: bool = false) -> void:
	if broadcast and multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_rpc_hit_sparks.rpc(pos, color)
	var fx := _fx()
	if fx == null:
		return
	var rich := fancy()
	for i in (10 if rich else 6):
		var dir := Vector3(randf_range(-1.0, 1.0), randf_range(0.2, 1.0), randf_range(-1.0, 1.0)).normalized()  # cosmetic
		var c := color.lightened(0.6) if rich and i % 3 == 0 else color  # T523: a hot core among them
		fx.sphere(pos, pos + dir * randf_range(0.3, 0.8) * (1.4 if rich else 1.0), 0.055, 0.0, c, 3.5, 3.5,
			randf_range(0.14, 0.24) * (1.4 if rich else 1.0), 0.0, 0.35 if rich else 0.0)
	if rich:  # T523: a little smoke where it hit
		for i in 2:
			var up := pos + Vector3(randf_range(-0.2, 0.2), randf_range(0.4, 0.8), randf_range(-0.2, 0.2))
			fx.puff(pos, up, 0.12, 0.45, Color(0.35, 0.35, 0.36), 0.55, 0.0, randf_range(0.45, 0.7))

@rpc("authority", "unreliable")
func _rpc_hit_sparks(pos: Vector3, color: Color) -> void:
	if multiplayer.is_server():
		return
	hit_sparks(pos, color)

func death_explosion(pos: Vector3, broadcast: bool = false) -> void:
	if broadcast and multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_rpc_death_explosion.rpc(pos)
	var fx := _fx()
	if fx == null:
		return
	# Instant white-orange core flash - brief, not dominant: grows to 2.8x in 0.05 s, then fades in 0.09 s
	var core := Color(1.0, 0.95, 0.82)
	fx.sphere(pos, pos, 0.0, 0.35 * 2.8, core, 14.0, 14.0, 0.05)
	fx.sphere(pos, pos, 0.35 * 2.8, 0.35 * 2.8, core, 14.0, 0.0, 0.09, 0.05)
	# 12 medium chunks replace the solid sphere - fragmented from frame 1
	for _i in 12:
		var hot := randf()  # cosmetic
		var col := Color(1.0, lerpf(0.30, 0.72, hot), lerpf(0.0, 0.12, hot))
		var emit := randf_range(4.5, 7.5)
		var r := randf_range(0.18, 0.42) * randf_range(0.6, 1.2)
		var at := pos + Vector3(randf_range(-0.25, 0.25), randf_range(-0.1, 0.25), randf_range(-0.25, 0.25))
		var dir := Vector3(randf_range(-1.0, 1.0), randf_range(-0.1, 1.3), randf_range(-1.0, 1.0)).normalized()
		fx.sphere(at, pos + dir * randf_range(1.2, 2.8), r, 0.0, col, emit, 0.0, randf_range(0.22, 0.48))
	# 26 fine debris particles (each gone at 85% of its flight, as before)
	for _i in 26:
		var hot := randf()  # cosmetic
		var col := Color(1.0, lerpf(0.25, 0.80, hot), lerpf(0.0, 0.18, hot))
		var dir := Vector3(randf_range(-1.0, 1.0), randf_range(-0.15, 1.4), randf_range(-1.0, 1.0)).normalized()
		var end := pos + dir * randf_range(1.0, 3.8) * 0.85
		var e := randf_range(3.0, 5.5)
		fx.sphere(pos, end, randf_range(0.05, 0.11), 0.0, col, e, e, randf_range(0.38, 0.75) * 0.85)
	if fancy():  # T523: a smoke column rising off it, and a few sparks arcing down
		for _i in 8:
			var at := pos + Vector3(randf_range(-0.6, 0.6), randf_range(0.0, 0.6), randf_range(-0.6, 0.6))
			fx.puff(at, at + Vector3(randf_range(-0.8, 0.8), randf_range(3.0, 6.0), randf_range(-0.8, 0.8)),
				randf_range(0.5, 0.8), randf_range(1.6, 2.4), Color(0.22, 0.21, 0.2), 0.7, 0.0, randf_range(1.2, 1.8), randf_range(0.0, 0.25))
		for _i in 12:
			var d := Vector3(randf_range(-1.0, 1.0), randf_range(0.4, 1.4), randf_range(-1.0, 1.0)).normalized()
			fx.sphere(pos, pos + d * randf_range(2.0, 4.5), 0.06, 0.0, Color(1.0, 0.8, 0.4), 0.0, 0.0, randf_range(0.5, 0.9), 0.0, 2.0)

@rpc("authority", "unreliable")
func _rpc_death_explosion(pos: Vector3) -> void:
	if multiplayer.is_server():
		return
	death_explosion(pos)

# T263: spent casings -- one shared pool per arena (scripts/Casings.gd), made on first use;
# cosmetic, local on every peer; none on a dedicated server (nothing renders there).
var _casings: Node = null

func casing(weapon: Node3D, shell := false) -> void:
	var scene := get_tree().current_scene
	if scene == null or Game.dedicated or not is_instance_valid(weapon) or not weapon.is_inside_tree():
		return
	if not is_instance_valid(_casings) or _casings.get_parent() != scene:
		_casings = load("res://scripts/Casings.gd").new()
		_casings.cap = 1000 if bool(Game.settings.get("casings_long", true)) else 150
		scene.add_child(_casings)
	_casings.eject(weapon, shell)
