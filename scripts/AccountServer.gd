extends Node
# T207: accounts on the dedicated server (Game.start_dedicated adds this node).
# Endpoint: TCP + TLS on game port + 1, one JSON request line -> one JSON reply line:
#   {"op": "signup", "email", "password", "callsign"} / {"op": "login", "email", "password"}
#   -> {"ok": true, "session": <token>, "profile": {...}} | {"ok": false, "error": <text>}
# Passwords: PBKDF2-HMAC-SHA256 (PBKDF2_ITER rounds, 16-byte random salt per account),
# compared in constant time; only salt + hash are stored (user://accounts.cfg), never the
# password, and nothing password-shaped is logged. LOCK_AFTER failed logins lock that
# email for LOCK_S. Sessions: random 32-byte tokens in memory (SESSION_S), presented in
# the game's auth handshake (Game._on_mp_auth) to tie a peer to its account.
# ponytail: self-signed certificate (generated once, user://account_tls.*) and clients
# connect with TLSOptions.client_unsafe(): encrypted, but no protection against a
# man in the middle until the server has a real certificate (NEEDS_HUMAN). Sessions die
# with the server process.

const PBKDF2_ITER := 100000  # ~0.3 s here; each account stores its own count, old ones keep theirs
const LOCK_AFTER := 5
const LOCK_S := 60.0
const SESSION_S := 7 * 24 * 3600.0
const STORE := "user://accounts.cfg"
const KEY_PATH := "user://account_tls.key"
const CERT_PATH := "user://account_tls.crt"
const MAX_LINE := 4096
const ERR_SESSION := "sign in again"  # T403: clients sign out on it (Game._session_lost); never reword
# T384 (V62): what one address may do. Requests are cheap to send and each login / sign-up
# costs us a password hash, so they are counted per address BEFORE any work is done.
const MAX_CONNS := 256           # open connections in total; beyond that new ones are closed
const MAX_CONNS_PER_ADDR := 8
const REQS_PER_MIN := 60         # per address
const SIGNUPS_PER_HOUR := 10     # per address (calibration knob: a household behind one router)
const MAX_ACCOUNTS := 100000     # the store is one file rewritten on every change
const CONN_TIMEOUT_MS := 10000

var _hits: Dictionary = {}       # address -> {"req": [window start s, n], "signup": [window start s, n]}
var _email_re := RegEx.create_from_string("^[a-z0-9._%+-]{1,64}@[a-z0-9-]{1,63}(\\.[a-z0-9-]{1,63}){1,8}$")
var _tcp := TCPServer.new()
var _tls_opts: TLSOptions = null
var _conns: Array = []          # [{tls, buf, t}]
var _sessions: Dictionary = {}  # token -> {email, exp}
# T385: the game connection is not encrypted (T212), so a session never goes on it. A
# signed-in client asks HERE (TLS) for a join ticket -- random, single use, TICKET_S -- and
# puts that in its hello; whoever reads the hello off the wire holds a ticket already spent.
const TICKET_S := 60.0
var _tickets: Dictionary = {}   # ticket -> {email, exp}
var _fails: Dictionary = {}     # email -> {n, until}
var _store := ConfigFile.new()
var _mx := Mutex.new()          # requests run on a worker thread (PBKDF2 ~60 ms); store, sessions, fails shared

func start(port: int) -> bool:
	_store.load(STORE)
	_lock_down(STORE)
	_tls_opts = TLSOptions.server(_load_or_make_key(), _load_or_make_cert())
	if _tcp.listen(port) != OK:
		push_error("[Accounts] cannot listen on %d" % port)
		return false
	print("[Accounts] TLS account endpoint on port %d (%d accounts)" % [port, _store.get_sections().size()])
	return true

func _load_or_make_key() -> CryptoKey:
	var key := CryptoKey.new()
	if FileAccess.file_exists(KEY_PATH) and key.load(KEY_PATH) == OK:
		return key
	key = Crypto.new().generate_rsa(2048)
	key.save(KEY_PATH)
	_lock_down(KEY_PATH)
	return key

