extends Node
# Records mech positions during a match, writes a CSV, and prints a per-mech
# analysis summary (distance, stuck %) when the match ends.
#
# Usage:
#   MovementLogger.start_session()     # call when match starts
#   MovementLogger.stop_and_analyze()  # call when match ends or is quit

const SAMPLE_INTERVAL := 0.25  # seconds between position samples
const STUCK_SPEED     := 0.5   # m/s - horizontal speed below this counts as stuck
const LOG_DIR         := "user://movement_logs/"

var _active:  bool  = false
var _samples: Array = []   # Array[Dictionary]
var _timer:   float = 0.0

func _notification(what: int) -> void:
	# Flush log if the window is closed mid-match.
	if what == NOTIFICATION_WM_CLOSE_REQUEST and _active:
		stop_and_analyze()

func start_session() -> void:
	_samples.clear()
	_timer  = 0.0
	_active = true
	print("[MovementLogger] Recording started.")

func stop_and_analyze() -> void:
	if not _active:
		return
	_active = false
	if _samples.is_empty():
		print("[MovementLogger] No samples collected.")
		return
	var path := _write_csv()
	_print_analysis(path)

func _process(delta: float) -> void:
	if not _active:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = SAMPLE_INTERVAL
	var t: float = Time.get_ticks_msec() / 1000.0
	for mech in get_tree().get_nodes_in_group("mechs"):
		if not is_instance_valid(mech) or not mech.visible:
			continue
		var src: Node = mech.get("_input_source") as Node
		var is_bot: bool = src == null or not src.is_human_input()
		var vel: Vector3 = mech.velocity
		_samples.append({
			"t":      snappedf(t, 0.01),
			"mech":   mech.name,
			"team":   int(mech.get("team")),
			"is_bot": is_bot,
			"x":      snappedf(mech.global_position.x, 0.01),
			"y":      snappedf(mech.global_position.y, 0.01),
			"z":      snappedf(mech.global_position.z, 0.01),
			"speed":  snappedf(Vector2(vel.x, vel.z).length(), 0.01),
		})

func _write_csv() -> String:
	DirAccess.make_dir_recursive_absolute(LOG_DIR)
	var dt := Time.get_datetime_string_from_system().replace(":", "-")
	var path := LOG_DIR + "movement_%s.csv" % dt
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("[MovementLogger] Cannot open %s for writing" % path)
		return path
	file.store_line("t,mech,team,is_bot,x,y,z,speed")
	for s in _samples:
		file.store_line("%.2f,%s,%d,%d,%.2f,%.2f,%.2f,%.2f" % [
			s.t, s.mech, s.team, 1 if s.is_bot else 0,
			s.x, s.y, s.z, s.speed,
		])
	file.close()
	print("[MovementLogger] Saved %d samples → %s" % [_samples.size(), path])
	return path

func _print_analysis(path: String) -> void:
	# Group samples by mech name.
	var by_mech: Dictionary = {}
	for s in _samples:
		if not by_mech.has(s.mech):
			by_mech[s.mech] = {"is_bot": s.is_bot, "team": s.team, "rows": []}
		by_mech[s.mech].rows.append(s)

	print("[MovementLogger] === Post-match movement analysis (log: %s) ===" % path)
	for mech_name in by_mech:
		var entry: Dictionary = by_mech[mech_name]
		var rows: Array = entry.rows
		var n := rows.size()
		if n == 0:
			continue

		# Total horizontal distance (sum of position deltas between samples).
		var total_dist := 0.0
		for i in range(1, n):
			var dx: float = rows[i].x - rows[i - 1].x
			var dz: float = rows[i].z - rows[i - 1].z
			total_dist += sqrt(dx * dx + dz * dz)

		# Stuck samples: horizontal speed below threshold.
		var stuck := 0
		for row in rows:
			if row.speed < STUCK_SPEED:
				stuck += 1
		var stuck_pct := 100.0 * stuck / n

		var label := "BOT   " if entry.is_bot else "PLAYER"
		print("  [T%d %s] %-20s  dist=%6.1f m  stuck=%5.1f%% (%d/%d samples)" % [
			entry.team, label, mech_name, total_dist, stuck_pct, stuck, n,
		])
	print("[MovementLogger] ==============================================")
