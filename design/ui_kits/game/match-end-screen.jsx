// Hardpoint UI Kit — Match-end. NEW screen. result = "WIN" | "LOSE".
// Big stencil verdict + full two-team scoreboard + beacon outcome + ELO
// delta. Copy is "YOU WIN" / "YOU LOSE" — no consolation flourishes.

/* eslint-disable */

const ME_ALLY = [
  { name: "VESPER-09", mech: "PEGASUS", k: 14, d: 6,  score: 312, bot: false, you: true },
  { name: "BIRCH",     mech: "EVEREST", k: 9,  d: 8,  score: 244, bot: false },
  { name: "SLIP-03",   mech: "SLIP",    k: 11, d: 10, score: 198, bot: false },
  { name: "HORNET-02", mech: "HORNET",  k: 6,  d: 9,  score: 141, bot: true },
  { name: "CESH-05",   mech: "CESH",    k: 4,  d: 11, score: 96,  bot: true },
];
const ME_ENEMY = [
  { name: "KESTREL-7",  mech: "SEEKER",     k: 12, d: 9,  score: 270, bot: false },
  { name: "EVEREST-01", mech: "VESUVIUS",   k: 10, d: 8,  score: 233, bot: true },
  { name: "HIPPO-04",   mech: "HIPPOGRIFF", k: 8,  d: 10, score: 187, bot: true },
  { name: "SEEKER-08",  mech: "SEEKER",     k: 7,  d: 12, score: 132, bot: true },
  { name: "PEGASUS-06", mech: "PEGASUS",    k: 5,  d: 13, score: 88,  bot: true },
];

function MEScoreTable({ side, list }) {
  const color = side === "ally" ? "var(--team-ally)" : "var(--team-enemy)";
  const soft = side === "ally" ? "var(--team-ally-soft)" : "var(--team-enemy-soft)";
  return (
    <div style={{ flex: 1 }}>
      <div style={{ display: "flex", alignItems: "center", gap: 10, marginBottom: 8 }}>
        <div style={{ fontFamily: "var(--font-display)", fontSize: 18, letterSpacing: "0.06em", color }}>{side === "ally" ? "ALLY" : "ENEMY"}</div>
        <div style={{ flex: 1, height: 2, background: color, opacity: 0.4 }} />
      </div>
      <div style={{ display: "grid", gridTemplateColumns: "1.6fr 0.5fr 0.5fr 0.7fr", gap: 8, padding: "4px 12px", fontFamily: "var(--font-ui)", fontSize: 10, letterSpacing: "0.16em", color: "var(--fg-3)", textTransform: "uppercase" }}>
        <div>PILOT</div><div style={{ textAlign: "right" }}>K</div><div style={{ textAlign: "right" }}>D</div><div style={{ textAlign: "right" }}>SCORE</div>
      </div>
      {list.map((p) => (
        <div key={p.name} style={{ display: "grid", gridTemplateColumns: "1.6fr 0.5fr 0.5fr 0.7fr", gap: 8, alignItems: "center", padding: "9px 12px", background: p.you ? "#101830" : "var(--bg-deep)", border: "1px solid " + (p.you ? color : "var(--rule-faint)"), borderLeft: "3px solid " + color, marginBottom: -1 }}>
          <div style={{ fontFamily: "var(--font-ui)", fontWeight: 700, fontSize: 13, letterSpacing: "0.05em", textTransform: "uppercase", color: p.you ? "#fff" : soft }}>
            {p.name} {p.bot && <span style={{ fontFamily: "var(--font-mono)", fontSize: 9, color: "var(--rust)" }}>[BOT]</span>}
            <span style={{ fontFamily: "var(--font-mono)", fontSize: 10, color: "var(--fg-3)", marginLeft: 6 }}>{p.mech}</span>
          </div>
          <div style={{ fontFamily: "var(--font-mono)", fontSize: 13, color: "var(--fg-1)", textAlign: "right" }}>{p.k}</div>
          <div style={{ fontFamily: "var(--font-mono)", fontSize: 13, color: "var(--fg-3)", textAlign: "right" }}>{p.d}</div>
          <div style={{ fontFamily: "var(--font-mono)", fontSize: 13, color: "var(--caution)", textAlign: "right" }}>{p.score}</div>
        </div>
      ))}
    </div>
  );
}

