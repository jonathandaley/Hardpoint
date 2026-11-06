extends Node
# T294 probe (B109/B110): every weapon script that spawns its own server-side Projectile in
# a _do_fire override also sends client ghosts -- MissileLauncher and MachineGun skipped
# ProjectileGun's T100 send, so MP clients never saw their rounds.

const SENDERS := ["res://scripts/ProjectileGun.gd", "res://scripts/MachineGun.gd", "res://scripts/MissileLauncher.gd",
	"res://scripts/RocketLauncher.gd", "res://scripts/AerialStrike.gd"]

func _ready() -> void:
	var bad: Array = []
	for path in SENDERS:
		var src: String = (load(path) as Script).source_code
		if src.contains("func _do_fire") and src.contains("PROJECTILE_SCENE.instantiate()") and not src.contains("_rpc_spawn_ghost.rpc("):
			bad.append(path.get_file())
	# any other script overriding _do_fire with its own projectile must send ghosts too
	for f in DirAccess.get_files_at("res://scripts"):
		if not f.ends_with(".gd") or ("res://scripts/" + f) in SENDERS:
			continue
		var src: String = (load("res://scripts/" + f) as Script).source_code
		if src.contains("func _do_fire") and src.contains("PROJECTILE_SCENE.instantiate()") and not src.contains("ghost"):
			bad.append(f)
	if not bad.is_empty():
		push_error("[probe] ghost_senders FAIL: no client ghosts from %s" % ", ".join(bad))
		get_tree().quit(1)
		return
	print("[probe] ghost_senders done")
	get_tree().quit(0)
