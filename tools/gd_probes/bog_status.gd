extends Node
# T284 probe (HUMAN_FOUND 2026-11-05: "Bogged down status effect should have a HUD icon and
# slowdown % listed. This should go under the minimap"): with our mech slowed to 55% by the
# terrain the HUD shows an icon + "BOGGED -45%" just under the minimap; at full speed nothing.

func _fail(msg: String) -> void:
	push_error("[probe] bog_status FAIL: " + msg)

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
	var hud: Node = arena.get("hud")
	me.set("terrain_speed", 0.55)  # Swamp's WADE
	for i in 5:
		await get_tree().process_frame
	var bad := false
	var box := hud.find_child("BogStatus", true, false) as Control
	var mm := hud.get("minimap") as Control
	if box == null or not box.visible:
		_fail("no bogged-down status while wading at 55%")
		bad = true
	else:
		var t: String = (box.find_child("BogLabel", true, false) as Label).text
		if not t.contains("45%"):
			_fail("status reads '%s', want the 45%% slowdown" % t)
			bad = true
		if box.find_child("BogIcon", true, false) == null:
			_fail("no icon")
			bad = true
		var r := mm.get_global_rect()
		var b := box.get_global_rect()
		if b.position.y < r.end.y or b.position.y > r.end.y + 20.0 or absf(b.position.x - r.position.x) > 2.0:
			_fail("status at %s is not just under the minimap %s" % [b, r])
			bad = true
	me.set("terrain_speed", 1.0)
	for i in 5:
		await get_tree().process_frame
	if box != null and box.visible:
		_fail("status still shown at full speed")
		bad = true
	if bad:
		get_tree().quit(1)
		return
	print("[probe] bog_status done")
	get_tree().quit(0)
