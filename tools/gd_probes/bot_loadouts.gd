extends Node
# T365 probe (user 2026-11-09: "Regular difficulties have random mechs, with weapons weighted to make
# sense with the mech"): regular bot squads mix mechs (not one mech repeated), and over many draws a
# mech's favourite families come up most -- Slip / Seeker snipe, Cesh brawls (never a sniper),
# Hippogriff fires missiles -- while every family that fits still turns up sometimes.

const Lobby := preload("res://scripts/Lobby.gd")

func _fail(msg: String) -> void:
	push_error("[probe] bot_loadouts FAIL: " + msg)
	get_tree().quit(1)

func _family(path: String) -> String:
	for w in Lobby.WEAPON_CATALOG:
		if w["path"] == path:
			return String(w["name"]).get_slice(" ", 0)
	return "?"

func _ready() -> void:
	Game.fixed_bots = ""  # T376: this probe tests the random draw itself
	var bad: Array = []
	Game.settings["bot_difficulty"] = 3
	var mixed := 0
	for i in 20:
		var squad: Array = Lobby._default_bot_squad(i)
		var mechs := {}
		for e in squad:
			mechs[e["mech"]] = true
		if mechs.size() > 1:
			mixed += 1
	if mixed < 15:
		bad.append("only %d of 20 squads mix mechs (want random mechs per slot)" % mixed)
	var rng := RandomNumberGenerator.new()
	rng.seed = 365
	for name in ["Slip", "Seeker", "Cesh", "Hippogriff"]:
		var md: Resource = load("res://resources/mechs/%s.tres" % name)
		var count := {}
		for i in 400:
			var fam := _family(Lobby.bot_weapon_paths(md, rng)[0])
			count[fam] = int(count.get(fam, 0)) + 1
		var top: String = count.keys().reduce(func(a, b): return a if count[a] >= count[b] else b)
		var want: String = {"Slip": "SNIPER", "Seeker": "SNIPER", "Cesh": "SHOTGUN", "Hippogriff": "MISSILE"}[name]
		if top != want:
			bad.append("%s's most common family is %s, want %s (%s)" % [name, top, want, count])
		if name == "Cesh" and count.has("SNIPER"):
			bad.append("Cesh drew a sniper (weight 0)")
		if count.size() < 4:
			bad.append("%s only ever gets %s (want variety)" % [name, count.keys()])
	if not bad.is_empty():
		_fail("; ".join(bad))
		return
	print("[probe] bot_loadouts done (%d / 20 squads mixed)" % mixed)
	get_tree().quit(0)