function MatchEnd({ result = "WIN" }) {
  const win = result === "WIN";
  const color = win ? "var(--team-ally)" : "var(--team-enemy)";
  const glow = win ? "rgba(51,128,255,0.4)" : "rgba(255,77,51,0.4)";
  return (
    <div data-screen-label={"MatchEnd-" + result} style={{ position: "relative", width: "100%", height: "100%", background: "var(--bg-void)", color: "var(--fg-1)", overflow: "hidden", display: "flex", flexDirection: "column" }}>
      <div style={{ position: "absolute", inset: 0, background: "radial-gradient(ellipse at 50% 0%, " + glow.replace("0.4", "0.12") + ", transparent 55%)", pointerEvents: "none" }} />
      <div style={{ position: "absolute", top: 0, left: 0, right: 0, height: 8, background: "repeating-linear-gradient(135deg," + (win ? "#3380ff" : "#ff4d33") + " 0 14px,#1a1410 14px 28px)", opacity: 0.5 }} />

      {/* verdict header */}
      <div style={{ position: "relative", paddingTop: 40, paddingBottom: 18, textAlign: "center" }}>
        <div style={{ fontFamily: "var(--font-display)", fontSize: 88, letterSpacing: "0.08em", lineHeight: 1, color, textShadow: "0 0 40px " + glow }}>
          YOU {result}
        </div>
        <div style={{ fontFamily: "var(--font-mono)", fontSize: 13, color: "var(--fg-3)", letterSpacing: "0.3em", marginTop: 12 }}>
          MATH TEMPLE · BEACON DRAIN · 11:42 ELAPSED
        </div>
      </div>

      {/* beacon outcome bar */}
      <div style={{ position: "relative", display: "flex", justifyContent: "center", marginBottom: 18 }}>
        <div style={{ display: "flex", alignItems: "center", gap: 14 }}>
          <div style={{ fontFamily: "var(--font-mono)", fontSize: 26, color: "var(--team-ally-soft)" }}>{win ? "1000" : "812"}</div>
          <div style={{ width: 280, height: 16, background: "var(--bg-bar)", border: "1px solid #000", position: "relative", display: "flex" }}>
            <div style={{ width: (win ? 55 : 45) + "%", background: "var(--team-ally)" }} />
            <div style={{ flex: 1, background: "var(--team-enemy)" }} />
          </div>
          <div style={{ fontFamily: "var(--font-mono)", fontSize: 26, color: "var(--team-enemy-soft)" }}>{win ? "874" : "1000"}</div>
        </div>
      </div>

      {/* scoreboard */}
      <div style={{ position: "relative", flex: 1, padding: "0 32px", display: "flex", gap: 24, minHeight: 0 }}>
        <MEScoreTable side="ally" list={ME_ALLY} />
        <MEScoreTable side="enemy" list={ME_ENEMY} />
      </div>

      {/* footer: elo delta + actions */}
      <div style={{ position: "relative", padding: 22, borderTop: "2px solid var(--rule)", display: "flex", alignItems: "center", gap: 16 }}>
        <div style={{ display: "flex", alignItems: "baseline", gap: 8 }}>
          <span style={{ fontFamily: "var(--font-ui)", fontSize: 11, letterSpacing: "0.18em", color: "var(--fg-3)", textTransform: "uppercase" }}>ELO</span>
          <span style={{ fontFamily: "var(--font-mono)", fontSize: 20, color: "var(--fg-1)" }}>{win ? 1842 : 1842}</span>
          <span style={{ fontFamily: "var(--font-mono)", fontSize: 18, color: win ? "var(--hp-full)" : "var(--team-enemy-soft)" }}>{win ? "+24" : "−18"}</span>
          <span style={{ fontFamily: "var(--font-mono)", fontSize: 14, color: "var(--fg-3)" }}>→ {win ? 1866 : 1824}</span>
        </div>
        <div style={{ marginLeft: 18, display: "flex", gap: 8 }}>
          <Chip tone="caution">MVP · VESPER-09</Chip>
          <Chip tone="elo">+420 COINS</Chip>
        </div>
        <div style={{ flex: 1 }} />
        <MBButton variant="ghost">VIEW STATS</MBButton>
        <MBButton>REMATCH</MBButton>
        <MBButton variant="primary" style={{ padding: "12px 32px" }}>RETURN TO HANGAR</MBButton>
      </div>
    </div>
  );
}

Object.assign(window, { MatchEnd });
