extends Node
# T304 probe (HUMAN_FOUND 2026-11-05: "Remove debug mech and the 'e' mark set key. Archive the
# code just in case"): the hangar roster has no debug mech, the mark_debug input action and the
# Mech mark signal are gone, the removed code is archived, and a squad saved with the debug mech
# loads as a normal one.

func _ready() -> void:
	var bad: Array = []
	var roster: Array = (load("res://scripts/Hangar.gd") as Script).get_script_constant_map()["ROSTER"]
	if roster.any(func(p): return String(p).contains("DebugMech")):
		bad.append("debug mech still in the hangar roster")
	if InputMap.has_action("mark_debug"):
		bad.append("mark_debug input action still bound")
	var mech: Node = (load("res://scenes/mech/Mech.tscn") as PackedScene).instantiate()
	if mech.has_signal("mark_requested"):
		bad.append("Mech still has mark_requested")
	mech.free()
	if not FileAccess.file_exists("res://archive/T304_debug_mark.md"):
		bad.append("the removed code isn't archived")
	Game.loadout["squad"] = ["res://resources/mechs/DebugMech.tres"]
	var h: Node = load("res://scenes/ui/Hangar.tscn").instantiate()
	add_child(h)
	await get_tree().process_frame
	if (Game.loadout.get("squad", []) as Array).any(func(p): return String(p).contains("DebugMech")):
		bad.append("a saved squad kept the debug mech")
	if not bad.is_empty():
		push_error("[probe] no_debug_bits FAIL: " + "; ".join(bad))
		get_tree().quit(1)
		return
	print("[probe] no_debug_bits done")
	get_tree().quit(0)
