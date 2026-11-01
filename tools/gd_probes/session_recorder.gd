extends Node
# T157 probe: hosting a real MP session (no --sync-log) records to user://sessions/<stamp>/,
# keeps only the newest Game.SESSIONS_KEEP sessions, and stops when the session ends.

func _ready() -> void:
	var root: String = Game.SESSIONS_DIR
	for i in 4:
		DirAccess.make_dir_recursive_absolute(root.path_join("2000-01-0%d_000000" % (i + 1)))
	Game.host(8990)
	if not (Game._recording and Game.sync_logging_enabled and String(Game._sync_dir).begins_with(root)):
		push_error("[probe] session_recorder: hosting did not start recording")
	var kept := DirAccess.get_directories_at(root).size()
	if kept != Game.SESSIONS_KEEP:
		push_error("[probe] session_recorder: %d session dirs kept, want %d" % [kept, Game.SESSIONS_KEEP])
	Game.disconnect_mp()
	if Game._recording or Game.sync_logging_enabled:
		push_error("[probe] session_recorder: recording survived disconnect_mp")
	print("[probe] session_recorder done")
	get_tree().quit(0)
