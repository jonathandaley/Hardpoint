extends Node3D
# T331 probe (HUMAN_FOUND 2026-11-05: 'New "missile_explosion" sound ... played when a missile
# explodes'): the sound is registered and loads, and a missile burst -- real shot or client
# ghost -- plays it where it bursts.

const SHOT := preload("res://scenes/weapons/ProjectileGrey.tscn")

func _booms() -> Array:
	return get_tree().root.get_children().filter(func(n): return n is AudioStreamPlayer3D and (n as AudioStreamPlayer3D).stream != null and (n as AudioStreamPlayer3D).stream.resource_path.ends_with("missile_explosion.ogg"))

func _ready() -> void:
	get_tree().current_scene = self
	var msg := ""
	if SoundManager.get_sfx_stream("missile_explosion") == null:
		msg = "no missile_explosion sound registered / loadable"
	for ghost in [false, true]:
		if msg != "":
			break
		var before := _booms().size()
		var p: Node3D = SHOT.instantiate()
		p.set("explode", true)
		p.set("splash_radius", 4.0)
		p.set("lifetime", 0.2)
		p.set("is_ghost", ghost)
		add_child(p)
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 1000 and _booms().size() <= before:
			await get_tree().physics_frame
		if _booms().size() <= before:
			msg = "a %s missile burst without the missile_explosion sound" % ("ghost" if ghost else "real")
	if msg != "":
		push_error("[probe] missile_sound FAIL: " + msg)
		get_tree().quit(1)
		return
	print("[probe] missile_sound done")
	get_tree().quit(0)