## Write-then-rename: a crash or power cut in the middle of a save must leave the old
## account file, not half of the new one (the store is every account there is). Caller
## holds _mx.
func _save_store() -> void:
	var tmp := STORE + ".tmp"
	if _store.save(tmp) != OK:
		push_error("[Accounts] could not write %s" % tmp)
		return
	_lock_down(tmp)
	if DirAccess.rename_absolute(tmp, STORE) != OK:
		push_error("[Accounts] could not replace %s" % STORE)

## Owner-only (0600): the TLS private key and the account store are not for other users
## of the machine to read.
func _lock_down(path: String) -> void:
	if FileAccess.file_exists(path) and OS.get_name() != "Windows":
		FileAccess.set_unix_permissions(path, FileAccess.UNIX_READ_OWNER | FileAccess.UNIX_WRITE_OWNER)

## false = this address is over its budget for `kind` ("req" per minute, "signup" per hour).
func _within(addr: String, kind: String, limit: int, window_s: float) -> bool:
	if addr == "":
		return true  # in-process caller (the probe)
	var now := Time.get_ticks_msec() * 0.001
	_mx.lock()
	if _hits.size() > 20000:  # ponytail: drop the lot when it gets big; a per-entry expiry if that ever bites
		_hits.clear()
	var h: Dictionary = _hits.get(addr, {})
	var w: Array = h.get(kind, [now, 0])
	if now - float(w[0]) >= window_s:
		w = [now, 0]
	w[1] = int(w[1]) + 1
	h[kind] = w
	_hits[addr] = h
	_mx.unlock()
	return int(w[1]) <= limit

func _load_or_make_cert() -> X509Certificate:
	var cert := X509Certificate.new()
	if FileAccess.file_exists(CERT_PATH) and cert.load(CERT_PATH) == OK:
		return cert
	var key := CryptoKey.new()
	key.load(KEY_PATH)
	cert = Crypto.new().generate_self_signed_certificate(key, "CN=hardpoint,O=Hardpoint,C=US")
	cert.save(CERT_PATH)
	return cert

func _process(_delta: float) -> void:
	while _tcp.is_connection_available():
		var tcp := _tcp.take_connection()
		var addr := tcp.get_connected_host()
		var from_addr := 0
		for c in _conns:
			from_addr += 1 if c["addr"] == addr else 0
		if _conns.size() >= MAX_CONNS or from_addr >= MAX_CONNS_PER_ADDR:
			tcp.disconnect_from_host()  # V62: before the TLS handshake costs anything
			continue
		var tls := StreamPeerTLS.new()
		if tls.accept_stream(tcp, _tls_opts) == OK:
			_conns.append({"tls": tls, "buf": PackedByteArray(), "t": Time.get_ticks_msec(), "addr": addr})
	for c in _conns.duplicate():
		var tls: StreamPeerTLS = c["tls"]
		tls.poll()
		var st := tls.get_status()
		if st == StreamPeerTLS.STATUS_CONNECTED and tls.get_available_bytes() > 0:
			c["buf"].append_array(tls.get_data(tls.get_available_bytes())[1])
		if c.has("task"):  # hashing off the game thread
			if WorkerThreadPool.is_task_completed(c["task"]):
				WorkerThreadPool.wait_for_task_completion(c["task"])
				tls.put_data((JSON.stringify(c["reply"][0]) + "\n").to_utf8_buffer())
				tls.poll()
				tls.disconnect_from_stream()
				_conns.erase(c)
			continue
		var nl: int = (c["buf"] as PackedByteArray).find(10)
		if nl >= 0 and _is_skill_op(c["buf"].slice(0, nl).get_string_from_utf8()):
			# T213: skill ops borrow Game's rules (Game.profile) -> main thread; no hashing
			tls.put_data((JSON.stringify(handle(c["buf"].slice(0, nl).get_string_from_utf8(), c["addr"])) + "\n").to_utf8_buffer())
			tls.poll()
			tls.disconnect_from_stream()
			_conns.erase(c)
		elif nl >= 0:
			var line: String = c["buf"].slice(0, mini(nl, MAX_LINE)).get_string_from_utf8()
			var addr: String = c["addr"]
			var out := [null]
			c["reply"] = out
			c["task"] = WorkerThreadPool.add_task(func() -> void: out[0] = handle(line, addr))
		elif st != StreamPeerTLS.STATUS_HANDSHAKING and st != StreamPeerTLS.STATUS_CONNECTED \
				or (c["buf"] as PackedByteArray).size() > MAX_LINE or Time.get_ticks_msec() - int(c["t"]) > CONN_TIMEOUT_MS:
			tls.disconnect_from_stream()
			_conns.erase(c)

