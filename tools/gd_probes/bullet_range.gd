extends Node
# T246 probe (HUMAN_FOUND_ISSUES 2026-11-05 note: "Bullets don't disappear after reaching
# max range?"): every projectile weapon, fired into open sky, frees each shot by the time it
# has flown its weapon's range (a 15% + 3 m margin) and none outlive range / speed + 0.5 s.
# Re-arming one mech weapon after weapon also guards B102 (configure_weapons twice in a
# frame left a freed weapon in the list: every second weapon fired nothing).

const SlotDef := preload("res://scripts/WeaponSlotDef.gd")
const HOMING := preload("res://scripts/HomingProjectile.gd")
const NEEDS_LOCK := ["RocketLauncherLight", "AerialStrikeHeavy"]  # fire only at a locked target: same lifetime code, not fired here
const WEAPONS := ["RifleLight", "RifleHeavy", "SniperLight", "SniperHeavy", "MachineGunLight", "MachineGunHeavy",
	"ShotgunLight", "ShotgunHeavy", "MissileLauncherLight", "MissileLauncherHeavy", "PatienceHeavy",
	"RocketLauncherLight", "AerialStrikeHeavy"]

class AimSrc extends "res://scripts/InputSource.gd":
	var aim := Vector2.ZERO
	var firing := false
	func get_abs_aim():
		return aim
	func is_firing_primary() -> bool:
		return firing

func _fail(msg: String) -> void:
	push_error("[probe] bullet_range: " + msg)

func _shots(arena: Node) -> Array:
	return arena.get_children().filter(func(n): return n is Projectile or n.get_script() == HOMING)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Game.mp_active_match["roster"] = []
	Game.loadout["team_size"] = 1
	var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arena)
	for i in 2:
		await get_tree().process_frame
	get_tree().current_scene = arena  # shots go under the current scene
	if arena.get("_start_pick_open"):
		arena.get("hud").squad_slot_selected.emit(0)
		arena.get("hud").spawn_selected.emit(0)
	for i in 10:
		await get_tree().physics_frame
	for t in 2:
		for m in arena.get("_team_mechs")[t]:
			m.invincible = true
			if m != arena.get("player_mech"):
				m.process_mode = Node.PROCESS_MODE_DISABLED
	var me: CharacterBody3D = arena.get("player_mech")
	var src := AimSrc.new()
	me.add_child(src)
	me.set_input_source(src)
	src.aim = Vector2(0.0, 0.4)  # pitched up: open sky above the arena
	var report: Array = []
	for wname in WEAPONS:
		var scene: PackedScene = load("res://scenes/weapons/%s.tscn" % wname)
		var probe_w: Node = scene.instantiate()
		var slot := SlotDef.new()
		slot.slot_size = int(probe_w.get("slot_size"))
		slot.position = Vector3(0, 2.0, 0)
		slot.weapon_scene = scene
		var rng: float = float(probe_w.get("range"))
		var spd: float = float(probe_w.get("projectile_speed"))
		probe_w.free()
		me.configure_weapons([slot])
		for i in 5:
			await get_tree().physics_frame
		var born := {}  # shot -> spawn position
		var far := 0.0
		src.firing = true
		var fire_ticks := 30
		var watch := int((rng / maxf(spd, 1.0) + 0.5) * 60.0) + fire_ticks  # the last shot's whole flight + 0.5 s
		var i := 0
		while i < watch:
			await get_tree().physics_frame
			i += 1
			if i == fire_ticks:
				src.firing = false
			var live := _shots(arena)
			for s in live:
				if not born.has(s):
					born[s] = (s as Node3D).global_position
				far = maxf(far, (s as Node3D).global_position.distance_to(born[s]))
			if i > fire_ticks and live.is_empty():
				break  # all gone: no need to sit out the window
		var left := _shots(arena).size()
		report.append("%s %d shots max %.0f/%.0f m" % [wname, born.size(), far, rng])
		if born.is_empty():
			report[-1] += " (no shot)"
			if not NEEDS_LOCK.has(wname):  # B102: every second re-arm left the mech a freed weapon
				_fail("%s fired no shots after configure_weapons" % wname)
		if left > 0:
			_fail("%s: %d shots still alive %.1f s after firing stopped (range %.0f m, speed %.0f)" % [wname, left, (i - fire_ticks) / 60.0, rng, spd])
			for s in _shots(arena):
				s.queue_free()
		if far > rng * 1.15 + 3.0:
			_fail("%s: a shot flew %.0f m, range is %.0f m" % [wname, far, rng])
	print("[probe] bullet_range done (%s)" % "; ".join(report))
	get_tree().quit(0)
