// Hardpoint UI Kit — domain widgets: weapon slots, beacon dots, crosshair,
// roster row. All composed from Primitives.jsx.

/* eslint-disable */
const { useState: useState_d, useEffect: useEffect_d, useRef: useRef_d } = React;

// ============================================================
// WeaponSlot — one of four 64×64 squares bottom-right of HUD
// ============================================================
function WeaponSlot({ slot, name, glyph, ammoPct, active, dim, reload }) {
  return (
    <div
      style={{
        width: 64,
        height: 64,
        background: "var(--bg-deep)",
        border: "1px solid " + (active ? "var(--team-ally)" : "var(--rule)"),
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        justifyContent: "center",
        fontFamily: "var(--font-mono)",
        position: "relative",
        opacity: dim ? 0.35 : 1,
        boxShadow: active ? "0 0 12px rgba(51,128,255,.45) inset" : "none",
      }}
    >
      <div
        style={{
          position: "absolute",
          left: 4,
          top: 2,
          fontSize: 10,
          color: active ? "var(--team-ally-soft)" : "var(--fg-3)",
          letterSpacing: "0.1em",
        }}
      >
        {slot}
      </div>
      <div style={{ fontSize: 22, color: active ? "var(--team-ally-soft)" : "var(--fg-2)" }}>{glyph}</div>
      <div
        style={{
          fontSize: 10,
          letterSpacing: "0.12em",
          color: "var(--fg-2)",
          textTransform: "uppercase",
        }}
      >
        {name}
      </div>
      <div
        style={{
          position: "absolute",
          left: 0,
          right: 0,
          bottom: 0,
          height: 4,
          background: "rgba(0,0,0,.6)",
        }}
      >
        <div
          style={{
            height: "100%",
            width: ammoPct * 100 + "%",
            background: reload ? "var(--fg-3)" : "var(--caution)",
          }}
        />
      </div>
    </div>
  );
}

// ============================================================
// BeaconDot — 22px circle. state: -1=neutral, 0=ally, 1=enemy, 2=contested
// progress 0..1 shown as conic when capturing
// ============================================================
function BeaconDot({ state, progress = 0, capTeam }) {
  let bg = "var(--bg-raised)";
  let glow = "none";
  if (state === 0) {
    bg = "var(--team-ally)";
    glow = "0 0 10px rgba(51,128,255,.55)";
  } else if (state === 1) {
    bg = "var(--team-enemy)";
    glow = "0 0 10px rgba(255,77,51,.55)";
  } else if (state === 2) {
    bg = "conic-gradient(var(--team-ally) 0 50%, var(--team-enemy) 50% 100%)";
  } else if (progress > 0) {
    const color = capTeam === 0 ? "var(--team-ally)" : "var(--team-enemy)";
    bg = `conic-gradient(${color} 0 ${progress * 100}%, var(--bg-raised) ${progress * 100}%)`;
  }
  return (
    <div
      style={{
        width: 22,
        height: 22,
        borderRadius: "50%",
        border: "2px solid #000",
        background: bg,
        boxShadow: glow,
      }}
    />
  );
}

// ============================================================
// TeamPawns — one mech pawn per roster slot; alive = team color,
// killed = darkened. side aligns the row toward the beacon dots.
// ============================================================
function Pawn({ dead, color }) {
  return (
    <svg width={13} height={16} viewBox="0 0 13 16" style={{ display: "block", filter: dead ? "none" : "drop-shadow(0 0 3px " + color + ")" }}>
      {/* simple mech pawn: head, shoulders, body */}
      <g fill={dead ? "var(--bg-raised)" : color} stroke="#000" strokeWidth="0.75">
        <rect x="4.5" y="1" width="4" height="4" />
        <rect x="1" y="5" width="11" height="3" />
        <rect x="3" y="8" width="7" height="7" />
      </g>
      {dead && <line x1="1.5" y1="2" x2="11.5" y2="14" stroke="var(--fg-dim)" strokeWidth="1.25" />}
    </svg>
  );
}
function TeamPawns({ alive, total, color, side }) {
  const pawns = Array.from({ length: total }, (_, i) => i < alive);
  return (
    <div style={{ display: "flex", gap: 4, marginTop: 4, justifyContent: side === "ally" ? "flex-end" : "flex-start" }}>
      {pawns.map((isAlive, i) => <Pawn key={i} dead={!isAlive} color={color} />)}
    </div>
  );
}

// ============================================================
// BeaconStrip — top-center scoring header
// ============================================================
function BeaconStrip({ beacons, scoreA, scoreB, scoreMax = 1000, aliveA, totalA = 5, aliveB, totalB = 5 }) {
  const pctA = scoreA / scoreMax;
  const pctB = scoreB / scoreMax;
  return (
    <div style={{ display: "flex", alignItems: "center", justifyContent: "center", gap: 10, padding: "8px 0" }}>
      <div style={{ textAlign: "right" }}>
        <div style={{ width: 130, height: 14, background: "var(--bg-bar)", border: "1px solid #000", position: "relative" }}>
          <div style={{ position: "absolute", inset: 0, background: "var(--team-ally)", width: pctA * 100 + "%" }} />
        </div>
        <TeamPawns alive={aliveA} total={totalA} color="var(--team-ally)" side="ally" />
      </div>
      <div style={{ display: "flex", gap: 4 }}>
        {beacons.map((b, i) => (
          <BeaconDot key={i} {...b} />
        ))}
      </div>
      <div>
        <div style={{ width: 130, height: 14, background: "var(--bg-bar)", border: "1px solid #000", position: "relative" }}>
          <div style={{ position: "absolute", right: 0, top: 0, bottom: 0, background: "var(--team-enemy)", width: pctB * 100 + "%" }} />
        </div>
        <TeamPawns alive={aliveB} total={totalB} color="var(--team-enemy)" side="enemy" />
      </div>
    </div>
  );
}

