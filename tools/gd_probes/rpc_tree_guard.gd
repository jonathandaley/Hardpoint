extends Node
# V50 / B130 probe (dedicated_server@bad crash_scan: "Cannot call method 'is_server' on a null
# value" in AerialStrike._rpc_spawn_ghost -- a burst's ghost RPC reached a weapon whose mech had
# already left the client's tree, where `multiplayer` is null): every @rpc handler in scripts/
# that uses `multiplayer` checks is_inside_tree() first (or before touching it).

func _ready() -> void:
	var bad: Array = []
	for f in DirAccess.get_files_at("res://scripts"):
		if not f.ends_with(".gd"):
			continue
		var lines: PackedStringArray = (load("res://scripts/" + f) as Script).source_code.split("\n")
		var i := 0
		while i < lines.size():
			if lines[i].begins_with("@rpc"):
				var j := i + 1
				while j < lines.size() and not lines[j].begins_with("func "):
					j += 1
				var name := lines[j].get_slice("(", 0).trim_prefix("func ") if j < lines.size() else "?"
				var k := j + 1
				while k < lines.size() and (lines[k].begins_with("\t\t") or lines[k].strip_edges() == ""):  # a wrapped signature
					k += 1
				# the body up to the first use of `multiplayer`: is the tree checked before it?
				var guarded := false
				while k < lines.size() and lines[k].begins_with("\t"):
					if lines[k].contains("is_inside_tree"):
						guarded = true
					if lines[k].contains("multiplayer.") and not guarded:
						bad.append("%s %s uses multiplayer before is_inside_tree()" % [f, name])
						break
					k += 1
				i = k
			else:
				i += 1
	if not bad.is_empty():
		push_error("[probe] rpc_tree_guard FAIL: " + "; ".join(bad))
		get_tree().quit(1)
		return
	print("[probe] rpc_tree_guard done")
	get_tree().quit(0)
