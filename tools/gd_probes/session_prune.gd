extends Node
# T386 probe: a dedicated server keeps only the newest Game.SESSIONS_KEEP matches of its
# (single, endless) recorded session; anything else keeps every match (the harness, a
# listen server: their sessions end).

func _fail(msg: String) -> void:
	push_error("[probe] session_prune: " + msg)

func _matches(root: String) -> Array:
	var out: Array = []
	if not DirAccess.get_files_at(root).is_empty():
		out.append(1)
	for d in DirAccess.get_directories_at(root):
		if not DirAccess.get_files_at(root.path_join(d)).is_empty():
			out.append(int(d.trim_prefix("match")))
	out.sort()
	return out

func _play(root: String, dedicated: bool, n: int) -> Array:
	DirAccess.make_dir_recursive_absolute(root)
	Game.dedicated = dedicated
	Game._recording = true
	Game._sync_root = ""
	Game._sync_dir = root
	Game._sync_match = 0
	for i in n:
		Game._sync_files_open = true  # as if the match had logged
		Game._sync_next_match()
		FileAccess.open(Game._sync_dir.path_join("server.jsonl"), FileAccess.WRITE).store_string("x")
	Game.dedicated = false
	Game._recording = false
	Game._sync_files_open = false
	return _matches(root)

func _ready() -> void:
	var keep: int = Game.SESSIONS_KEEP
	var got := _play("user://sessions/probe_dedicated", true, 7)
	if got != range(7 - keep + 1, 8):
		_fail("dedicated server kept matches %s of 7 (wanted the newest %d)" % [got, keep])
	got = _play("user://sessions/probe_listen", false, 7)
	if got.size() != 7:
		_fail("a normal session lost matches: %s" % [got])
	Game._rm_tree("user://sessions/probe_dedicated")
	Game._rm_tree("user://sessions/probe_listen")
	print("[probe] session_prune done")
	get_tree().quit(0)
