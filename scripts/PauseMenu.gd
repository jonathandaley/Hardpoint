extends CanvasLayer

signal resume_requested
signal quit_requested

# T161: Esc while paused. Arena is pausable, so it no longer sees input while the
# tree is paused; this CanvasLayer runs PROCESS_MODE_ALWAYS.
func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		emit_signal("resume_requested")

func _on_resume_pressed() -> void:
	emit_signal("resume_requested")

func _on_quit_pressed() -> void:
	emit_signal("quit_requested")