// ============================================================
// Crosshair — default / eligible / locked
// ============================================================
function Crosshair({ state = "default", lockProgress = 0 }) {
  const w = 80;
  if (state === "locked")
    return (
      <svg viewBox="0 0 80 80" width={w} height={w} style={{ overflow: "visible" }}>
        <g stroke="var(--team-enemy)" fill="none" strokeWidth="2.5">
          <rect x="26" y="26" width="28" height="28" strokeDasharray="6 4" />
          <circle cx="40" cy="40" r="22" stroke="var(--team-enemy)" strokeOpacity="0.4" />
          <path d="M18 26 L18 18 L26 18 M62 26 L62 18 L54 18 M18 54 L18 62 L26 62 M62 54 L62 62 L54 62" />
        </g>
      </svg>
    );
  if (state === "eligible")
    return (
      <svg viewBox="0 0 80 80" width={w} height={w}>
        <g stroke="var(--neon-cyan)" fill="none" strokeWidth="2">
          <rect x="28" y="28" width="24" height="24" />
          <line x1="22" y1="40" x2="28" y2="40" />
          <line x1="58" y1="40" x2="52" y2="40" />
          <line x1="40" y1="22" x2="40" y2="28" />
          <line x1="40" y1="58" x2="40" y2="52" />
        </g>
      </svg>
    );
  return (
    <svg viewBox="0 0 80 80" width={w} height={w}>
      <g stroke="var(--fg-1)" fill="var(--fg-1)" strokeWidth="2">
        <line x1="26" y1="40" x2="36" y2="40" />
        <line x1="44" y1="40" x2="54" y2="40" />
        <line x1="40" y1="26" x2="40" y2="36" />
        <line x1="40" y1="44" x2="40" y2="54" />
        <circle cx="40" cy="40" r="1.5" />
      </g>
    </svg>
  );
}

// ============================================================
// MechRosterRow — one mech in the hangar list
// ============================================================
function MechRosterRow({ name, slots, hp, speed, active, onSelect, badge }) {
  const slotChip = slots.includes("H") ? "rust" : slots.includes("L") ? "elo" : "neutral";
  const slotColors = {
    rust: { borderColor: "var(--rust)", color: "var(--rust)" },
    elo: { borderColor: "var(--neon-cyan)", color: "var(--neon-cyan)" },
    neutral: { borderColor: "var(--rule)", color: "var(--fg-2)" },
  }[slotChip];
  return (
    <div
      onClick={onSelect}
      style={{
        display: "flex",
        alignItems: "center",
        gap: 12,
        padding: "10px 12px",
        background: active ? "#101830" : "var(--bg-deep)",
        border: "1px solid " + (active ? "var(--team-ally)" : "var(--rule-faint)"),
        marginBottom: -1,
        fontFamily: "var(--font-ui)",
        cursor: "pointer",
        boxShadow: active ? "0 0 10px rgba(51,128,255,.3) inset" : "none",
      }}
    >
      <div
        style={{
          fontFamily: "var(--font-mono)",
          fontSize: 10,
          letterSpacing: "0.1em",
          padding: "2px 6px",
          border: "1px solid",
          ...slotColors,
        }}
      >
        {slots}
      </div>
      <div
        style={{
          fontWeight: 700,
          letterSpacing: "0.06em",
          textTransform: "uppercase",
          fontSize: 15,
          color: "var(--fg-1)",
        }}
      >
        {name}
      </div>
      {badge && (
        <span style={{ marginLeft: 6 }}>
          <Chip tone="caution">{badge}</Chip>
        </span>
      )}
      <div
        style={{
          marginLeft: "auto",
          fontFamily: "var(--font-mono)",
          fontSize: 11,
          color: "var(--fg-3)",
          letterSpacing: "0.06em",
        }}
      >
        SPD {speed} · HP {hp}
      </div>
    </div>
  );
}

// ============================================================
// Panel — square dark surface with header
// ============================================================
function Panel({ title, action, children, style }) {
  return (
    <section
      style={{
        background: "var(--bg-panel)",
        border: "1px solid #000",
        boxShadow: "0 0 0 1px var(--rule-faint) inset",
        ...style,
      }}
    >
      {title && (
        <header
          style={{
            padding: "8px 12px",
            display: "flex",
            alignItems: "center",
            gap: 8,
            borderBottom: "2px solid var(--rule)",
          }}
        >
          <span
            style={{
              fontFamily: "var(--font-ui)",
              fontWeight: 700,
              letterSpacing: "0.12em",
              textTransform: "uppercase",
              fontSize: 14,
              color: "var(--fg-1)",
            }}
          >
            {title}
          </span>
          {action && <div style={{ marginLeft: "auto" }}>{action}</div>}
        </header>
      )}
      <div style={{ padding: 12 }}>{children}</div>
    </section>
  );
}

Object.assign(window, { WeaponSlot, BeaconDot, BeaconStrip, Crosshair, MechRosterRow, Panel });
