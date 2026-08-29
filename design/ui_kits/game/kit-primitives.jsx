/* Hardpoint UI Kit — primitives. All Tailwind-free, pure CSS variables
   from ../../colors_and_type.css. Square corners, uppercase, military. */

/* eslint-disable */
const { useState, useEffect, useRef } = React;

// ============================================================
// Button
// ============================================================
function MBButton({ variant = "default", children, disabled, onClick, style }) {
  const base = {
    fontFamily: "var(--font-ui)",
    fontWeight: 700,
    letterSpacing: "0.1em",
    textTransform: "uppercase",
    padding: "10px 22px",
    border: "1px solid var(--rule)",
    background: "var(--bg-deep)",
    color: "var(--fg-1)",
    fontSize: "14px",
    cursor: disabled ? "not-allowed" : "pointer",
    transition: "all .12s ease",
    position: "relative",
    outline: "none",
  };
  const variants = {
    default: {},
    primary: {
      background: "var(--team-ally-dim)",
      borderColor: "var(--team-ally)",
      color: "#fff",
      boxShadow:
        "0 0 14px rgba(51,128,255,0.5), inset 0 0 0 1px rgba(255,255,255,0.05)",
    },
    danger: {
      background: "var(--oil)",
      borderColor: "var(--team-enemy-dim)",
      color: "var(--team-enemy-soft)",
    },
    ghost: {
      background: "transparent",
      borderColor: "var(--rule)",
      color: "var(--fg-2)",
    },
  };
  const dis = disabled
    ? { color: "var(--fg-dim)", borderColor: "var(--rule-faint)", background: "var(--bg-void)" }
    : {};
  return (
    <button
      className="mb-btn"
      disabled={disabled}
      onClick={onClick}
      style={{ ...base, ...variants[variant], ...dis, ...style }}
    >
      {children}
    </button>
  );
}

// ============================================================
// HudBar — value bar with optional readout
// ============================================================
function HudBar({ value, max, color = "var(--hp-full)", height = 22, label, readout, width }) {
  const pct = Math.max(0, Math.min(1, value / max));
  return (
    <div style={{ width }}>
      {label && (
        <div
          style={{
            fontFamily: "var(--font-ui)",
            fontSize: 11,
            letterSpacing: "0.18em",
            textTransform: "uppercase",
            color: "var(--fg-3)",
            marginBottom: 4,
          }}
        >
          {label}
        </div>
      )}
      <div
        style={{
          height,
          background: "var(--bg-bar)",
          border: "1px solid #000",
          position: "relative",
        }}
      >
        <div style={{ position: "absolute", inset: 0, width: pct * 100 + "%", background: color }} />
        {readout && (
          <div
            style={{
              position: "absolute",
              inset: 0,
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              fontFamily: "var(--font-mono)",
              fontSize: 12,
              color: "var(--bg-void)",
              mixBlendMode: "screen",
              letterSpacing: "0.06em",
            }}
          >
            {readout}
          </div>
        )}
      </div>
    </div>
  );
}

// ============================================================
// Chip — terse status tag (ALLY, ENEMY, [BOT], ELO 1842…)
// ============================================================
function Chip({ tone = "neutral", children, style }) {
  const tones = {
    neutral: { borderColor: "var(--rule)", color: "var(--fg-2)" },
    ally:    { borderColor: "var(--team-ally)", color: "var(--team-ally-soft)", background: "rgba(51,128,255,0.1)" },
    enemy:   { borderColor: "var(--team-enemy)", color: "var(--team-enemy-soft)", background: "rgba(255,77,51,0.1)" },
    bot:     { borderColor: "var(--rust)", color: "var(--rust)" },
    elo:     { borderColor: "var(--neon-cyan)", color: "var(--neon-cyan)" },
    caution: { borderColor: "var(--caution)", color: "var(--caution)" },
  };
  return (
    <span
      style={{
        display: "inline-block",
        padding: "3px 8px",
        fontFamily: "var(--font-mono)",
        fontSize: 10,
        letterSpacing: "0.12em",
        border: "1px solid",
        ...tones[tone],
        ...style,
      }}
    >
      {children}
    </span>
  );
}

// ============================================================
// Divider
// ============================================================
function Divider({ strong, vertical }) {
  if (vertical)
    return <div style={{ width: 2, alignSelf: "stretch", background: "var(--rule)" }} />;
  return (
    <div
      style={{
        height: strong ? 2 : 1,
        background: strong ? "var(--rule)" : "var(--rule-faint)",
        width: "100%",
      }}
    />
  );
}

// ============================================================
// Tab bar
// ============================================================
function Tabs({ tabs, active, onChange }) {
  return (
    <div style={{ display: "flex", borderBottom: "2px solid var(--rule)" }}>
      {tabs.map((t) => (
        <button
          key={t}
          onClick={() => onChange(t)}
          style={{
            fontFamily: "var(--font-ui)",
            fontWeight: 700,
            letterSpacing: "0.1em",
            textTransform: "uppercase",
            fontSize: 16,
            padding: "8px 18px",
            background: "transparent",
            border: "1px solid transparent",
            borderBottom: active === t ? "2px solid var(--team-ally)" : "2px solid transparent",
            marginBottom: -2,
            color: active === t ? "var(--fg-1)" : "var(--fg-3)",
            cursor: "pointer",
          }}
        >
          {t}
        </button>
      ))}
    </div>
  );
}

// ============================================================
// Label helpers
// ============================================================
function Micro({ children, style }) {
  return (
    <div
      style={{
        fontFamily: "var(--font-ui)",
        fontSize: 11,
        letterSpacing: "0.18em",
        textTransform: "uppercase",
        color: "var(--fg-3)",
        ...style,
      }}
    >
      {children}
    </div>
  );
}

function Readout({ children, color = "var(--fg-1)", size = 22, style }) {
  return (
    <div
      style={{
        fontFamily: "var(--font-mono)",
        fontSize: size,
        color,
        letterSpacing: "0.04em",
        ...style,
      }}
    >
      {children}
    </div>
  );
}

// export to window so other JSX scripts can use these
Object.assign(window, {
  MBButton,
  HudBar,
  Chip,
  Divider,
  Tabs,
  Micro,
  Readout,
});
