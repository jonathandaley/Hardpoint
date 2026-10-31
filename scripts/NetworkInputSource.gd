class_name NetworkInputSource
extends "res://scripts/InputSource.gd"

# Server-side input buffer for a remote peer's mech.
# T118 _rpc_input handler calls push_input() after sender validation (V41).
# All getters consume one-shot fields on read (matches PlayerInputSource contract).

var _move_dir: Vector2 = Vector2.ZERO
var _abs_aim = null  # Vector2(yaw, pitch) from the owning client; null until first packet (V47)
var _fire_primary: bool = false
var _fire_secondary: bool = false
var _slot_toggle: int = -1
var _reload: bool = false
var _ability: bool = false
var _last_presses: Array = [0, 0, 0, 0, 0, 0]  # T158: last cumulative counts seen

func push_input(payload: Dictionary) -> void:
	_move_dir = payload.get("move", Vector2.ZERO)
	# V47: aim arrives absolute (latest wins), so a lost packet is healed by the next
	# one and the server's own sensitivity never touches it. V41: untrusted input.
	var aim = payload.get("aim")
	if aim is Vector2 and aim.is_finite():
		_abs_aim = aim
	_fire_primary = payload.get("fire_prim", false)
	_fire_secondary = payload.get("fire_sec", false)
	# T158/V47: one-shots arrive as cumulative press counts [reload, ability, slot0..3];
	# new presses = diff vs the last packet, so a lost packet is healed by the next.
	# ponytail: presses closer than one packet (2 ticks) collapse -- one reload, and a
	# double-tapped slot toggles by parity; humans can't press faster than that.
	var c = payload.get("presses")
	if not (c is Array and c.size() == 6):
		return
	for i in 6:
		if typeof(c[i]) != TYPE_INT:
			return  # V41: malformed, drop the whole update
	for i in 6:
		var n: int = c[i] - int(_last_presses[i])
		if n <= 0:
			continue
		if i == 0:
			_reload = true
		elif i == 1:
			_ability = true
		elif n % 2 == 1:
			_slot_toggle = i - 2
	_last_presses = c.duplicate()

func get_move_direction() -> Vector2:
	return _move_dir

func get_look_delta() -> Vector2:
	return Vector2.ZERO  # remote aim is absolute, see get_abs_aim()

func get_abs_aim():
	return _abs_aim

func is_firing_primary() -> bool:
	return _fire_primary

func is_firing_secondary() -> bool:
	return _fire_secondary

func get_slot_toggle() -> int:
	var t := _slot_toggle
	_slot_toggle = -1
	return t

func is_reload_pressed() -> bool:
	var r := _reload
	_reload = false
	return r

func is_ability_pressed() -> bool:
	var a := _ability
	_ability = false
	return a

func is_human_input() -> bool:
	return true
