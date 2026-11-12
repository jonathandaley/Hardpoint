extends Node
# T384 probe (V61 / V62): the helpers every piece of client input goes through, and the
# account endpoint's request parsing -- wrong types, markup, oversized values, limits.

func _fail(msg: String) -> void:
	push_error("[probe] net_clean: " + msg)

func _ready() -> void:
	# names
	for c in [["[b]Evil[/b]\nX", "bEvil/bX"], ["  Ace  ", "Ace"], ["A".repeat(500), "A".repeat(16)],
			["\u0007\t", "Pilot"], [5, "Pilot"], [null, "Pilot"], [{"x": 1}, "Pilot"], ["<{\\}>", "Pilot"]]:
		if Game.clean_name(c[0]) != c[1]:
			_fail("clean_name(%s) = '%s', wanted '%s'" % [str(c[0]).left(20).c_escape(), Game.clean_name(c[0]).c_escape(), c[1]])
	# numbers
	for c in [[999999, 4000], [-5, 100], [1500.7, 1500], ["2000", 1000], [null, 1000], [{"a": 1}, 1000], [NAN, 1000], [INF, 1000], [[1], 1000]]:
		if Game.clean_int(c[0], 100, 4000, 1000) != c[1]:
			_fail("clean_int(%s) = %d, wanted %d" % [str(c[0]), Game.clean_int(c[0], 100, 4000, 1000), c[1]])
	# tokens
	for c in [["abc123", "abc123"], ["a".repeat(65), ""], ["x\n[Server] fake", ""], ["a|b", ""], ["", ""]]:
		if Game._clean_token(c[0]) != c[1]:
			_fail("_clean_token(%s) = '%s'" % [String(c[0]).left(12).c_escape(), Game._clean_token(c[0])])
	# paths a server may hand a client
	for c in [["res://resources/maps/MathTemple.tres", true], ["res://scenes/ui/Lobby.tscn", false],
			["res://resources/maps/../mechs/Slip.tres", false], ["user://x.tres", false], [5, false], ["", false]]:
		if Game.safe_res(c[0], "res://resources/maps/", ".tres") != c[1]:
			_fail("safe_res(%s) != %s" % [str(c[0]), c[1]])
	# squads: rebuilt from the hangar's lists, nothing kept as sent
	var slip := "res://resources/mechs/Slip.tres"
	var md = load(slip)
	var light := "res://scenes/weapons/RifleLight.tscn"
	var heavy := "res://scenes/weapons/RifleHeavy.tscn"
	var first_size: int = md.weapon_slots[0].slot_size if "slot_size" in md.weapon_slots[0] else 0
	var fits: String = heavy if first_size == 1 else light
	var misfit: String = light if first_size == 1 else heavy
	var ok: Dictionary = Game.clean_squad_entry({"mech": slip, "weapons": [fits], "junk": "A".repeat(1000), "skills": {"x": 9}})
	if ok.keys() != ["mech", "weapons"] or ok["mech"] != slip or ok["weapons"] != [fits]:
		_fail("an honest entry came back as %s" % ok)
	if Game.clean_squad_entry({"mech": slip, "weapons": []}).is_empty() or Game.clean_squad_entry({"mech": slip, "weapons": [""]}).is_empty():
		_fail("default weapons ([] / '') refused")
	for bad in [{"mech": "res://resources/mechs/DebugMech.tres", "weapons": []}, {"mech": "res://scenes/arena/Arena.tscn", "weapons": []},
			{"mech": slip, "weapons": [misfit]}, {"mech": slip, "weapons": ["res://scenes/ui/Lobby.tscn"]},
			{"mech": slip, "weapons": "x"}, {"mech": slip, "weapons": [5]}, {"mech": 5}, {}, 5, "x", null, [slip]]:
		if not Game.clean_squad_entry(bad).is_empty():
			_fail("squad entry accepted: %s" % str(bad).left(80))
	# rate limit + refusal log cap
	var passed := 0
	for i in 50:
		passed += 1 if Game.net_rate_ok(4242, "probe", 4) else 0
	if passed != 4:
		_fail("net_rate_ok let %d of 50 calls through in one second (limit 4)" % passed)
	Game._forget_peer(4242)
	if Game._refusals.has(4242) or Game._rate.has(4242):
		_fail("_forget_peer left per-peer state behind")
	# skills: bounded by the (clamped) level
	var all := {}
	for k in Game.SKILL_TREE:
		all[k] = 99
	var sk: Dictionary = Game.sanitize_skills(all, 3)
	if sk.size() != 3 or sk.values().max() > 12:
		_fail("sanitize_skills gave a level-3 pilot %s" % sk)

	# ---- account endpoint parsing (handle() with no address = no rate limit) ----
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://accounts.cfg"))
	var srv: Node = load("res://scripts/AccountServer.gd").new()
	add_child(srv)
	srv._tls_opts = null
	var pw := "correct-horse-battery"
	for junk in ['{"op":5}', '{"op":["signup"]}', '{"op":"login","email":5,"password":7}', '{"op":"signup","email":{"a":1},"password":[1],"callsign":{}}',
			'{"op":"unlock_skill","session":5,"key":9}', '{"op":"upgrade_skill","session":null,"key":null}', '[]', '"str"', '5', 'null', '',
			'{'.repeat(3000), '{"op":"login","email":"' + "a".repeat(6000) + '@b.cd","password":"x"}']:
		var r = srv.handle(junk)
		if not r is Dictionary or r.get("ok") != false:
			_fail("junk request %s answered %s" % [junk.left(40), r])
	for e in ["a@b.c]\n[admin@x.y", "x\n[evil]\nk=1\n@b.co", "a\tb@c.de", 'a"@b.cd', "a[b@c.de", "a b@c.de", "a@b", "@b.cd", "a@@b.cd", "a@b..cd"]:
		if srv.handle(JSON.stringify({"op": "signup", "email": e, "password": pw, "callsign": "X"})).get("ok"):
			_fail("signup accepted the email %s" % e.c_escape())
	for e in ["ace@example.com", "first.last+tag@sub.example.co.uk", "A_B-c%d@Example.COM"]:
		if not srv.handle(JSON.stringify({"op": "signup", "email": e, "password": pw, "callsign": "Ok"})).get("ok"):
			_fail("signup refused the ordinary email %s" % e)
	var cs: Dictionary = srv.handle(JSON.stringify({"op": "signup", "email": "cs@example.com", "password": pw, "callsign": "[b]A\nB\u0007[/b]" + "Z".repeat(100)}))
	var nm: String = (cs.get("profile", {}) as Dictionary).get("pilot_name", "")
	if not cs.get("ok") or nm.length() > 16 or nm.contains("[") or nm.contains("\n"):
		_fail("callsign stored as '%s'" % nm.c_escape())
	if srv.handle(JSON.stringify({"op": "login", "email": "ace@example.com", "password": "p".repeat(5000)})).get("ok") != false:
		_fail("oversized password not refused")
	# per-address budgets
	var served := 0
	for i in srv.REQS_PER_MIN + 20:
		if srv.handle("{}", "10.9.9.9").get("error") != "slow down - try again in a minute":
			served += 1
	if served != srv.REQS_PER_MIN:
		_fail("one address got %d requests served in a minute (limit %d)" % [served, srv.REQS_PER_MIN])
	var made := 0
	for i in srv.SIGNUPS_PER_HOUR + 5:
		if srv.handle(JSON.stringify({"op": "signup", "email": "n%d@example.com" % i, "password": pw, "callsign": "N"}), "10.8.8.8").get("ok"):
			made += 1
	if made != srv.SIGNUPS_PER_HOUR:
		_fail("one address made %d accounts in an hour (limit %d)" % [made, srv.SIGNUPS_PER_HOUR])
	if not srv.handle(JSON.stringify({"op": "login", "email": "ace@example.com", "password": pw}), "10.7.7.7").get("ok"):
		_fail("another address was caught by somebody else's budget")
	# files: owner-only
	if OS.get_name() != "Windows":
		srv._lock_down("user://accounts.cfg")
		var mode := FileAccess.get_unix_permissions("user://accounts.cfg")
		if mode & (FileAccess.UNIX_READ_GROUP | FileAccess.UNIX_READ_OTHER | FileAccess.UNIX_WRITE_GROUP | FileAccess.UNIX_WRITE_OTHER) != 0:
			_fail("accounts.cfg is readable by other users (mode %o)" % mode)
	print("[probe] net_clean done")
	get_tree().quit(0)