const SKILL_OPS := ["unlock_skill", "upgrade_skill"]

## JSON -> Dictionary or null. The engine's parser logs an error line per bad document;
## an instance reports through its own fields instead (V62: no log line per junk request).
static func _parse(line: String):
	var j := JSON.new()
	return j.data if line.length() <= MAX_LINE and j.parse(line) == OK else null

## A text field of a request: a String as sent, or "" for anything else (V62: a client's
## JSON can hold any type anywhere -- never String(x) / int(x) a field that might not be one).
static func _s(req: Dictionary, key: String) -> String:
	var v = req.get(key)
	return v if v is String else ""

func _is_skill_op(line: String) -> bool:
	var req = _parse(line)
	return req is Dictionary and _s(req, "op") in SKILL_OPS

# One request (a JSON line from an untrusted client at `addr`) -> reply. Public for the
# probe, which passes no address (no rate limits).
func handle(line: String, addr: String = "") -> Dictionary:
	if not _within(addr, "req", REQS_PER_MIN, 60.0):
		return _err("slow down - try again in a minute")
	var req = _parse(line)
	if not req is Dictionary:
		return _err("bad request")
	var op := _s(req, "op")
	if op in SKILL_OPS:  # T213: {op, session, key}; main thread only
		var who := email_for(_s(req, "session"))
		if who == "":
			return _err(ERR_SESSION)
		var after: Dictionary = Game.skill_op_on(profile(who), op, _s(req, "key"))
		if after.is_empty():
			return _err("not enough points or coins")
		save_profile(who, after)
		return {"ok": true, "profile": after}
	if op == "ticket":  # T385: {op, session} -> {ok, ticket}
		var who := email_for(_s(req, "session"))
		if who == "":
			return _err(ERR_SESSION)
		var ticket := Crypto.new().generate_random_bytes(32).hex_encode()
		_mx.lock()
		if _tickets.size() > 2000:
			_tickets.clear()  # ponytail: unused tickets die after TICKET_S anyway; the asker just asks again
		_tickets[ticket] = {"email": who, "exp": Time.get_unix_time_from_system() + TICKET_S}
		_mx.unlock()
		return {"ok": true, "ticket": ticket}
	var email := _s(req, "email").strip_edges().to_lower()
	var password := _s(req, "password")
	if not _valid_email(email):
		return _err("enter a valid email address")
	match op:
		"signup":
			if password.length() < 8 or password.length() > 128:
				return _err("password must be 8-128 characters")
			var callsign := Game.clean_name(_s(req, "callsign"), "")
			if callsign == "":
				return _err("enter a callsign")
			if not _within(addr, "signup", SIGNUPS_PER_HOUR, 3600.0):
				return _err("too many new accounts from this address - try again later")
			var salt := Crypto.new().generate_random_bytes(16)
			var hash := pbkdf2_sha256(password.to_utf8_buffer(), salt, PBKDF2_ITER)  # outside the lock
			_mx.lock()
			if _store.has_section(email):
				_mx.unlock()
				return _err("that email already has an account")
			if _store.get_sections().size() >= MAX_ACCOUNTS:
				_mx.unlock()
				return _err("the server is not taking new accounts")
			_store.set_value(email, "salt", Marshalls.raw_to_base64(salt))
			_store.set_value(email, "hash", Marshalls.raw_to_base64(hash))
			_store.set_value(email, "iter", PBKDF2_ITER)
			_store.set_value(email, "profile", {"pilot_name": callsign, "elo": 1000, "xp": 0, "level": 1,
				"coins": 0, "wins": 0, "losses": 0, "skills": {}})
			_save_store()
			_mx.unlock()
			print("[Accounts] signup: %s" % email)
			return _session_reply(email)
		"login":
			if password.length() > 128:
				return _err("wrong email or password")
			_mx.lock()
			var f: Dictionary = _fails.get(email, {"n": 0, "until": 0.0})
			var known := _store.has_section(email)
			var salt := Marshalls.base64_to_raw(_store.get_value(email, "salt", "")) if known else PackedByteArray()
			var want := Marshalls.base64_to_raw(_store.get_value(email, "hash", "")) if known else PackedByteArray()
			var iters: int = int(_store.get_value(email, "iter", PBKDF2_ITER)) if known else PBKDF2_ITER
			_mx.unlock()
			if Time.get_ticks_msec() * 0.001 < float(f["until"]):
				return _err("too many attempts - try again in a minute")
			# unknown emails hash too, so the reply time doesn't say whether an account exists
			var got := pbkdf2_sha256(password.to_utf8_buffer(), salt if known else "x".to_utf8_buffer(), iters)
			_mx.lock()
			if not known or not _same(got, want):
				f["n"] = int(f["n"]) + 1
				if int(f["n"]) >= LOCK_AFTER:
					f = {"n": 0, "until": Time.get_ticks_msec() * 0.001 + LOCK_S}
				if _fails.size() > 20000:
					_fails.clear()  # ponytail: as _hits
				_fails[email] = f
				_mx.unlock()
				return _err("wrong email or password")
			_fails.erase(email)
			_mx.unlock()
			return _session_reply(email)
	return _err("bad request")

