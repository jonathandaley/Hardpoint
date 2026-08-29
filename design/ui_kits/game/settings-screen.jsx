// Hardpoint UI Kit — Settings. NEW screen.
// Section tabs (VIDEO / AUDIO / CONTROLS / GAMEPLAY); VIDEO shown active.
// Settings is the one place sentence-length tooltips are allowed (README).

/* eslint-disable */

function SetSlider({ label, value, pct, hint }) {
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 6 }}>
      <div style={{ display: "flex", alignItems: "baseline", gap: 8 }}>
        <div style={{ fontFamily: "var(--font-ui)", fontSize: 12, letterSpacing: "0.14em", textTransform: "uppercase", color: "var(--fg-2)", flex: 1 }}>{label}</div>
        <div style={{ fontFamily: "var(--font-mono)", fontSize: 13, color: "var(--neon-cyan)" }}>{value}</div>
      </div>
      <div style={{ height: 6, background: "var(--bg-void)", border: "1px solid var(--rule-faint)", position: "relative" }}>
        <div style={{ position: "absolute", left: 0, top: 0, bottom: 0, width: pct + "%", background: "var(--team-ally)" }} />
        <div style={{ position: "absolute", top: -5, left: "calc(" + pct + "% - 6px)", width: 12, height: 16, background: "var(--fg-1)", border: "1px solid #000" }} />
      </div>
      {hint && <div style={{ fontFamily: "var(--font-ui)", fontSize: 11, lineHeight: 1.4, color: "var(--fg-3)", letterSpacing: "0.03em" }}>{hint}</div>}
    </div>
  );
}

function SetToggle({ label, on, hint }) {
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 6 }}>
      <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
        <div style={{ fontFamily: "var(--font-ui)", fontSize: 12, letterSpacing: "0.14em", textTransform: "uppercase", color: "var(--fg-2)", flex: 1 }}>{label}</div>
        <div style={{ width: 46, height: 22, background: on ? "var(--team-ally-dim)" : "var(--bg-void)", border: "1px solid " + (on ? "var(--team-ally)" : "var(--rule)"), position: "relative", boxShadow: on ? "0 0 10px rgba(51,128,255,.4)" : "none" }}>
          <div style={{ position: "absolute", top: 1, bottom: 1, width: 18, left: on ? 25 : 1, background: on ? "var(--team-ally-soft)" : "var(--fg-dim)" }} />
        </div>
        <div style={{ fontFamily: "var(--font-mono)", fontSize: 12, color: on ? "var(--team-ally-soft)" : "var(--fg-3)", width: 28 }}>{on ? "ON" : "OFF"}</div>
      </div>
      {hint && <div style={{ fontFamily: "var(--font-ui)", fontSize: 11, lineHeight: 1.4, color: "var(--fg-3)", letterSpacing: "0.03em" }}>{hint}</div>}
    </div>
  );
}

function SetSelect({ label, value, hint }) {
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 6 }}>
      <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
        <div style={{ fontFamily: "var(--font-ui)", fontSize: 12, letterSpacing: "0.14em", textTransform: "uppercase", color: "var(--fg-2)", flex: 1 }}>{label}</div>
        <div style={{ minWidth: 180, display: "flex", alignItems: "center", justifyContent: "space-between", background: "var(--bg-void)", border: "1px solid var(--rule)", padding: "7px 11px", fontFamily: "var(--font-mono)", fontSize: 13, color: "var(--fg-1)", letterSpacing: "0.04em" }}>
          {value} <span style={{ color: "var(--fg-3)", marginLeft: 12 }}>▾</span>
        </div>
      </div>
      {hint && <div style={{ fontFamily: "var(--font-ui)", fontSize: 11, lineHeight: 1.4, color: "var(--fg-3)", letterSpacing: "0.03em" }}>{hint}</div>}
    </div>
  );
}

function Settings() {
  const [tab, setTab] = useState("VIDEO");
  return (
    <div data-screen-label="Settings" style={{ width: "100%", height: "100%", background: "var(--bg-void)", color: "var(--fg-1)", display: "flex", flexDirection: "column" }}>
      {/* header */}
      <div style={{ padding: "12px 18px", display: "flex", alignItems: "center", gap: 14, borderBottom: "2px solid var(--rule)" }}>
        <div style={{ fontFamily: "var(--font-display)", fontSize: 22, letterSpacing: "0.06em" }}>SETTINGS</div>
        <div style={{ flex: 1 }} />
        <Chip tone="caution">UNSAVED CHANGES</Chip>
      </div>

      {/* tabs */}
      <div style={{ padding: "0 18px", borderBottom: "2px solid var(--rule)" }}>
        <Tabs tabs={["VIDEO", "AUDIO", "CONTROLS", "GAMEPLAY"]} active={tab} onChange={setTab} />
      </div>

      {/* body */}
      <div style={{ flex: 1, padding: 18, display: "grid", gridTemplateColumns: "1fr 1fr", gap: 18, minHeight: 0, overflow: "auto" }}>
        {/* render */}
        <Panel title="RENDER">
          <div style={{ display: "flex", flexDirection: "column", gap: 18 }}>
            <SetSelect label="RESOLUTION" value="1280 × 720" />
            <SetSelect label="WINDOW MODE" value="FULLSCREEN" />
            <SetSlider label="RENDER SCALE" value="640 × 360" pct={50} hint="Internal viewport is rendered then nearest-neighbor upscaled. Lower keeps the chunky-pixel look and runs on T3500-class hardware." />
            <SetToggle label="VSYNC" on={true} hint="Caps frame rate to the display refresh. Applies on next match load." />
            <SetSelect label="FRAME CAP" value="60 FPS" />
          </div>
        </Panel>
        {/* image + preview */}
        <Panel title="IMAGE">
          <div style={{ display: "flex", flexDirection: "column", gap: 18 }}>
            <SetSlider label="FIELD OF VIEW" value="84°" pct={68} />
            <SetSlider label="BRIGHTNESS" value="1.05" pct={52} />
            <SetToggle label="BLOB SHADOWS" on={true} hint="The only shadow type — no real-time shadow maps (DESIGN.md locked non-goal)." />
            <SetToggle label="DAMAGE FLASH VIGNETTE" on={true} />
            <SetToggle label="CHROMATIC GRIME" on={false} hint="Adds a faint edge tint to the arena view. Off by default for clarity." />
          </div>
        </Panel>
      </div>

      {/* action bar */}
      <div style={{ padding: 18, borderTop: "2px solid var(--rule)", display: "flex", alignItems: "center", gap: 12 }}>
        <Micro>PROFILE · <span style={{ color: "var(--fg-1)" }}>VESPER-09</span> · WRITES TO profile.cfg</Micro>
        <div style={{ flex: 1 }} />
        <MBButton variant="ghost">RESET DEFAULTS</MBButton>
        <MBButton>REVERT</MBButton>
        <MBButton variant="primary" style={{ padding: "10px 34px" }}>APPLY</MBButton>
      </div>
    </div>
  );
}

Object.assign(window, { Settings });
