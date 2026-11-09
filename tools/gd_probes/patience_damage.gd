extends Node
# T298 probe (HUMAN_FOUND 2026-11-05: "Patience damage should scale higher; human testing shows
# sniper to be vastly better than patience in every situation I tried"): a full Patience charge
# hits for >= 2.5x a heavy sniper shot (it takes 12 s to charge + 3.5 s reload: 62.5 was ~4 DPS
# vs the sniper's ~13), and the scene's `damage` equals max_damage -- the server rejects any hit
# over 1.5x a weapon's `damage` (Mech.request_damage, V28).

func _ready() -> void:
	var p: Node = (load("res://scenes/weapons/PatienceHeavy.tscn") as PackedScene).instantiate()
	var s: Node = (load("res://scenes/weapons/SniperHeavy.tscn") as PackedScene).instantiate()
	var full: float = p.get("max_damage")
	var sniper: float = s.get("damage")
	var msg := ""
	if full < sniper * 2.5:
		msg = "full charge %.1f vs a sniper shot %.1f (want >= 2.5x)" % [full, sniper]
	elif not p.has_method("charge_damage"):
		msg = "no charge_damage() (T348)"
	elif absf(float(p.get("damage")) - full) > 0.01:
		msg = "damage %.1f != max_damage %.1f: full-charge hits over 1.5x damage are dropped" % [float(p.get("damage")), full]
	if msg == "":  # T348: damage grows with charge squared -- half a charge, a quarter of the way
		var lo: float = p.get("min_damage")
		for c in [[0.5, lo + (full - lo) * 0.25], [1.0, full], [0.0, lo]]:
			p.set("_charge_time", float(p.get("max_charge_time")) * float(c[0]))
			var got: float = p.call("charge_damage")
			if absf(got - float(c[1])) > 0.01:
				msg = "%.0f%% charge hits %.1f, want %.1f (charge squared)" % [float(c[0]) * 100.0, got, float(c[1])]
	p.free()
	s.free()
	if msg != "":
		push_error("[probe] patience_damage FAIL: " + msg)
		get_tree().quit(1)
		return
	print("[probe] patience_damage done (full %.0f vs sniper %.0f)" % [full, sniper])
	get_tree().quit(0)
