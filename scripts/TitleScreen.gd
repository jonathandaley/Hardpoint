extends Control

var _blink_time: float = 0.0

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _process(delta: float) -> void:
	_blink_time += delta
	$PressEnter.visible = fmod(_blink_time, 1.0) < 0.7

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ENTER:
		get_tree().change_scene_to_file("res://scenes/ui/SignIn.tscn")
