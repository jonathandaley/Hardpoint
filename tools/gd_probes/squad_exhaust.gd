extends Node
# T185 probe: a squad that runs out must end in spectate / match end, never another
# 'select next mech' picker. The local player's respawned mechs were never wired to
# Player.on_pawn_destroyed, so only the first death cost a life: after the 5th mech the
# picker came back and the team could never be eliminated (enemy bots just wandered).
# 1v1 SP (a local MP match since T184): the player burns all 5 squad mechs.

func _fail(msg: String) -> void:
	push_error("[probe] squad_exhaust: " + msg)

func _ready() -> void:
	Game.mp_active_match["roster"] = []  # Arena sets up SP from the loadout
	Game.loadout["team_size"] = 1
	var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arena)
	for i in 2:
		await get_tree().process_frame
	if arena.get("_start_pick_open"):  # T187: keep slot 0, as a player would
		arena.get("hud").squad_slot_selected.emit(0)
	for i in 60:
		await get_tree().physics_frame
	var hud: Node = arena.get("hud")
	var player: Node = arena.get("_player")
	var lives0: int = player.get("lives")
	for slot in range(1, 6):
		arena.get("player_mech").take_damage(1e9)
		await get_tree().process_frame
		var picker: Variant = hud.get("_squad_picker")
		var picker_up: bool = picker != null and is_instance_valid(picker)
		if slot < lives0:
			if not picker_up:
				_fail("no picker after mech %d of %d" % [slot, lives0])
				break
			arena.call("_process_pick_next_mech", 1, slot)  # what the picker button does
			for i in 10:
				await get_tree().physics_frame
		elif picker_up:
			_fail("picker shown after the last squad mech died (lives %d)" % player.get("lives"))
	for i in 3:
		await get_tree().process_frame
	if not arena.get("_match_over"):
		_fail("1v1 match did not end when the player's squad ran out (lives %d)" % player.get("lives"))
	print("[probe] squad_exhaust done (lives %d -> %d, over=%s)" % [lives0, player.get("lives"), arena.get("_match_over")])
	get_tree().quit(0)
