extends Node
# T494 probe (HUMAN_FOUND 2026-11-18: "Mortar should have a grey overlay like sniper to show when another
# shot is available."): the weapon HUD greys a mortar's icon while it's between shots, like the sniper's.

func _fail(msg: String) -> void:
	push_error("[probe] mortar_ready FAIL: " + msg)
	get_tree().quit(1)

func _ready() -> void:
	var md: Resource = load("res://resources/mechs/Denali.tres")
	var slots: Array = []
	for sd in md.weapon_slots:
		var c: Resource = sd.duplicate()
		c.weapon_scene = load("res://scenes/weapons/MortarHeavy.tscn")
		slots.append(c)
	var m: Node3D = md.scene.instantiate()
	add_child(m)
	m.call("configure_weapons", slots)
	var hud: Control = load("res://scripts/WeaponHUD.gd").new()
	add_child(hud)
	await get_tree().process_frame
	hud.call("setup", m)
	var w: Node = (m.call("get_weapons") as Array)[0]
	w.set("_cooldown", 0.5 / float(w.get("fire_rate")))  # half way to the next shot
	await get_tree().process_frame
	await get_tree().process_frame
	var e: Dictionary = (hud.get("_entries") as Array)[0]
	var fg: Control = e["cooldown_fg"]
	if fg.offset_right - fg.offset_left < 1.0:
		_fail("the mortar's icon isn't greyed half way to its next shot (overlay %.1f px)" % (fg.offset_right - fg.offset_left))
		return
	w.set("_cooldown", 0.0)
	await get_tree().process_frame
	if fg.offset_right - fg.offset_left > 0.5:
		_fail("the overlay stays on a mortar that's ready")
		return
	print("[probe] mortar_ready done")
	get_tree().quit(0)
