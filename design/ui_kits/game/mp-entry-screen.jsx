// Hardpoint UI Kit — Multiplayer · LAN entry. NEW screen.
// Left: discovered-peer browser. Right: HOST GAME + DIRECT CONNECT.
// LAN is wired but gated on the solo loop (README) — tone stays terse.

/* eslint-disable */

const MP_PEERS = [
  { host: "VESPER-09",  ip: "10.0.0.42:8910",  map: "MATH TEMPLE", players: "6 / 10", ping: 4,   elo: 1842, tag: "open" },
  { host: "BIRCH",      ip: "10.0.0.51:8910",  map: "BADLANDS",    players: "10 / 10", ping: 11,  elo: 2104, tag: "full" },
  { host: "KESTREL-7",  ip: "10.0.0.18:8910",  map: "IRONWORKS",   players: "3 / 8",  ping: 7,   elo: 1560, tag: "open" },
  { host: "DRY-DOCK",   ip: "10.0.0.90:8910",  map: "MATH TEMPLE", players: "1 / 10", ping: 22,  elo: 980,  tag: "bots" },
];

function MPField({ label, value, mono = true }) {
  return (
    <label style={{ display: "block" }}>
      <div style={{ fontFamily: "var(--font-ui)", fontSize: 11, letterSpacing: "0.18em", textTransform: "uppercase", color: "var(--fg-3)", marginBottom: 6 }}>{label}</div>
      <input defaultValue={value} style={{ width: "100%", boxSizing: "border-box", background: "var(--bg-void)", border: "1px solid var(--rule)", color: "var(--fg-1)", fontFamily: mono ? "var(--font-mono)" : "var(--font-ui)", fontSize: 14, padding: "9px 11px", letterSpacing: "0.04em", outline: "none" }} />
    </label>
  );
}

function MPSelectRow({ label, value }) {
  return (
    <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
      <div style={{ fontFamily: "var(--font-ui)", fontSize: 11, letterSpacing: "0.18em", textTransform: "uppercase", color: "var(--fg-3)", width: 110 }}>{label}</div>
      <div style={{ flex: 1, display: "flex", alignItems: "center", justifyContent: "space-between", background: "var(--bg-void)", border: "1px solid var(--rule)", padding: "9px 11px", fontFamily: "var(--font-mono)", fontSize: 14, color: "var(--fg-1)", letterSpacing: "0.04em" }}>
        {value} <span style={{ color: "var(--fg-3)" }}>▾</span>
      </div>
    </div>
  );
}

