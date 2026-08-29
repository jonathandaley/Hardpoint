// Hardpoint UI Kit — pre-match Lobby / staging. NEW screen.
// Two team columns (ally blue, enemy red — V122 never swapped), ready
// states, map header, countdown, ready-up action bar.

/* eslint-disable */

const LOBBY_ALLY = [
  { name: "VESPER-09", mech: "PEGASUS", elo: 1842, ready: true,  bot: false },
  { name: "BIRCH",     mech: "EVEREST", elo: 2104, ready: true,  bot: false },
  { name: "SLIP-03",   mech: "SLIP",    elo: 1490, ready: false, bot: false },
  { name: "HORNET-02", mech: "HORNET",  elo: 1310, ready: true,  bot: true },
  { name: "CESH-05",   mech: "CESH",    elo: 1205, ready: true,  bot: true },
];
const LOBBY_ENEMY = [
  { name: "KESTREL-7",   mech: "SEEKER",     elo: 1980, ready: true,  bot: false },
  { name: "EVEREST-01",  mech: "VESUVIUS",   elo: 1760, ready: true,  bot: true },
  { name: "HIPPO-04",    mech: "HIPPOGRIFF", elo: 1644, ready: true,  bot: true },
  { name: "SEEKER-08",   mech: "SEEKER",     elo: 1402, ready: false, bot: true },
  { name: "PEGASUS-06",  mech: "PEGASUS",    elo: 1188, ready: true,  bot: true },
];

function LobbyPilotRow({ p, side }) {
  const color = side === "ally" ? "var(--team-ally)" : "var(--team-enemy)";
  const soft = side === "ally" ? "var(--team-ally-soft)" : "var(--team-enemy-soft)";
  return (
    <div style={{ display: "flex", alignItems: "center", gap: 10, padding: "11px 12px", background: "var(--bg-deep)", border: "1px solid var(--rule-faint)", borderLeft: "3px solid " + color, marginBottom: -1, flexDirection: side === "enemy" ? "row-reverse" : "row", textAlign: side === "enemy" ? "right" : "left" }}>
      <span style={{ width: 10, height: 10, borderRadius: "50%", background: p.ready ? "var(--hp-full)" : "var(--bg-raised)", border: "1px solid #000", boxShadow: p.ready ? "0 0 8px rgba(0,255,51,.5)" : "none", flex: "none" }} />
      <div style={{ flex: 1 }}>
        <div style={{ fontFamily: "var(--font-ui)", fontWeight: 700, fontSize: 14, letterSpacing: "0.06em", textTransform: "uppercase", color: soft }}>
          {p.name} {p.bot && <span style={{ fontFamily: "var(--font-mono)", fontSize: 10, color: "var(--rust)", letterSpacing: "0.1em" }}>[BOT]</span>}
        </div>
        <div style={{ fontFamily: "var(--font-mono)", fontSize: 11, color: "var(--fg-3)", letterSpacing: "0.06em" }}>{p.mech} · ELO {p.elo}</div>
      </div>
      <div style={{ fontFamily: "var(--font-mono)", fontSize: 11, letterSpacing: "0.14em", color: p.ready ? "var(--hp-full)" : "var(--caution)" }}>{p.ready ? "READY" : "WAIT"}</div>
    </div>
  );
}

function LobbyColumn({ side, title, list, count }) {
  const color = side === "ally" ? "var(--team-ally)" : "var(--team-enemy)";
  return (
    <div style={{ display: "flex", flexDirection: "column", minHeight: 0 }}>
      <div style={{ display: "flex", alignItems: "center", gap: 10, marginBottom: 10, flexDirection: side === "enemy" ? "row-reverse" : "row" }}>
        <div style={{ fontFamily: "var(--font-display)", fontSize: 22, letterSpacing: "0.06em", color }}>{title}</div>
        <div style={{ flex: 1, height: 2, background: color, opacity: 0.4 }} />
        <div style={{ fontFamily: "var(--font-mono)", fontSize: 12, color: "var(--fg-3)", letterSpacing: "0.1em" }}>{count}</div>
      </div>
      <div style={{ overflow: "auto", flex: 1 }}>
        {list.map((p) => <LobbyPilotRow key={p.name} p={p} side={side} />)}
      </div>
    </div>
  );
}

