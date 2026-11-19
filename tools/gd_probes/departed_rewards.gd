extends Node
# T502 probe (user 2026-11-19: "When all your robots are dead when you leave still get rewards. Presumably
# this can only apply to an online server"): on a server with accounts, a signed-in player who leaves
# with the squad spent is still paid into the account at match end; one who leaves with mechs left (a
# bot takes those over) is not kept aside.

var spent := {}  # this node stands in for the Arena (current_scene): Game asks it squad_spent(pid)

func squad_spent(pid: int) -> bool:
	return bool(spent.get(pid, false))

class StubAccounts extends Node:
	var saved := {}
	func profile(email: String) -> Dictionary:
		return saved.get(email, {"pilot_name": "P", "wins": 0, "losses": 0, "elo": 1000, "xp": 0, "level": 1, "coins": 100, "skills": {}})
	func save_profile(email: String, prof: Dictionary) -> void:
		saved[email] = prof

func _fail(msg: String) -> void:
	push_error("[probe] departed_rewards FAIL: " + msg)
	get_tree().quit(1)

func _ready() -> void:
	var stub := StubAccounts.new()
	add_child(stub)
	var keep_srv = Game.account_server
	Game.account_server = stub
	Game.mp_active_match["roster"] = [{"peer_id": 7, "team": 0, "slot_idx": 0, "squad": [], "bot_id": -1},
		{"peer_id": 8, "team": 0, "slot_idx": 1, "squad": [], "bot_id": -1}]
	Game._peer_accounts[7] = "gone@example.invalid"
	Game._peer_accounts[8] = "left_alive@example.invalid"
	spent = {7: true, 8: false}
	Game._on_mp_peer_disconnected(7)
	Game._on_mp_peer_disconnected(8)
	await get_tree().process_frame  # _forget_peer runs deferred
	var bad: Array = []
	if not Game._departed_accounts.has(7):
		bad.append("a player who left with the squad spent wasn't kept for the payout")
	if Game._departed_accounts.has(8):
		bad.append("a player who left with mechs left (a bot fights on) was kept too")
	var stats := [{"peer_id": 7, "team": 0, "coins": 5, "kill_coins": 10, "kills": 1, "pre_elo": 1000},
		{"peer_id": 0, "team": 1, "coins": 0, "kill_coins": 0, "kills": 0, "pre_elo": 1000}]
	Game._update_account_profiles(0, stats)
	var got: Dictionary = stub.saved.get("gone@example.invalid", {})
	if got.is_empty() or int(got.get("coins", 0)) <= 100 or int(got.get("xp", 0)) <= 0:
		bad.append("the departed player's account wasn't paid (%s)" % str(got).left(160))
	if not Game._departed_accounts.is_empty():
		bad.append("the departed list wasn't cleared after the payout")
	Game.account_server = keep_srv
	Game.mp_active_match["roster"] = []
	if not bad.is_empty():
		_fail("; ".join(bad))
		return
	print("[probe] departed_rewards done (coins 100 -> %d, xp %d)" % [int(got.get("coins", 0)), int(got.get("xp", 0))])
	get_tree().quit(0)
