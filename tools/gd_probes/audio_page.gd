extends Node
# T433 probe (user 2026-11-16: "Multiple volume sliders, probably under an \"Audio\" tag: master, UI,
# SFX, ambiance, music (stub)"): Settings has an AUDIO page with a slider per bus; moving one sets
# that bus's volume and is saved; UI clicks play on the UI bus, game sounds on SFX; the master
# slider left the main page.

func _ready() -> void:
	var bad: Array = []
	var st: Node = load("res://scenes/ui/Settings.tscn").instantiate()
	add_child(st)
	await get_tree().process_frame
	if st.get_node_or_null("Scroll/Content/VolRow") != null:
		bad.append("the old master volume row is still on the main page")
	var open := st.find_child("AudioButton", true, false) as Button
	var page := st.find_child("AudioPage", true, false) as Control
	if open == null or page == null:
		bad.append("no AUDIO button / page")
	else:
		open.pressed.emit()
		await get_tree().process_frame
		if not page.visible:
			bad.append("AUDIO didn't open its page")
		var keep := {}
		for bv in Game.VOLUME_BUSES:
			keep[bv[1]] = Game.settings.get(bv[1])
			var row := page.find_child("Vol" + bv[0], true, false)
			if row == null:
				bad.append("no %s slider" % bv[2])
				continue
			var sl := row.get_node("Slider") as HSlider
			sl.value = 0.25
			var i := AudioServer.get_bus_index(bv[0])
			if i < 0 or absf(AudioServer.get_bus_volume_db(i) - linear_to_db(0.25)) > 0.01:
				bad.append("%s slider at 25%% left bus %s at %s dB" % [bv[2], bv[0], AudioServer.get_bus_volume_db(i) if i >= 0 else "missing"])
			if i > 0 and AudioServer.get_bus_send(i) != &"Master":
				bad.append("bus %s sends to %s" % [bv[0], AudioServer.get_bus_send(i)])
			var cfg := ConfigFile.new()
			cfg.load("user://settings.cfg")
			if absf(float(cfg.get_value("settings", bv[1], -1.0)) - 0.25) > 0.001:
				bad.append("%s not saved (%s)" % [bv[1], cfg.get_value("settings", bv[1], null)])
		for k in keep:
			Game.settings[k] = keep[k]
		Game.apply_volumes()
		Game.save_settings()
	for key in ["ui_click", "hit_impact"]:
		var before := get_tree().root.get_children().size()
		SoundManager.play_sfx_2d(key)
		var p: Node = get_tree().root.get_child(get_tree().root.get_child_count() - 1)
		var want := "UI" if key == "ui_click" else "SFX"
		if get_tree().root.get_children().size() == before or not p is AudioStreamPlayer or String(p.bus) != want:
			bad.append("%s plays on %s, want %s" % [key, p.get("bus"), want])
	if not bad.is_empty():
		push_error("[probe] audio_page FAIL: " + "; ".join(bad))
		get_tree().quit(1)
		return
	print("[probe] audio_page done")
	get_tree().quit(0)
