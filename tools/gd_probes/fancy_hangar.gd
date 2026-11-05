extends Node
# T254 probe (HUMAN_FOUND_ISSUES 2026-11-05: fancy hangar -- Design's flying drones and
# conveyor belts -- under a GRAPHICS toggle): with FANCY HANGAR on, the bay has a roaming
# drone swarm that travels between mechs, swinging assembly arms and a scrolling tread;
# with it off, none of that exists; the GRAPHICS page toggle sets the setting.

func _fail(msg: String) -> void:
	push_error("[probe] fancy_hangar: " + msg)

func _bay(on: bool) -> Node:
	Game.settings["fancy_hangar"] = on
	var b: Node3D = load("res://scripts/HangarBay.gd").new()
	add_child(b)
	return b

func _ready() -> void:
	var b := _bay(true)
	var drones := b.find_children("SwarmDrone*", "Node3D", false, false)
	var arms := b.find_children("AssemblyArm*", "Node3D", false, false)
	if drones.size() < 3 or arms.size() < 3:
		_fail("fancy on: %d swarm drones, %d arms (want 3 / 3)" % [drones.size(), arms.size()])
	var p0: Array = drones.map(func(d): return (d as Node3D).position)
	var r0: Array = arms.map(func(a): return (a as Node3D).rotation.z)
	var tread: StandardMaterial3D = b.get("_tread")
	var u0: float = tread.uv1_offset.x if tread != null else 0.0
	await get_tree().create_timer(2.0).timeout
	var moved := 0
	for i in drones.size():
		if (drones[i] as Node3D).position.distance_to(p0[i]) > 0.5:
			moved += 1
	if moved == 0:
		_fail("no swarm drone travelled in 2 s")
	if arms.size() > 0 and absf((arms[0] as Node3D).rotation.z - float(r0[0])) < 0.01:
		_fail("assembly arms don't swing")
	if tread == null or is_equal_approx(tread.uv1_offset.x, u0):
		_fail("the tread doesn't scroll")
	b.queue_free()
	var off := _bay(false)
	if off.find_children("SwarmDrone*", "Node3D", false, false).size() > 0 or off.get("_tread") != null:
		_fail("fancy off still builds the swarm / tread")
	off.queue_free()
	var st: Node = load("res://scenes/ui/Settings.tscn").instantiate()
	add_child(st)
	await get_tree().process_frame
	var on_btn := st.find_child("Fancy_on", true, false) as Button
	var off_btn := st.find_child("Fancy_off", true, false) as Button
	if on_btn == null or off_btn == null or not st.find_child("GraphicsPage", true, false).is_ancestor_of(on_btn):
		_fail("no FANCY HANGAR toggle on the GRAPHICS page")
	else:
		off_btn.pressed.emit()
		if Game.settings.get("fancy_hangar") != false:
			_fail("FANCY HANGAR OFF didn't change the setting")
		on_btn.pressed.emit()
	print("[probe] fancy_hangar done (%d drones moved)" % moved)
	get_tree().quit(0)
