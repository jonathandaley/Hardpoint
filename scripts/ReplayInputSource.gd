class_name ReplayInputSource
extends "res://scripts/InputSource.gd"
# M0.3: deterministic scripted input for the MP autodebug harness.
# Feeds a fixed, tick-indexed input sequence (from a scenario file) so a match
# replays identically every run. A drop-in sibling of PlayerInputSource /
# AIInputSource -- Mech reads nothing raw (V1/V2).
#
# Input spec (untyped Dictionary per V14), set via load_spec():
#   {
#     "keyframes": [   # persistent state; latest keyframe with tick <= now wins
#       {"tick": 0,   "move": [0, 1], "look": [0.4, 0.0], "fire_primary": false,
#                     "fire_secondary": false},
#       {"tick": 120, "move": [1, 0], "look": [0.0, 0.0]}
#     ],
#     "pulses": [      # one-shot edge events (reload / ability / mark / slot N), visible on their tick only
#       {"tick": 60, "action": "reload"},
#       {"tick": 90, "action": "slot", "slot": 1}
#     ]
#   }
# look is the per-tick look delta applied while the keyframe is active.

var _keyframes: Array = []   # sorted by tick
var _pulses: Array = []      # sorted by tick; each consumed once
var _tick: int = 0

# Current persistent state, recomputed as keyframes activate.
var _move: Vector2 = Vector2.ZERO
var _look: Vector2 = Vector2.ZERO
var _fire_primary: bool = false
var _fire_secondary: bool = false
var _kf_idx: int = 0
var mech_id: String = ""     # T158: set by Harness so input_press events name the mech

func load_spec(spec: Dictionary) -> void:
	_keyframes = spec.get("keyframes", []).duplicate(true)
	_keyframes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("tick", 0)) < int(b.get("tick", 0)))
	_pulses = spec.get("pulses", []).duplicate(true)
	_pulses.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("tick", 0)) < int(b.get("tick", 0)))
	_tick = 0
	_kf_idx = 0
	_apply_due_keyframes()

func _physics_process(_delta: float) -> void:
	_tick += 1
	_apply_due_keyframes()
	# T158: ground truth for input_delivery -- the moment the "finger" presses.
	for p in _pulses:
		if int(p.get("tick", 0)) == _tick and String(p.get("action", "")) != "mark":
			Game.sync_log_event("input_press", mech_id,
				{"action": String(p["action"]), "slot": int(p.get("slot", -1))})

# Activate every keyframe whose tick has arrived; the last one wins for any
# field it specifies (fields persist across keyframes that omit them).
func _apply_due_keyframes() -> void:
	while _kf_idx < _keyframes.size() and int(_keyframes[_kf_idx].get("tick", 0)) <= _tick:
		var kf: Dictionary = _keyframes[_kf_idx]
		if kf.has("move"):
			_move = Vector2(kf["move"][0], kf["move"][1])
		if kf.has("look"):
			_look = Vector2(kf["look"][0], kf["look"][1])
		if kf.has("fire_primary"):
			_fire_primary = bool(kf["fire_primary"])
		if kf.has("fire_secondary"):
			_fire_secondary = bool(kf["fire_secondary"])
		_kf_idx += 1

# Consume the pulse matching action on its own tick. T158: like
# Input.is_action_just_pressed, a pulse is visible ONLY on its tick; a reader that
# doesn't poll that tick misses it (real keyboard behavior). The old "on or after"
# latch hid the client's every-2nd-tick sampling bug from the harness.
func _take_pulse(action: String) -> Dictionary:
	for p in _pulses:
		var t := int(p.get("tick", 0))
		if t > _tick:
			break
		if t < _tick or p.get("consumed", false):
			continue
		if String(p.get("action", "")) == action:
			p["consumed"] = true
			return p
	return {}

func get_move_direction() -> Vector2:
	return _move

func get_look_delta() -> Vector2:
	return _look

func is_firing_primary() -> bool:
	return _fire_primary

func is_firing_secondary() -> bool:
	return _fire_secondary

func get_slot_toggle() -> int:
	var p := _take_pulse("slot")
	return int(p.get("slot", -1)) if not p.is_empty() else -1

func is_reload_pressed() -> bool:
	return not _take_pulse("reload").is_empty()

func is_ability_pressed() -> bool:
	return not _take_pulse("ability").is_empty()

func is_mark_pressed() -> bool:
	return not _take_pulse("mark").is_empty()

func is_human_input() -> bool:
	return false
