extends Node
# T538 probe (user 2026-11-20: "A few weapons don't show their damage correctly; Patience, for example, should
# show a range. Arc, too."): every catalog weapon's damage_range() is positive and ordered, and its hangar tip
# prints its real numbers: Patience min - max, Arc far - close, Shotgun the pellets' close / far totals (not
# the unused base `damage`), Orbital centre / rim, Mortar / Missile direct + splash, the MG's spin-up rates.
const H := preload("res://scripts/Hangar.gd")
const WB := preload("res://scripts/WeaponBase.gd")

func _ready() -> void:
	var bad: Array = []
	for i in H.WEAPON_CATALOG.size():
		var e: Dictionary = H.WEAPON_CATALOG[i]
		var w: Node = (load(e["path"]) as PackedScene).instantiate()
		var r: Vector2 = w.call("damage_range")
		var tip: String = H.weapon_tip(i)
		if not (r.x > 0.0 and r.x <= r.y):
			bad.append("%s damage_range %s" % [e["name"], r])
		var want: Array = []
		if w is Patience:
			want = [w.min_damage, w.max_damage]
		elif w is ArcWeapon:
			want = [w.damage, w.max_damage]
		elif w is Shotgun:
			want = [w.damage_close * w.pellet_count, w.damage_far * w.pellet_count]
		elif w is OrbitalStrike:
			want = [w.damage, w.edge_damage]
		elif w is Mortar or w is MissileLauncher:
			want = [w.damage, w.splash_damage]
		elif w is MachineGun:
			want = [w.base_fire_rate, w.max_fire_rate]
		for v in want:
			var s := WB.num(float(v)) if not (w is MachineGun) else "%.0f" % float(v)
			if not (" %s " % s) in (tip.replace("\n", " ") + " ").replace("-", " ").replace("(", " "):
				bad.append("%s tip lacks %s:\n%s" % [e["name"], s, tip.split("\n\n")[0]])
		w.free()
	if not bad.is_empty():
		push_error("[probe] weapon_tips FAIL: " + "; ".join(bad))
		get_tree().quit(1)
		return
	print("[probe] weapon_tips done (%d weapons)" % H.WEAPON_CATALOG.size())
	get_tree().quit(0)
