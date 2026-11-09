extends Node
# T354 probe (HUMAN_FOUND 2026-11-08: "remove Cesh from bot rosters at lower difficulties"):
# Easy / Normal / Medium bot squads never field Cesh (no stealth tactics below Hard, T295);
# Hard / Elite still do.

const Lobby := preload("res://scripts/Lobby.gd")

func _cesh_count(diff: int) -> int:
	Game.settings["bot_difficulty"] = diff
	var n := 0
	for id in 40:
		for e in Lobby._default_bot_squad(id):
			if String(e["mech"]).ends_with("/Cesh.tres"):
				n += 1
	return n

func _ready() -> void:
	var keep = Game.settings.get("bot_difficulty", 1)
	var bad: Array = []
	for d in [0, 1, 2]:
		if _cesh_count(d) > 0:
			bad.append("difficulty %d bots field Cesh" % d)
	for d in [3, 4]:
		if _cesh_count(d) == 0:
			bad.append("difficulty %d bots never field Cesh" % d)
	Game.settings["bot_difficulty"] = keep
	if not bad.is_empty():
		push_error("[probe] bot_roster FAIL: " + "; ".join(bad))
		get_tree().quit(1)
		return
	print("[probe] bot_roster done")
	get_tree().quit(0)
