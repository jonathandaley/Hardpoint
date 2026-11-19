extends Node
# T495 probe (HUMAN_FOUND 2026-11-18: "Ammo powerup should fully charge Patience."): the ammo pickup's
# refill (Mech.refill_ammo) leaves a Patience at full charge, its magazine full.

func _fail(msg: String) -> void:
	push_error("[probe] patience_refill FAIL: " + msg)
	get_tree().quit(1)

func _ready() -> void:
	var md: Resource = load("res://resources/mechs/Denali.tres")
	var slots: Array = []
	for sd in md.weapon_slots:
		var c: Resource = sd.duplicate()
		c.weapon_scene = load("res://scenes/weapons/PatienceHeavy.tscn")
		slots.append(c)
	var m: Node3D = md.scene.instantiate()
	add_child(m)
	m.call("configure_weapons", slots)
	await get_tree().physics_frame
	var w: Node = (m.call("get_weapons") as Array)[0]
	w.set("ammo", 0)
	w.set("_charge_time", 0.0)
	m.call("refill_ammo")
	if float(w.get("_charge_time")) < float(w.get("max_charge_time")) - 0.001 or int(w.get("ammo")) != int(w.get("max_ammo")):
		_fail("after the refill: charge %.2f / %.2f s, ammo %d / %d" % [w.get("_charge_time"), w.get("max_charge_time"), w.get("ammo"), w.get("max_ammo")])
		return
	print("[probe] patience_refill done")
	m.free()
	get_tree().quit(0)
