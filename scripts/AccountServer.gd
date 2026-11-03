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

const PBKDF2_ITER := 20000
const LOCK_AFTER := 5
const LOCK_S := 60.0
const SESSION_S := 7 * 24 * 3600.0
const STORE := "user://accounts.cfg"
const KEY_PATH := "user://account_tls.key"
const CERT_PATH := "user://account_tls.crt"
const MAX_LINE := 4096

var _tcp := TCPServer.new()
var _tls_opts: TLSOptions = null
var _conns: Array = []          # [{tls, buf, t}]
var _sessions: Dictionary = {}  # token -> {email, exp}
var _fails: Dictionary = {}     # email -> {n, until}
var _store := ConfigFile.new()
var _mx := Mutex.new()          # requests run on a worker thread (PBKDF2 ~60 ms); store, sessions, fails shared

func start(port: int) -> bool:
	_store.load(STORE)
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
	return key

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
		var tls := StreamPeerTLS.new()
		if tls.accept_stream(_tcp.take_connection(), _tls_opts) == OK:
			_conns.append({"tls": tls, "buf": PackedByteArray(), "t": Time.get_ticks_msec()})
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
			tls.put_data((JSON.stringify(handle(c["buf"].slice(0, nl).get_string_from_utf8())) + "\n").to_utf8_buffer())
			tls.poll()
			tls.disconnect_from_stream()
			_conns.erase(c)
		elif nl >= 0:
			var line: String = c["buf"].slice(0, nl).get_string_from_utf8()
			var out := [null]
			c["reply"] = out
			c["task"] = WorkerThreadPool.add_task(func() -> void: out[0] = handle(line))
		elif st != StreamPeerTLS.STATUS_HANDSHAKING and st != StreamPeerTLS.STATUS_CONNECTED \
				or (c["buf"] as PackedByteArray).size() > MAX_LINE or Time.get_ticks_msec() - int(c["t"]) > 10000:
			tls.disconnect_from_stream()
			_conns.erase(c)

const SKILL_OPS := ["unlock_skill", "upgrade_skill"]

func _is_skill_op(line: String) -> bool:
	var req = JSON.parse_string(line)
	return req is Dictionary and String(req.get("op", "")) in SKILL_OPS

# One request (a JSON line from an untrusted client) -> reply. Public for the probe.
func handle(line: String) -> Dictionary:
	var req = JSON.parse_string(line)
	if not req is Dictionary:
		return _err("bad request")
	if String(req.get("op", "")) in SKILL_OPS:  # T213: {op, session, key}; main thread only
		var who := email_for(String(req.get("session", "")))
		if who == "":
			return _err("sign in again")
		var after: Dictionary = Game.skill_op_on(profile(who), String(req["op"]), String(req.get("key", "")))
		if after.is_empty():
			return _err("not enough points or coins")
		save_profile(who, after)
		return {"ok": true, "profile": after}
	var email := String(req.get("email", "")).strip_edges().to_lower()
	var password := String(req.get("password", ""))
	if not _valid_email(email):
		return _err("enter a valid email address")
	match String(req.get("op", "")):
		"signup":
			if password.length() < 8 or password.length() > 128:
				return _err("password must be 8-128 characters")
			var callsign := String(req.get("callsign", "")).strip_edges().left(16)
			if callsign == "":
				return _err("enter a callsign")
			var salt := Crypto.new().generate_random_bytes(16)
			var hash := pbkdf2_sha256(password.to_utf8_buffer(), salt, PBKDF2_ITER)  # outside the lock
			_mx.lock()
			if _store.has_section(email):
				_mx.unlock()
				return _err("that email already has an account")
			_store.set_value(email, "salt", Marshalls.raw_to_base64(salt))
			_store.set_value(email, "hash", Marshalls.raw_to_base64(hash))
			_store.set_value(email, "iter", PBKDF2_ITER)
			_store.set_value(email, "profile", {"pilot_name": callsign, "elo": 1000, "xp": 0, "level": 1,
				"coins": 0, "wins": 0, "losses": 0, "skills": {}})
			_store.save(STORE)
			_mx.unlock()
			print("[Accounts] signup: %s" % email)
			return _session_reply(email)
		"login":
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
	_sessions[token] = {"email": email, "exp": Time.get_unix_time_from_system() + SESSION_S}
	_mx.unlock()
	return {"ok": true, "session": token, "profile": profile(email)}

func _err(msg: String) -> Dictionary:
	return {"ok": false, "error": msg}

func _valid_email(e: String) -> bool:
	var at := e.find("@")
	return e.length() <= 254 and at > 0 and e.rfind(".") > at + 1 and not e.contains(" ") and e.count("@") == 1

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

func profile(email: String) -> Dictionary:
	_mx.lock()
	var p := (_store.get_value(email, "profile", {}) as Dictionary).duplicate(true)
	_mx.unlock()
	return p

func save_profile(email: String, prof: Dictionary) -> void:
	_mx.lock()
	_store.set_value(email, "profile", prof)
	_store.save(STORE)
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
