extends Node
# T207 probe: the account store (AccountServer) -- PBKDF2 vectors, sign-up rules, wrong
# passwords + lockout, nothing password-shaped on disk, sessions -- and a real TLS round
# trip through Game.account_request.

func _fail(msg: String) -> void:
	push_error("[probe] accounts: " + msg)

func _req(srv: Node, d: Dictionary) -> Dictionary:
	return srv.handle(JSON.stringify(d))

func _ready() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://accounts.cfg"))
	var A: Script = load("res://scripts/AccountServer.gd")
	# RFC 6070-style PBKDF2-HMAC-SHA256 vectors (= Python hashlib.pbkdf2_hmac)
	var vec := {1: "120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b",
		4096: "c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a"}
	for c in vec:
		if A.pbkdf2_sha256("password".to_utf8_buffer(), "salt".to_utf8_buffer(), c).hex_encode() != vec[c]:
			_fail("PBKDF2 c=%d does not match the reference vector" % c)
	var srv: Node = A.new()
	add_child(srv)
	if not srv.start(8960):
		_fail("account endpoint did not start")
	var pw := "hunter2-but-longer"
	var r := _req(srv, {"op": "signup", "email": "Ace@Example.com", "password": pw, "callsign": "Ace"})
	if not r.get("ok") or String(r.get("session", "")).length() != 64 or r["profile"].get("pilot_name") != "Ace":
		_fail("signup failed: %s" % r)
	var ace_session: String = r.get("session", "")
	for bad in [{"email": "ace@example.com", "password": pw, "callsign": "X", "why": "duplicate email"},
			{"email": "b@example.com", "password": "short", "callsign": "B", "why": "short password"},
			{"email": "not-an-email", "password": pw, "callsign": "C", "why": "bad email"},
			{"email": "d@example.com", "password": pw, "callsign": "", "why": "no callsign"}]:
		var why: String = bad["why"]
		bad.erase("why")
		bad["op"] = "signup"
		if _req(srv, bad).get("ok"):
			_fail("signup accepted a %s" % why)
	_req(srv, {"op": "signup", "email": "bob@example.com", "password": pw, "callsign": "Bob"})
	# login: wrong password refused; right one works; LOCK_AFTER misses lock it out
	if _req(srv, {"op": "login", "email": "ace@example.com", "password": "nope-nope"}).get("ok"):
		_fail("wrong password accepted")
	if not _req(srv, {"op": "login", "email": "ACE@example.com ", "password": pw}).get("ok"):
		_fail("right password (email case/space) refused")
	for i in srv.LOCK_AFTER:
		_req(srv, {"op": "login", "email": "ace@example.com", "password": "nope-nope"})
	if _req(srv, {"op": "login", "email": "ace@example.com", "password": pw}).get("ok"):
		_fail("no lockout after %d wrong passwords" % srv.LOCK_AFTER)
	# disk: salt + hash only, salts differ
	var text := FileAccess.get_file_as_string("user://accounts.cfg")
	if text.contains(pw) or text.contains(Marshalls.utf8_to_base64(pw)) or text.to_lower().contains(pw.sha256_text()):
		_fail("the store holds the password (or its plain hash)")
	var cfg := ConfigFile.new()
	cfg.load("user://accounts.cfg")
	if cfg.get_value("ace@example.com", "salt") == cfg.get_value("bob@example.com", "salt"):
		_fail("two accounts share a salt")
	# sessions
	if srv.email_for(ace_session) != "ace@example.com" or srv.email_for("f".repeat(64)) != "":
		_fail("session lookup wrong")
	# TLS round trip, the client path the Account screen uses
	var reply: Dictionary = await Game.account_request("127.0.0.1", 8959, {"op": "login", "email": "bob@example.com", "password": pw})
	if not reply.get("ok") or reply["profile"].get("pilot_name") != "Bob":
		_fail("TLS login round trip failed: %s" % reply)
	var wrong: Dictionary = await Game.account_request("127.0.0.1", 8959, {"op": "login", "email": "bob@example.com", "password": "x" + pw})
	if wrong.get("ok") or wrong.get("error", "") != "wrong email or password":
		_fail("TLS wrong-password reply: %s" % wrong)
	# T213: skills on the account, by the game's rules, over TLS
	var own_skills: Dictionary = (Game.profile.get("skills", {}) as Dictionary).duplicate()
	var sess: String = reply.get("session", "")
	var key: String = Game.SKILL_TREE.keys()[0]
	for k in Game.SKILL_TREE:
		if (Game.SKILL_TREE[k] as Dictionary).get("parents", []).is_empty():
			key = k
			break
	var u: Dictionary = await Game.account_request("127.0.0.1", 8959, {"op": "unlock_skill", "session": sess, "key": key})
	if not u.get("ok") or int(u["profile"]["skills"].get(key, 0)) != 1 or int(srv.profile("bob@example.com")["skills"].get(key, 0)) != 1:
		_fail("unlock_skill on the account failed: %s" % u)
	var again: Dictionary = await Game.account_request("127.0.0.1", 8959, {"op": "unlock_skill", "session": sess, "key": key})
	if again.get("ok"):
		_fail("unlocked the same skill twice (level-1 account has 1 point)")
	var up: Dictionary = await Game.account_request("127.0.0.1", 8959, {"op": "upgrade_skill", "session": sess, "key": key})
	if up.get("ok"):
		_fail("upgrade with 0 coins accepted")
	var forged: Dictionary = await Game.account_request("127.0.0.1", 8959, {"op": "unlock_skill", "session": "0".repeat(64), "key": key})
	if forged.get("ok"):
		_fail("skill op accepted without a valid session")
	if Game.profile.get("skills", {}) != own_skills:
		_fail("the server's own profile picked up the account's skill (borrow not restored)")
	print("[probe] accounts done")
	get_tree().quit(0)
