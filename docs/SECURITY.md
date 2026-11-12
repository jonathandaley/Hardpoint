# Network security rules

Plain-language copy of SPEC V61 / V62 (T290, 2026-11-12). Read this before any task that
touches RPCs, the join handshake, the lobby, accounts, or anything a server sends a client.

## The one idea

**Every client is hostile until proven otherwise, and so is every server a client joins.**
A player can run a modified game that sends anything, in any order, as fast as it likes.
A stranger who never logs in can still send packets to both ports. The server decides
everything that matters from its own simulation; a client only ever *asks*.

Two ports face the internet on a dedicated server:

| Port | What | Who can reach it |
|---|---|---|
| game (UDP, ENet) | join handshake, then RPCs | anyone; RPCs only after the handshake |
| game + 1 (TCP, TLS) | accounts: sign up, log in, skills | anyone |

## Rules

1. **A new client-callable RPC is a security change.** `@rpc("any_peer")` means "any player
   may call this with any arguments". Add it to `ANY_PEER_OK` in
   `tools/oracles/net_security.py` and add an attack on it to `tools/security/attacker.gd`
   in the same task. Prefer not adding one: most things belong on the server.
2. **Every any_peer handler starts the same way**: `if not multiplayer.is_server(): return`,
   then `var sender := multiplayer.get_remote_sender_id()`. Who is asking is never a
   parameter the client fills in.
3. **Ask "may this sender do this now?", not just "is the sender known?"** Does it own that
   mech? Is its current mech dead? Is that slot unused? Is the match still running? (The
   worst bug of T290 was an RPC that checked only that the sender was connected.)
4. **Clients never report outcomes.** Damage, health, kills, pickups, scores, coins, XP,
   match results are computed on the server. A client sends input and choices.
5. **Check the type before using a value.** A client's Dictionary / JSON can hold anything
   anywhere. `String(x)`, `int(x)`, `float(x)`, `x == true`, or assigning to a typed
   variable faults the handler when `x` is the wrong type. Use `Game.clean_int`,
   `Game.clean_name`, `x is String`, `typeof(x)`, `AccountServer._s()`.
6. **Bound every value**: numbers clamped, floats `is_finite`, strings cut to a length,
   arrays to a size. Rebuild what you keep from server-side lists
   (`Game.clean_squad_entry`); never store a client's dictionary as sent.
7. **Paths from the network are picked from a list, not loaded.** Server side: the path
   must BE an entry of `Lobby.ROSTER` / `WEAPON_CATALOG`. Client side (paths from a
   server): `Game.safe_res(path, folder, extension)`.
8. **`Game.mp_lobby` and match rosters are public.** Every client gets a copy. Tokens,
   sessions, emails, addresses go in the server-private dicts in `Game.gd`
   (`_late_tokens`, `_peer_sessions`, `_peer_accounts`, `_peer_addr`) and are cleared in
   `_forget_peer`.
9. **Refuse quietly.** `Game.net_refuse(sender, why)` logs five lines per peer, then goes
   silent. Never `push_error` on client input: an attacker would fill the disk with it.
10. **Anything a client can trigger repeatedly gets a limit**: `Game.net_rate_ok` for RPCs
    that make the server broadcast; `AccountServer._within` (per address) before any
    password hashing. Any table keyed by a client-chosen value needs a size cap.
11. **Before a peer is admitted it gets almost nothing**: one hello, one small answer, a
    few seconds. Don't add work, state, or bigger replies to the handshake.
12. **Never decode objects or run text**: no `bytes_to_var_with_objects`, `str_to_var`,
    `allow_object_decoding`, `Expression`, `OS.execute`, `OS.create_process`,
    `OS.shell_open` in game code. `bytes_to_var` only where the oracle allows it.
13. **Secrets**: passwords only ever travel to the account port (TLS) and are stored as
    salted PBKDF2 hashes; nothing password-, hash- or session-shaped is printed, logged,
    or sent to another player. The game connection is not encrypted (T212): put nothing
    on it that is worth stealing. A login session goes only to the account port of the
    server it belongs to; the game hello carries a single-use join ticket (T385).
14. **Debug things stay out of reach of the network**: debug mechs, cheats, harness
    switches are never selectable through an RPC or a handshake field.

15. **Changing what travels on the wire means bumping `Game.NET_VERSION`.** A new or changed
    `@rpc` function, a new step or field in the join hello, a new shape for the lobby, roster
    or late-join data: old and new games can no longer talk, so the server must tell the
    player to update instead of desyncing. The suite fails when an `@rpc` signature changes
    without a bump (`NET_SIG` in `tools/oracles/net_security.py`); the other shapes are on you.

## How it is enforced

- `python3 tools/security/run_security.py` starts a real dedicated server on loopback
  and attacks it from outside (hostile game client, raw ENet peer, half-open flood,
  account-endpoint attacker). It must print `0 VULN`. It runs as the `security` step of
  `tools/run_suite.py`.
- `tools/oracles/net_security.py` (static, in the suite): rules 1, 2, 5, 9, 12, 15.
- Probes `net_clean` and `accounts`: the cleaning helpers and the account endpoint.

A change that needs one of these loosened is a decision for the user, not for a task.

## Before going online (T266 deploy)

The code is hardened; these belong to the machine and the deploy kit:

- Run the server as its own unprivileged user, with only its data folder writable.
- Firewall: open only the game UDP port and the account TCP port; rate-limit new
  connections per source address on both.
- Cap the logs. The engine prints one line for every malformed packet it refuses, and
  that cannot be turned off from game code.
- Back up `accounts.cfg`; keep `account_tls.key` private.
- Keep Godot up to date: the engine parses every packet before game code sees it.
