extends Node3D
# T531 probe (user 2026-11-20: "A sniper skill, with scrolling zoom and max zoom determined by skill level"
# + "It should work on laser, too, and any other weapon with a range over 150m."): skill scope_zoom gives a
# max zoom of 1 + 0.5 x level; the wheel steps Mech.scope_zoom by 0.5 and the camera FOV follows, capped
# there and floored at 1x. Scoped: Sniper LT, Laser LT (120 m, a laser), Patience; not Rifle LT; no skill =
# no zoom; a mounted Mortar keeps the wheel for its range. T535: lock-on weapons (Rocket LT 180 m, Swarm HV) don't. The hangar text reads the max zoom ("3x").

const SlotDef := preload("res://scripts/WeaponSlotDef.gd")
const Replay := preload("res://scripts/ReplayInputSource.gd")
const MD := preload("res://resources/mechs/Kestrel.tres")

func _mech(weapons: Array, skills: Dictionary) -> Node:
	var m: Node3D = MD.scene.instantiate()
	add_child(m)
	m.set_physics_process(false)
	m.remove_from_group("mechs")
	var slots: Array = []
	for w in weapons:
		var sl := SlotDef.new()
		sl.slot_size = 1 if w.ends_with("Heavy") else 0
		sl.weapon_scene = load("res://scenes/weapons/%s.tscn" % w)
		slots.append(sl)
	m.configure_weapons(slots)
	if m.get_weapons().size() != weapons.size():
		push_error("[probe] scope_zoom FAIL: %s mounted %d weapons" % [weapons, m.get_weapons().size()])
	m.set("pilot_skills", skills)
	var src: Node = Replay.new()
	add_child(src)
	m.set_input_source(src)
	return m

func _wheel(m: Node, steps: float) -> void:
	m.get("_input_source").load_spec({"keyframes": [{"tick": 0, "wheel": steps}]})
	m.call("_handle_wheel")

func _ready() -> void:
	var bad: Array = []
	if Game.skill_effect_text("scope_zoom", 4) != "3x" or Game.skill_effect_text("scope_zoom", 1) != "1.5x":
		bad.append("hangar text %s / %s (want 3x / 1.5x)" % [Game.skill_effect_text("scope_zoom", 4), Game.skill_effect_text("scope_zoom", 1)])
	var m := _mech(["SniperLight"], {"scope_zoom": 4})
	var cam := m.get("camera") as Camera3D
	var fov0 := cam.fov
	_wheel(m, 1.0)
	if absf(float(m.get("scope_zoom")) - 1.5) > 0.001 or absf(cam.fov - fov0 / 1.5) > 0.01:
		bad.append("one notch: zoom %.2f fov %.1f (want 1.5x, %.1f)" % [m.get("scope_zoom"), cam.fov, fov0 / 1.5])
	_wheel(m, 10.0)
	if absf(float(m.get("scope_zoom")) - 3.0) > 0.001 or absf(cam.fov - fov0 / 3.0) > 0.01:
		bad.append("level 4 cap: zoom %.2f fov %.1f (want 3x, %.1f)" % [m.get("scope_zoom"), cam.fov, fov0 / 3.0])
	_wheel(m, -20.0)
	if absf(float(m.get("scope_zoom")) - 1.0) > 0.001 or absf(cam.fov - fov0) > 0.01:
		bad.append("zoomed back out: zoom %.2f fov %.1f (want 1x, %.1f)" % [m.get("scope_zoom"), cam.fov, fov0])
	for c in [[["LaserCannonLight"], {"scope_zoom": 4}, true], [["PatienceHeavy"], {"scope_zoom": 4}, true],
			[["RifleLight"], {"scope_zoom": 4}, false], [["SniperLight"], {}, false],
			[["RocketLauncherLight"], {"scope_zoom": 4}, false], [["SwarmHeavy"], {"scope_zoom": 4}, false],  # T535: lock-on
			[["MortarHeavy", "SniperLight"], {"scope_zoom": 4}, false]]:
		var mm := _mech(c[0], c[1])
		_wheel(mm, 2.0)
		var zoomed: bool = float(mm.get("scope_zoom")) > 1.0
		if zoomed != c[2]:
			bad.append("%s skills %s: zoomed %s (want %s)" % [c[0], c[1], zoomed, c[2]])
	if not bad.is_empty():
		push_error("[probe] scope_zoom FAIL: " + "; ".join(bad))
		get_tree().quit(1)
		return
	print("[probe] scope_zoom done (1.5x / 3x cap / 1x; laser + patience scoped, rifle / no skill / mortar not)")
	get_tree().quit(0)
