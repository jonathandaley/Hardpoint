extends Node
# T301 probe (HUMAN_FOUND 2026-11-05: "Pegasus sometimes heals too much in a single jump?"):
# mashing the ability key through a whole jump heals exactly once, +Mech.JUMP_HEAL, and the 16 s cooldown
# blocks the rest.

class Src extends "res://scripts/InputSource.gd":
	var press := false
	func is_ability_pressed() -> bool:
		return press
	func is_human_input() -> bool:
		return true

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Game.mp_active_match["roster"] = []
	Game.loadout["team_size"] = 1
	var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arena)
	for i in 2:
		await get_tree().process_frame
	if arena.get("_start_pick_open"):
		arena.get("hud").squad_slot_selected.emit(0)
		arena.get("hud").spawn_selected.emit(0)
	for i in 10:
		await get_tree().physics_frame
	var me: Node = arena.get("player_mech")
	var jh: Resource = load("res://resources/abilities/JumpHeal.tres")
	if OS.get_cmdline_user_args().has("no_cooldown"):  # red check: a broken cooldown must fail this
		jh = jh.duplicate()
		jh.set("cooldown", 0.0)
	me.set("_abilities", [jh])
	me.set("_ability_cooldowns", {})
	var src := Src.new()
	me.add_child(src)
	me.set_input_source(src)
	var start: float = float(me.get("max_health")) - 100.0  # room for the heal under the cap
	me.set("health", start)
	var heals := 0
	var last: float = me.get("health")
	for i in 120:  # 2 s, the key mashed every other tick through the whole jump
		src.press = i % 2 == 0 and i < 40
		await get_tree().physics_frame
		var h: float = me.get("health")
		if h > last + 1.0:
			heals += 1
		last = h
	var gained: float = float(me.get("health")) - start
	var msg := ""
	if heals != 1 or absf(gained - Mech.JUMP_HEAL) > 1.0:
		msg = "%d heals for %.1f HP in one jump, want one +%.0f" % [heals, gained, Mech.JUMP_HEAL]
	if msg != "":
		push_error("[probe] jump_heal_once FAIL: " + msg)
		get_tree().quit(1)
		return
	print("[probe] jump_heal_once done (one heal, +%.0f)" % gained)
	get_tree().quit(0)
