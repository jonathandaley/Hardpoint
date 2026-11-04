extends Node
# T236 probe (HUMAN_FOUND_ISSUES 2026-11-04: "health bars obstruct vision too much, make them
# shorter"): an enemy in view gets an over-head bar no bigger than MAX_W x MAX_H px (on the
# 640 x 360 canvas; it was 32 x 6), and it is still drawn above the mech.

const MAX_W := 20.0
const MAX_H := 3.0

func _fail(msg: String) -> void:
	push_error("[probe] health_bars: " + msg)

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
	var me: Node3D = arena.get("player_mech")
	var enemy: Node3D = arena.get("_team_mechs")[1 - int(me.get("team"))][0]
	for t in 2:
		for m in arena.get("_team_mechs")[t]:
			m.invincible = true
			m.process_mode = Node.PROCESS_MODE_DISABLED
	me.process_mode = Node.PROCESS_MODE_INHERIT
	var cam: Camera3D = me.get("camera")
	enemy.global_position = cam.global_position + (-cam.global_transform.basis.z * Vector3(1, 0, 1)).normalized() * 18.0
	enemy.global_position.y = me.global_position.y
	for i in 10:
		await get_tree().process_frame
	var shown := 0
	for bg in arena.get("hud").get("_bot_bg_bars"):
		var r: ColorRect = bg
		if not r.visible:
			continue
		shown += 1
		var w := r.offset_right - r.offset_left
		var h := r.offset_bottom - r.offset_top
		if w > MAX_W + 0.01 or h > MAX_H + 0.01:
			_fail("enemy health bar is %.0f x %.0f px (max %.0f x %.0f)" % [w, h, MAX_W, MAX_H])
		var head := cam.unproject_position(enemy.global_position + Vector3(0, 2.0, 0))
		if r.offset_bottom > head.y:
			_fail("bar bottom %.0f is below the mech's head at %.0f" % [r.offset_bottom, head.y])
	if shown == 0:
		_fail("no enemy health bar shown with an enemy 18 m in front")
	print("[probe] health_bars done (%d shown)" % shown)
	get_tree().quit(0)