function Lobby() {
  return (
    <div data-screen-label="Lobby" style={{ position: "relative", width: "100%", height: "100%", background: "var(--bg-void)", color: "var(--fg-1)", display: "flex", flexDirection: "column", overflow: "hidden" }}>
      <div style={{ position: "absolute", inset: 0, background: "radial-gradient(ellipse at 50% 0%, rgba(51,128,255,0.06), transparent 45%), radial-gradient(ellipse at 50% 100%, rgba(255,77,51,0.06), transparent 45%)", pointerEvents: "none" }} />

      {/* header */}
      <div style={{ position: "relative", padding: "14px 18px", display: "flex", alignItems: "center", gap: 14, borderBottom: "2px solid var(--rule)" }}>
        <div style={{ fontFamily: "var(--font-display)", fontSize: 22, letterSpacing: "0.06em" }}>STAGING</div>
        <Chip tone="caution">MATCH FOUND</Chip>
        <div style={{ flex: 1 }} />
        <div style={{ fontFamily: "var(--font-ui)", fontSize: 13, letterSpacing: "0.1em", textTransform: "uppercase", color: "var(--fg-2)" }}>
          MAP <span style={{ color: "var(--fg-1)" }}>MATH TEMPLE</span> · BEACON DRAIN · 5 BEACONS · TO 1000
        </div>
      </div>

      {/* body: ally | center | enemy */}
      <div style={{ position: "relative", flex: 1, padding: 18, display: "grid", gridTemplateColumns: "1fr 280px 1fr", gap: 18, minHeight: 0 }}>
        <LobbyColumn side="ally" title="ALLY" list={LOBBY_ALLY} count="5 / 5" />

        {/* center: countdown + map stub */}
        <div style={{ display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", gap: 14 }}>
          <div style={{ fontFamily: "var(--font-ui)", fontSize: 11, letterSpacing: "0.24em", color: "var(--fg-3)", textTransform: "uppercase" }}>ARENA LOADS IN</div>
          <div style={{ fontFamily: "var(--font-display)", fontSize: 72, lineHeight: 1, color: "var(--neon-cyan)", textShadow: "0 0 26px rgba(40,224,198,0.4)" }}>00:08</div>
          {/* map stub */}
          <div style={{ width: 220, height: 130, background: "radial-gradient(ellipse at 50% 60%, rgba(40,224,198,0.08), transparent 60%), var(--bg-deep)", border: "1px solid var(--rule)", boxShadow: "inset 0 0 30px rgba(0,0,0,0.7)", position: "relative", marginTop: 4 }}>
            <div style={{ position: "absolute", inset: 6, border: "1px dashed var(--rust)", opacity: 0.35 }} />
            {[["20%","70%","var(--team-ally)"],["55%","55%","var(--caution)"],["48%","38%","var(--bg-raised)"],["80%","30%","var(--team-enemy)"],["72%","72%","var(--team-enemy)"]].map((b,i)=>(
              <div key={i} style={{ position: "absolute", left: b[0], top: b[1], width: 9, height: 9, borderRadius: "50%", background: b[2], boxShadow: b[2].includes("raised") ? "none" : "0 0 6px " + b[2] }} />
            ))}
            <div style={{ position: "absolute", bottom: 6, left: 8, fontFamily: "var(--font-mono)", fontSize: 10, color: "var(--fg-3)", letterSpacing: "0.12em" }}>MATH TEMPLE</div>
          </div>
          <div style={{ fontFamily: "var(--font-display)", fontSize: 28, letterSpacing: "0.1em", color: "var(--fg-2)", marginTop: 2 }}>VS</div>
        </div>

        <LobbyColumn side="enemy" title="ENEMY" list={LOBBY_ENEMY} count="5 / 5" />
      </div>

      {/* action bar */}
      <div style={{ position: "relative", padding: 18, borderTop: "2px solid var(--rule)", display: "flex", alignItems: "center", gap: 12 }}>
        <Micro>STATUS: <span style={{ color: "var(--caution)" }}>2 PILOTS NOT READY</span> · AUTO-START AT 00:00</Micro>
        <div style={{ flex: 1 }} />
        <MBButton variant="ghost">LEAVE</MBButton>
        <MBButton variant="primary" style={{ padding: "12px 40px" }}>READY UP</MBButton>
      </div>
    </div>
  );
}

Object.assign(window, { Lobby });
