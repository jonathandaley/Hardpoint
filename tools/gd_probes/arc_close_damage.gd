extends Node
# T412 probe (HUMAN_FOUND, queued 2026-11-13: "Arc weapon should increase damage as range decreases.
# Current damage is good for reasonably long range."): the arc's per-tick damage is its old value at
# long range and grows as the target gets closer; a close-range hit passes the server's per-hit check.

const SlotDef := preload("res://scripts/WeaponSlotDef.gd")

func _fail(msg: String) -> void:
	push_error("[probe] arc_close_damage FAIL: " + msg)

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
	var slot := SlotDef.new()
	slot.slot_size = 0
	slot.position = Vector3(0, 2.0, 0)
	slot.weapon_scene = load("res://scenes/weapons/ArcWeaponLight.tscn")
	me.call("configure_weapons", [slot])
	var arc: Node = me.call("get_weapons")[0]
	if not arc.has_method("damage_at"):
		_fail("the arc's damage doesn't depend on range")
		get_tree().quit(0)
		return
	var base := float(arc.get("damage"))
	var far := float(arc.damage_at(float(arc.get("range")) * 0.9))
	var mid := float(arc.damage_at(30.0))
	var close := float(arc.damage_at(5.0))
	if absf(far - base) > 0.001:
		_fail("long range %.2f, want the old %.2f" % [far, base])
	if not (close > mid and mid > far):
		_fail("doesn't climb as range falls: 5 m %.2f, 30 m %.2f, 81 m %.2f" % [close, mid, far])
	var enemy: Node = arena.get("_team_mechs")[1 - int(me.get("team"))][0]
	enemy.invincible = false
	enemy.global_position = (me as Node3D).global_position + Vector3(5, 0, 0)  # within the check's 1.2 x range
	var hp0 := float(enemy.get("health"))
	enemy.call("request_damage", close, arc)
	if absf((hp0 - float(enemy.get("health"))) - close) > 0.01:
		_fail("a close-range hit of %.2f was refused by the server check (hp %.1f -> %.1f)" % [close, hp0, float(enemy.get("health"))])
	print("[probe] arc_close_damage done (5 m %.2f, 30 m %.2f, far %.2f)" % [close, mid, far])
	get_tree().quit(0)
