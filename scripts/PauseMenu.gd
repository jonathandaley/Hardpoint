extends CanvasLayer

signal resume_requested
signal quit_requested

func _on_resume_pressed() -> void:
	emit_signal("resume_requested")

func _on_quit_pressed() -> void:
	emit_signal("quit_requested")
