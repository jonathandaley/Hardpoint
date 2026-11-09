extends Node
# T349 probe (HUMAN_FOUND 2026-11-08): the Patience HUD charge bar is yellow while charging and
# purple once the charge is full.

class FakeMech extends Node:
	var w: Array = []
	func get_weapons() -> Array:
		return w

func _fail(msg: String) -> void:
	push_error("[probe] patience_bar FAIL: " + msg)
	get_tree().quit(1)

func _ready() -> void:
	var p: Node = (load("res://scenes/weapons/PatienceHeavy.tscn") as PackedScene).instantiate()
	p.set_process(false)
	p.set_physics_process(false)
	add_child(p)
	var m := FakeMech.new()
	m.w = [p]
	add_child(m)
	var hud: Control = (load("res://scripts/WeaponHUD.gd") as GDScript).new()
	add_child(hud)
	hud.setup(m)
	var bar: ColorRect = hud.get("_entries")[0]["charge_fg"]
	var full: float = p.get("max_charge_time")
	p.set("_charge_time", full * 0.5)
	await get_tree().process_frame
	await get_tree().process_frame
	if bar.color.b > bar.color.r * 0.6 or bar.color.g < 0.5:
		_fail("half charge bar %s, want yellow" % bar.color)
		return
	p.set("_charge_time", full)
	await get_tree().process_frame
	await get_tree().process_frame
	if not (bar.color.b > 0.7 and bar.color.r > 0.5 and bar.color.g < 0.5):
		_fail("full charge bar %s, want purple" % bar.color)
		return
	print("[probe] patience_bar done")
	get_tree().quit(0)
