extends Node
# T195 probe (HUMAN_FOUND_ISSUES: the red damage flash for laser / machine-gun fire is
# "flickery and annoying"): a 10 Hz hit stream (MG rate) must hold a steady tint -- no
# frame-to-frame jumps -- and fade once it stops; an isolated hit still flashes.

func _fail(msg: String) -> void:
	push_error("[probe] hud_damage: " + msg)

func _ready() -> void:
	var hud: Node = load("res://scenes/ui/HUD.tscn").instantiate()
	add_child(hud)
	var flash: CanvasItem = hud.get_node("DamageFlash")
	var lo := INF
	var hi := 0.0
	var jump := 0.0
	var prev := -1.0
	for i in 120:  # 2 s at 60 Hz, a hit every 6 ticks
		if i % 6 == 0:
			hud.show_damage()
		await get_tree().process_frame
		var a := flash.modulate.a
		if i >= 30:  # past the first 0.5 s: the stream is established
			lo = minf(lo, a)
			hi = maxf(hi, a)
			if prev >= 0.0:
				jump = maxf(jump, absf(a - prev))
			prev = a
	if jump > 0.05 or hi - lo > 0.1:
		_fail("10 Hz hits flicker: alpha %.2f..%.2f, biggest frame step %.2f" % [lo, hi, jump])
	for i in 60:
		await get_tree().process_frame
	if flash.modulate.a > 0.01:
		_fail("tint did not fade 1 s after the stream stopped (alpha %.2f)" % flash.modulate.a)
	hud.show_damage()
	await get_tree().process_frame
	if flash.modulate.a < 0.4:
		_fail("an isolated hit no longer flashes (alpha %.2f)" % flash.modulate.a)
	print("[probe] hud_damage done (stream alpha %.2f..%.2f, max step %.3f)" % [lo, hi, jump])
	get_tree().quit(0)
