extends Node
# T538 probe (user 2026-11-20: "A few weapons don't show their damage correctly; Patience, for example, should
# show a range. Arc, too."): every catalog weapon's damage_range() is positive and ordered, and its hangar tip
# prints its real numbers: Patience min - max, Arc far - close, Shotgun the pellets' close / far totals (not
# the unused base `damage`), Orbital centre / rim, Mortar / Missile direct + splash, the MG's spin-up rates.
# T537: the stat bars' bounds are per slot size (Inferno LT's 14 m is the light minimum, Patience's 300 m
# the heavy maximum) and StatBar puts the min holder at 0, the max at 1, a range as its span.
# T562 (user: "Modify hangar to match current behavior."): a direct hit takes no splash (the blast skips the
# struck mech), so a splash weapon's most on one mech is its direct or its splash, whichever is more (x the
# salvo) -- it said direct + splash.
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
		if w is Mortar or w is MissileLauncher or w is AerialStrike:
			var most: float = maxf(w.damage, w.splash_damage) * (w.burst_count if w is AerialStrike else 1)
			if not is_equal_approx(r.y, most):
				bad.append("%s damage_range max %s, want %s (a direct hit takes no splash)" % [e["name"], r.y, most])
			if " + " in String(w.call("damage_text")):
				bad.append("%s tip adds direct + splash: %s" % [e["name"], w.call("damage_text")])
		for v in want:
			var s := WB.num(float(v)) if not (w is MachineGun) else "%.0f" % float(v)
			if not (" %s " % s) in (tip.replace("\n", " ") + " ").replace("-", " ").replace("(", " "):
				bad.append("%s tip lacks %s:\n%s" % [e["name"], s, tip.split("\n\n")[0]])
		w.free()
	var bl: Dictionary = H.weapon_bounds(0)
	var bh: Dictionary = H.weapon_bounds(1)
	if bl["range"] != [14.0, 200.0] or bh["range"] != [18.0, 300.0]:
		bad.append("range bounds light %s heavy %s (want [14, 200] / [18, 300], per slot size)" % [bl["range"], bh["range"]])
	var b0 := StatBar.make(14.0, 14.0, 14.0, 200.0)
	var b1 := StatBar.make(200.0, 200.0, 14.0, 200.0)
	var bs := StatBar.make(50.0, 110.0, 10.0, 210.0)
	if b0.lo != 0.0 or b1.hi != 1.0 or absf(bs.lo - 0.2) > 0.001 or absf(bs.hi - 0.5) > 0.001:
		bad.append("StatBar fractions %s %s %s/%s" % [b0.lo, b1.hi, bs.lo, bs.hi])
	for b in [b0, b1, bs]:
		b.free()
	if not bad.is_empty():
		push_error("[probe] weapon_tips FAIL: " + "; ".join(bad))
		get_tree().quit(1)
		return
	print("[probe] weapon_tips done (%d weapons)" % H.WEAPON_CATALOG.size())
	get_tree().quit(0)
