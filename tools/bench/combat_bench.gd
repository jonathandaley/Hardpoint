extends Node
# T166: per-call cost of combat work that showed up as frame spikes in soaks.
# Run: godot --headless --path . res://tools/bench/combat_bench.tscn
# Measures (usec per call, median of reps) on a real SP Arena, headless.

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Game.mp_active_match["roster"] = []
	Game.loadout["mech_def"] = load("res://resources/mechs/Hippogriff.tres")
	var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arena)
	for i in 120:
		await get_tree().physics_frame
	var p := Vector3(0, 6, 0)
	_bench("VFX.muzzle_flash", 60, func(): VFX.muzzle_flash(p))
	_bench("VFX.tracer", 60, func(): VFX.tracer(p, p + Vector3(20, 0, 0)))
	_bench("VFX.hit_sparks", 60, func(): VFX.hit_sparks(p))
	_bench("SoundManager.play_sfx", 60, func(): SoundManager.play_sfx("hit_impact", p))
	_bench("VFX.death_explosion", 10, func(): VFX.death_explosion(p))
	var stream: AudioStream = load("res://audio/sfx/weapons/hit_impact.wav")
	_bench("sfx: new player + add_child (no play)", 60, func():
		var pl := AudioStreamPlayer3D.new(); pl.stream = stream; get_tree().root.add_child(pl); pl.queue_free())
	var pooled := AudioStreamPlayer3D.new()
	pooled.stream = stream
	get_tree().root.add_child(pooled)
	_bench("sfx: play() on an existing player", 60, func(): pooled.play())
	_bench("sfx: stream.instantiate_playback()", 60, func(): stream.instantiate_playback())
	var mechs := get_tree().get_nodes_in_group("mechs")
	var victims: Array = mechs.slice(1, 4)
	var died: Array = []
	for m in victims:
		var t0 := Time.get_ticks_usec()
		m.call("_die")
		died.append(Time.get_ticks_usec() - t0)
	print("[bench] Mech._die x%d: %s usec" % [died.size(), str(died)])
	# smoke-trail projectile salvo: spawn 16 (a shotgun-ish volley) and time the next frames
	var scene: PackedScene = load("res://scenes/weapons/ProjectileGrey.tscn")
	var t_spawn := Time.get_ticks_usec()
	for i in 16:
		var pr: Node3D = scene.instantiate()
		pr.set("velocity", Vector3(randf_range(-2, 2), 0, 60))
		arena.add_child(pr)
		pr.global_position = p + Vector3(i * 0.1, 0, 0)
	print("[bench] spawn 16 ProjectileGrey: %d usec" % (Time.get_ticks_usec() - t_spawn))
	var frames: Array = []
	for i in 30:
		var f0 := Time.get_ticks_usec()
		await get_tree().physics_frame
		frames.append(Time.get_ticks_usec() - f0)
	frames.sort()
	print("[bench] 30 frames with 16 smoke projectiles alive: median %d max %d usec (wall per frame)" % [frames[15], frames[-1]])
	print("[bench] done")
	get_tree().quit(0)

func _bench(label: String, reps: int, f: Callable) -> void:
	var times: Array = []
	for i in reps:
		var t0 := Time.get_ticks_usec()
		f.call()
		times.append(Time.get_ticks_usec() - t0)
	times.sort()
	print("[bench] %s: median %d usec, max %d (x%d)" % [label, times[reps / 2], times[-1], reps])
