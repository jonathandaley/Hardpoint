extends Node3D
# T316 probe (user 2026-11-05: the bullet impact sound "should not play for laser, arc, or
# patience. Any raycast weapons added in the future, either"): a hit confirmed the raycast way
# (no projectile) plays no hit_impact sound for any weapon, the beam / hitscan weapons included;
# a projectile's hit still does; and every projectile on_hit passes by_projectile.

const HITSCAN := ["LaserCannonLight", "LaserCannonHeavy", "ArcWeaponLight", "ArcWeaponHeavy", "PatienceHeavy"]

func _impacts() -> int:
	return get_tree().root.get_children().filter(func(n): return n is AudioStreamPlayer3D and (n as AudioStreamPlayer3D).stream != null and (n as AudioStreamPlayer3D).stream.resource_path.ends_with("hit_impact.wav")).size()

func _hurts() -> int:
	return get_tree().root.get_children().filter(func(n): return n is AudioStreamPlayer3D and (n as AudioStreamPlayer3D).stream != null and (n as AudioStreamPlayer3D).stream.resource_path.ends_with("damage_hit.wav")).size()

func _fail(msg: String) -> void:
	push_error("[probe] impact_sound FAIL: " + msg)

func _ready() -> void:
	await get_tree().process_frame  # root is busy during _ready: SoundManager's add_child would fail
	var dummy := Node3D.new()
	add_child(dummy)
	dummy.global_position = Vector3(0, 1, -10)
	var bad := false
	for n in HITSCAN + ["RifleLight"]:
		var w: Node = (load("res://scenes/weapons/%s.tscn" % n) as PackedScene).instantiate()
		add_child(w)
		var before := _impacts()
		w.call("_emit_hit_if_visible", dummy, dummy.global_position)
		if _impacts() > before:
			_fail("%s: a raycast-style hit played the impact sound" % n)
			bad = true
		if n == "RifleLight":
			before = _impacts()
			w.set("_last_cue_tick", -1000)  # T330: one cue per blast -- this is the next blast
			w.call("_emit_hit_if_visible", dummy, dummy.global_position, true)
			if _impacts() <= before:
				_fail("a projectile hit no longer plays the impact sound")
				bad = true
		w.queue_free()
	for f in DirAccess.get_files_at("res://scripts"):
		if f.ends_with(".gd"):
			var src: String = (load("res://scripts/" + f) as Script).source_code
			if src.contains("on_hit = func(body, pos): _emit_hit_if_visible(body, pos)"):
				_fail("%s: a projectile's on_hit doesn't pass by_projectile" % f)
				bad = true
	# T360 (HUMAN_FOUND 2026-11-08 late: "Impact sound still plays when hit by arc weapon"): the
	# hurt clank on the struck mech stays quiet for arc / laser / Patience damage; a rifle still sounds it
	var md: Resource = load("res://resources/mechs/Pegasus.tres")
	var m: Node3D = md.scene.instantiate()
	MechVisuals.apply(m, md.display_name)
	add_child(m)
	m.set_physics_process(false)
	m.remove_from_group("mechs")
	for n in HITSCAN + ["RifleLight"]:
		var w: Node = (load("res://scenes/weapons/%s.tscn" % n) as PackedScene).instantiate()
		add_child(w)
		m.set("_last_hurt_sfx", -1000)
		var before := _hurts()
		m.call("take_damage", 1.0, w)
		var sounded := _hurts() > before
		if sounded != (n == "RifleLight"):
			_fail("%s damage %s the hurt sound" % [n, "played" if sounded else "didn't play"])
			bad = true
		w.queue_free()
	for p in get_tree().root.find_children("*", "", true, false):  # B124: no sound left playing at exit
		if p is AudioStreamPlayer3D or p is AudioStreamPlayer:
			p.stop()
	await get_tree().create_timer(0.3).timeout
	if bad:
		get_tree().quit(1)
		return
	print("[probe] impact_sound done")
	get_tree().quit(0)