function MPEntry() {
  const tags = {
    open: { tone: "neutral", label: "OPEN" },
    full: { tone: "enemy", label: "FULL" },
    bots: { tone: "bot", label: "BOTS" },
  };
  return (
    <div data-screen-label="MPEntry" style={{ position: "relative", width: "100%", height: "100%", background: "var(--bg-void)", color: "var(--fg-1)", display: "flex", flexDirection: "column" }}>
      {/* top bar */}
      <div style={{ padding: "12px 18px", display: "flex", alignItems: "center", gap: 14, borderBottom: "2px solid var(--rule)" }}>
        <img src="../../assets/logo-mark.svg" width={28} height={28} style={{ imageRendering: "pixelated" }} alt="" />
        <div style={{ fontFamily: "var(--font-display)", fontSize: 22, letterSpacing: "0.06em" }}>MULTIPLAYER · LAN</div>
        <div style={{ flex: 1 }} />
        <Chip tone="elo">PILOT VESPER-09</Chip>
        <Chip tone="caution">SUBNET 10.0.0.0/24</Chip>
      </div>

      <div style={{ flex: 1, padding: 18, display: "grid", gridTemplateColumns: "1fr 360px", gap: 16, minHeight: 0 }}>
        {/* peer browser */}
        <div style={{ display: "flex", flexDirection: "column", minHeight: 0 }}>
          <div style={{ display: "flex", alignItems: "center", marginBottom: 8 }}>
            <Micro>DISCOVERED PEERS</Micro>
            <div style={{ flex: 1 }} />
            <span style={{ fontFamily: "var(--font-mono)", fontSize: 11, color: "var(--neon-cyan)", letterSpacing: "0.14em" }}>● SCANNING · {MP_PEERS.length} FOUND</span>
          </div>
          {/* column header */}
          <div style={{ display: "grid", gridTemplateColumns: "1.4fr 1.2fr 1fr 0.7fr 0.7fr 90px", gap: 10, padding: "6px 12px", fontFamily: "var(--font-ui)", fontSize: 10, letterSpacing: "0.16em", textTransform: "uppercase", color: "var(--fg-3)", borderBottom: "1px solid var(--rule-faint)" }}>
            <div>HOST</div><div>ADDRESS</div><div>MAP</div><div>PLAYERS</div><div>PING</div><div style={{ textAlign: "right" }}>STATE</div>
          </div>
          <div style={{ overflow: "auto", flex: 1 }}>
            {MP_PEERS.map((p, i) => (
              <div key={p.ip} style={{ display: "grid", gridTemplateColumns: "1.4fr 1.2fr 1fr 0.7fr 0.7fr 90px", gap: 10, alignItems: "center", padding: "12px", background: i === 0 ? "#101830" : "var(--bg-deep)", border: "1px solid " + (i === 0 ? "var(--team-ally)" : "var(--rule-faint)"), marginBottom: -1, boxShadow: i === 0 ? "0 0 10px rgba(51,128,255,.3) inset" : "none" }}>
                <div style={{ fontFamily: "var(--font-ui)", fontWeight: 700, fontSize: 14, letterSpacing: "0.06em", textTransform: "uppercase", color: "var(--fg-1)" }}>{p.host}</div>
                <div style={{ fontFamily: "var(--font-mono)", fontSize: 12, color: "var(--fg-3)", letterSpacing: "0.04em" }}>{p.ip}</div>
                <div style={{ fontFamily: "var(--font-ui)", fontSize: 12, letterSpacing: "0.08em", textTransform: "uppercase", color: "var(--fg-2)" }}>{p.map}</div>
                <div style={{ fontFamily: "var(--font-mono)", fontSize: 13, color: p.tag === "full" ? "var(--team-enemy-soft)" : "var(--fg-1)" }}>{p.players}</div>
                <div style={{ fontFamily: "var(--font-mono)", fontSize: 13, color: p.ping < 10 ? "var(--hp-full)" : p.ping < 20 ? "var(--caution)" : "var(--team-enemy-soft)" }}>{p.ping}ms</div>
                <div style={{ textAlign: "right" }}>
                  {p.tag === "full"
                    ? <Chip tone="enemy">FULL</Chip>
                    : <MBButton variant={i === 0 ? "primary" : "default"} style={{ padding: "6px 16px", fontSize: 12 }}>JOIN</MBButton>}
                </div>
              </div>
            ))}
          </div>
          <div style={{ fontFamily: "var(--font-mono)", fontSize: 11, color: "var(--fg-3)", letterSpacing: "0.14em", marginTop: 10 }}>
            BROADCAST PORT 8910 · ELO PEER-EXCHANGED · [ F5 ] RESCAN
          </div>
        </div>

        {/* host + direct connect */}
        <div style={{ display: "flex", flexDirection: "column", gap: 14, minHeight: 0 }}>
          <Panel title="HOST GAME">
            <div style={{ display: "flex", flexDirection: "column", gap: 12 }}>
              <MPSelectRow label="MAP" value="MATH TEMPLE" />
              <MPSelectRow label="MAX PLAYERS" value="10" />
              <MPSelectRow label="BOT FILL" value="ON · BALANCE TEAMS" />
              <MPSelectRow label="BEACONS" value="5" />
              <MBButton variant="primary" style={{ padding: "12px 22px", fontSize: 15, marginTop: 2 }}>HOST GAME</MBButton>
            </div>
          </Panel>
          <Panel title="DIRECT CONNECT">
            <div style={{ display: "flex", flexDirection: "column", gap: 12 }}>
              <MPField label="SERVER IP : PORT" value="10.0.0.42:8910" />
              <MBButton style={{ padding: "11px 22px", fontSize: 14 }}>CONNECT</MBButton>
            </div>
          </Panel>
        </div>
      </div>
    </div>
  );
}

Object.assign(window, { MPEntry });