static func _same(a: PackedByteArray, b: PackedByteArray) -> bool:
	if a.size() != b.size():
		return false
	var diff := 0
	for i in a.size():  # constant time: no early exit on the first mismatch
		diff |= a[i] ^ b[i]
	return diff == 0

func _session_reply(email: String) -> Dictionary:
	var token := Crypto.new().generate_random_bytes(32).hex_encode()
	_mx.lock()
	if _sessions.size() > 5000:  # expired ones only go when presented; sweep before it grows
		var now := Time.get_unix_time_from_system()
		for t in _sessions.keys():
			if now > float(_sessions[t]["exp"]):
				_sessions.erase(t)
	_sessions[token] = {"email": email, "exp": Time.get_unix_time_from_system() + SESSION_S}
	_mx.unlock()
	return {"ok": true, "session": token, "profile": profile(email)}

func _err(msg: String) -> Dictionary:
	return {"ok": false, "error": msg}

## V62: an email is a store section name and a log line: plain address characters only.
func _valid_email(e: String) -> bool:
	return e.length() <= 254 and _email_re.search(e) != null

## Account email for a session token, or "" (unknown / expired).
func email_for(session: String) -> String:
	_mx.lock()
	var s = _sessions.get(session)
	var out := ""
	if s != null and Time.get_unix_time_from_system() <= float(s["exp"]):
		out = s["email"]
	elif s != null:
		_sessions.erase(session)
	_mx.unlock()
	return out

## T385: the account a join ticket stands for, once ("" = unknown, expired or already used).
func redeem(ticket: String) -> String:
	_mx.lock()
	var t = _tickets.get(ticket)
	_tickets.erase(ticket)
	_mx.unlock()
	return t["email"] if t != null and Time.get_unix_time_from_system() <= float(t["exp"]) else ""

func profile(email: String) -> Dictionary:
	_mx.lock()
	var p := (_store.get_value(email, "profile", {}) as Dictionary).duplicate(true)
	_mx.unlock()
	return p

func save_profile(email: String, prof: Dictionary) -> void:
	_mx.lock()
	_store.set_value(email, "profile", prof)
	_save_store()
	_mx.unlock()

## PBKDF2-HMAC-SHA256, one 32-byte block (RFC 8018; dkLen = hLen).
static func pbkdf2_sha256(password: PackedByteArray, salt: PackedByteArray, iterations: int) -> PackedByteArray:
	var crypto := Crypto.new()
	var block := salt.duplicate()
	block.append_array(PackedByteArray([0, 0, 0, 1]))
	var u := crypto.hmac_digest(HashingContext.HASH_SHA256, password, block)
	var t := [u.decode_s64(0), u.decode_s64(8), u.decode_s64(16), u.decode_s64(24)]  # XOR in 8-byte words
	for _i in iterations - 1:
		u = crypto.hmac_digest(HashingContext.HASH_SHA256, password, u)
		t[0] ^= u.decode_s64(0)
		t[1] ^= u.decode_s64(8)
		t[2] ^= u.decode_s64(16)
		t[3] ^= u.decode_s64(24)
	var out := PackedByteArray()
	out.resize(32)
	for k in 4:
		out.encode_s64(k * 8, t[k])
	return out
