extends Node
# T282 probe (user 2026-11-05: "Make sure elite bots don't miss, and in fact shoot ahead of moving
# targets"; "Hard will have no intentional bad strategy/aiming errors, elite will be that plus
# upgrades"): the Hard and Elite presets carry no deliberate error -- no aim drift, full lead,
# no burst pauses, full tactics, juking -- and Elite alone is marked for pilot upgrades.

func _ready() -> void:
	var presets: Array = (load("res://scripts/AIInputSource.gd") as Script).get_script_constant_map()["DIFFICULTY_PRESETS"]
	var hard: Dictionary = presets[3]
	var elite: Dictionary = presets[4]
	var bad: Array = []
	for pair in [["Hard", hard], ["Elite", elite]]:
		var p: Dictionary = pair[1]
		if float(p["aim_jitter"]) != 0.0 or float(p["lead"]) < 1.0 or float(p["pause"]) != 0.0 or not p["tactics"] or not p.get("juke", false):
			bad.append("%s still makes deliberate errors: %s" % [pair[0], p])
	for k in ["aim_jitter", "turn_scale", "lead", "reaction", "pause", "tactics", "team", "juke"]:
		if hard.get(k) != elite.get(k):
			bad.append("Hard and Elite differ in %s (%s vs %s): only upgrades should" % [k, hard.get(k), elite.get(k)])
	if not elite.get("upgrades", false) or hard.get("upgrades", false):
		bad.append("Elite (only) should be marked for pilot upgrades")
	if not bad.is_empty():
		push_error("[probe] hard_bots FAIL: " + "; ".join(bad))
		get_tree().quit(1)
		return
	print("[probe] hard_bots done")
	get_tree().quit(0)
