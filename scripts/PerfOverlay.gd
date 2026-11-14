extends CanvasLayer

# T420: the browser speed check (page address ...index.html?perf). Turns on the T165 per-system
# timers and every 5 s shows (and prints to the browser console) one line: frames per second,
# average / worst frame ms, proc_max / phys_max (Godot's monitors: the SLOWEST frame / physics tick
# of the last second, not averages -- a death spike shows there), draw calls, whether the mouse is
# locked, then avg/max ms per system per physics tick. tick = all scripts' physics work in one tick
# (first to last _physics_process); the engine's own physics step is not in it.
# Render time on the graphics card is not counted separately: it shows up in the frame ms.

const WINDOW_S := 5.0
var _label := Label.new()
var _t := 0.0
var _frames := 0
var _worst := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100
	Game.prof_on = true
	_label.position = Vector2(4, 4)
	_label.add_theme_font_size_override("font_size", 10)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 3)
	add_child(_label)
	process_physics_priority = -1000000
	var end := _TickEnd.new()
	end.process_mode = Node.PROCESS_MODE_ALWAYS
	end.process_physics_priority = 1000000
	end.started = func() -> int: return _tick_t0
	add_child(end)

var _tick_t0 := 0

class _TickEnd extends Node:  # runs after every other _physics_process (priority)
	var started: Callable
	func _physics_process(_d: float) -> void:
		Game.prof_add("tick", Time.get_ticks_usec() - int(started.call()))

func _physics_process(_delta: float) -> void:
	Game.prof_end_frame()  # closes the previous tick
	_tick_t0 = Time.get_ticks_usec()

var autopick := false  # ?perf&sp: take mech 0 at spawn 0 (SP pauses while the picker is open)

func _process(delta: float) -> void:
	var arena := get_tree().current_scene
	if autopick and arena != null and arena.get("_start_pick_open"):
		arena.get("hud").squad_slot_selected.emit(0)
		arena.get("hud").spawn_selected.emit(0)
	_t += delta
	_frames += 1
	_worst = maxf(_worst, delta)
	if _t < WINDOW_S:
		return
	var parts: Array = ["fps=%.0f frame=%.1f/%.1fms proc_max=%.2fms phys_max=%.2fms draws=%d" % [_frames / _t,
		_t * 1000.0 / _frames, _worst * 1000.0, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)]
		+ (" mouse=locked" if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else " mouse=free")]
	var prof: Dictionary = Game.prof_take()
	for k in prof:  # avg/max ms per physics frame
		var e: Array = prof[k]
		parts.append("%s=%.2f/%.2f" % [k, float(e[0]) / maxi(e[2], 1) / 1000.0, float(e[1]) / 1000.0])
	_label.text = "\n".join(parts)
	print("[Perf] ", " ".join(parts))
	_t = 0.0
	_frames = 0
	_worst = 0.0
