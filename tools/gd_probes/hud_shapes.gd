extends Node
# T328 probe (before release: any screen shape): in a match the canvas fills the window's shape
# (16:10, 21:9, a tall browser) instead of letterboxing to 16:9, and the corner HUD sits in the
# real corners -- minimap top-right, weapon slots bottom-right, also after a mid-match resize; back in the
# menus the designed 640x360 layout letterboxes again.

func _fail(msg: String) -> void:
	push_error("[probe] hud_shapes FAIL: " + msg)
	get_tree().quit(1)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var rows := []
	for shape in [Vector2i(1280, 720), Vector2i(1280, 800), Vector2i(1680, 720), Vector2i(720, 1100)]:
		get_tree().root.size = shape
		Game.mp_active_match["roster"] = []
		Game.loadout["team_size"] = 1
		Game.loadout["sp_bots"] = [0, 1]
		Game.loadout["mode"] = "beacons"
		var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
		get_tree().root.add_child.call_deferred(arena)
		for i in 3:
			await get_tree().process_frame
		if arena.get("_start_pick_open"):
			arena.get("hud").squad_slot_selected.emit(0)
			arena.get("hud").spawn_selected.emit(0)
		for i in 5:
			await get_tree().process_frame
		var vis: Vector2 = get_viewport().get_visible_rect().size
		var want_aspect := float(shape.x) / float(shape.y)
		if absf(vis.x / vis.y - want_aspect) > 0.02:
			_fail("%s window: the canvas is %s (aspect %.2f, want %.2f) -- letterboxed" % [shape, vis, vis.x / vis.y, want_aspect])
			return
		var hud: Node = arena.get("hud")
		var mm: Control = hud.get("minimap")
		var wh: Control = hud.get("weapon_hud")
		var mr := mm.get_global_rect()
		var wr := wh.get_global_rect()
		if absf(mr.end.x - vis.x) > 24.0 or mr.position.y > 24.0:
			_fail("%s: minimap at %s, not in the top-right of %s" % [shape, mr, vis])
			return
		if absf(wr.end.x - vis.x) > 24.0 or absf(wr.end.y - vis.y) > 24.0:
			_fail("%s: weapon slots at %s, not in the bottom-right of %s" % [shape, wr, vis])
			return
		rows.append("%dx%d -> %dx%d" % [shape.x, shape.y, vis.x, vis.y])
		if shape == Vector2i(1280, 720):  # fullscreen / resize mid-match: the pieces follow
			get_tree().root.size = Vector2i(1680, 720)
			for i in 3:
				await get_tree().process_frame
			vis = get_viewport().get_visible_rect().size
			wr = wh.get_global_rect()
			if absf(wr.end.x - vis.x) > 24.0:
				_fail("after a mid-match resize to %s the weapon slots stayed at %s" % [vis, wr])
				return
		arena.queue_free()
		for i in 3:
			await get_tree().process_frame
	if get_tree().root.content_scale_aspect != Window.CONTENT_SCALE_ASPECT_KEEP:
		_fail("menus after a match don't letterbox again (aspect mode %d)" % get_tree().root.content_scale_aspect)
		return
	print("[probe] hud_shapes done (%s)" % ", ".join(rows))
	get_tree().quit(0)
