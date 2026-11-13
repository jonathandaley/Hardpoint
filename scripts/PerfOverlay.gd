extends CanvasLayer

# T420: the browser speed check (page address ...index.html?perf). Turns on the T165 per-system
# timers and every 5 s shows (and prints to the browser console) one line: frames per second,
# average / worst frame ms, process + physics ms, then avg/max ms per system.
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

func _physics_process(_delta: float) -> void:
	Game.prof_end_frame()

func _process(delta: float) -> void:
	_t += delta
	_frames += 1
	_worst = maxf(_worst, delta)
	if _t < WINDOW_S:
		return
	var parts: Array = ["fps=%.0f frame=%.1f/%.1fms process=%.2fms physics=%.2fms draws=%d" % [_frames / _t,
		_t * 1000.0 / _frames, _worst * 1000.0, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)]]
	var prof: Dictionary = Game.prof_take()
	for k in prof:  # avg/max ms per physics frame
		var e: Array = prof[k]
		parts.append("%s=%.2f/%.2f" % [k, float(e[0]) / maxi(e[2], 1) / 1000.0, float(e[1]) / 1000.0])
	_label.text = "\n".join(parts)
	print("[Perf] ", " ".join(parts))
	_t = 0.0
	_frames = 0
	_worst = 0.0
