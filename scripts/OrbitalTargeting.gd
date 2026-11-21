extends Node
# T541 (user 2026-11-20: "firing frees mouse, click desired target on minimap with a circular highlight to
# show area" / "No steering, aim anywhere. Current delay is good, nerf damage to compensate." / "Stop
# completely. Multiple orbitals fired simultaneously queue and take multiple clicks to fire."): the LOCAL
# player's ORBITAL HV. Pulling a trigger that would fire one or more ready orbitals opens targeting: the mouse
# is freed, the mech stops (no walking, no aiming), the minimap grows to the middle of the screen and a circle
# of the strike's radius follows the cursor (inside the weapon's range of the mech). Each click sends one
# strike (OrbitalStrike.request_strike -> the server checks and marks it); Esc / right-click cancels the rest
# (their shots stay loaded). Bots don't come here: they strike their lock target (OrbitalStrike._do_fire).

var hud: Node = null
var arena: Node = null
var _queue: Array = []  # orbitals still to aim, this pull
var _open := false

func _process(_delta: float) -> void:
	var m: Node = arena.get("player_mech") if arena != null else null
	if _open:
		if m == null or not is_instance_valid(m) or m.get("is_dead") or _queue.is_empty():
			close()
		else:
			_preview(m)
		return
	if m == null or not is_instance_valid(m) or m.get("is_dead") or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	var prim := Input.is_action_just_pressed("fire_primary")
	var sec := Input.is_action_just_pressed("fire_secondary")
	if not (prim or sec):
		return
	var aset: Array = m.call("get_active_set")
	var ws: Array = m.call("get_weapons")
	var q: Array = []
	for i in ws.size():
		var w: Node = ws[i]
		if w is OrbitalStrike and (w as OrbitalStrike).ready_to_strike() and (prim or (i < aset.size() and aset[i])):
			q.append(w)
	if not q.is_empty():
		_open_for(q)

func _open_for(q: Array) -> void:
	_queue = q
	_open = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_set_frozen(true)
	hud.call("orbital_targeting_shown", true, _queue.size())

func close() -> void:
	if not _open:
		return
	_open = false
	_queue.clear()
	_set_frozen(false)
	var mm: Node = hud.get("minimap") if hud != null else null
	if mm != null:
		mm.set("strike_preview", Vector4.ZERO)
	hud.call("orbital_targeting_shown", false, 0)
	if not get_tree().paused:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _set_frozen(on: bool) -> void:
	var m: Node = arena.get("player_mech") if arena != null else null
	var src: Node = m.get("_input_source") if m != null and is_instance_valid(m) else null
	if src != null and "frozen" in src:
		src.set("frozen", on)

## The ground point under a minimap position (world XZ), pulled inside `w`'s range.
func _aim(m: Node, w: OrbitalStrike, local: Vector2) -> Vector3:
	var mm: Control = hud.get("minimap")
	var p: Vector3 = mm.call("from_map", local)
	var me := (m as Node3D).global_position
	var d := Vector2(p.x - me.x, p.z - me.z)
	if d.length() > w.range:
		d = d.normalized() * w.range
	return Vector3(me.x + d.x, me.y, me.z + d.y)

func _preview(m: Node) -> void:
	var mm: Node = hud.get("minimap")
	var a := _aim(m, _queue[0], (mm as Control).get_local_mouse_position())
	mm.set("strike_preview", Vector4(a.x, a.z, (_queue[0] as OrbitalStrike).strike_radius, 1.0))

func _input(e: InputEvent) -> void:  # before the HUD controls: the minimap click is ours
	if not _open:
		return
	if e.is_action_pressed("ui_cancel") or (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_RIGHT):
		get_viewport().set_input_as_handled()
		close()
		return
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		var mm: Control = hud.get("minimap")
		if not mm.get_global_rect().has_point(mm.get_global_mouse_position()):
			return  # a click off the map does nothing (no shot wasted)
		get_viewport().set_input_as_handled()
		_click(mm.get_local_mouse_position())

## One click at minimap position `local`: the next orbital strikes there.
## T543: aim BEFORE the pop -- reading _queue[0] after it sent the last orbital of every pull to (0,0,0).
func _click(local: Vector2) -> void:
	var w: OrbitalStrike = _queue[0]
	w.request_strike(_aim(arena.get("player_mech"), w, local))
	_queue.pop_front()
	if _queue.is_empty():
		close()
	else:
		hud.call("orbital_targeting_shown", true, _queue.size())
