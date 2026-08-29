// Hardpoint UI Kit — SignIn / Login. NEW screen.
// Two paths: PLAY AS GUEST (callsign → local profile.cfg) and SIGN IN
// (email account — gated OFFLINE until accounts are wired). Mirrors the
// terse military tone; no friendly second-person copy.

/* eslint-disable */

function SignInField({ label, value, type, placeholder, mono = true, disabled }) {
  return (
    <label style={{ display: "block" }}>
      <div style={{ fontFamily: "var(--font-ui)", fontSize: 11, letterSpacing: "0.18em", textTransform: "uppercase", color: "var(--fg-3)", marginBottom: 6 }}>
        {label}
      </div>
      <input
        defaultValue={value}
        type={type || "text"}
        placeholder={placeholder}
        disabled={disabled}
        style={{
          width: "100%",
          boxSizing: "border-box",
          background: disabled ? "var(--bg-void)" : "var(--bg-void)",
          border: "1px solid " + (disabled ? "var(--rule-faint)" : "var(--rule)"),
          color: disabled ? "var(--fg-dim)" : "var(--fg-1)",
          fontFamily: mono ? "var(--font-mono)" : "var(--font-ui)",
          fontSize: 15,
          padding: "11px 12px",
          letterSpacing: "0.04em",
          outline: "none",
        }}
      />
    </label>
  );
}

function SignIn() {
  return (
    <div
      data-screen-label="SignIn"
      style={{
        position: "relative",
        width: "100%",
        height: "100%",
        background: "var(--bg-void)",
        overflow: "hidden",
        color: "var(--fg-1)",
      }}
    >
      {/* vignette + scanline + hazard, matching TitleScreen */}
      <div style={{ position: "absolute", inset: 0, background: "radial-gradient(ellipse at 50% 80%, rgba(40,224,198,0.05), transparent 55%), radial-gradient(ellipse at 50% 0%, rgba(51,128,255,0.07), transparent 60%)" }} />
      <div style={{ position: "absolute", inset: 0, background: "repeating-linear-gradient(0deg, rgba(255,255,255,0.012) 0 1px, transparent 1px 3px)", pointerEvents: "none" }} />
      <div style={{ position: "absolute", top: 0, left: 0, right: 0, height: 8, background: "repeating-linear-gradient(135deg,#f7c948 0 14px,#1a1410 14px 28px)", opacity: 0.7 }} />
      <div style={{ position: "absolute", bottom: 0, left: 0, right: 0, height: 8, background: "repeating-linear-gradient(135deg,#f7c948 0 14px,#1a1410 14px 28px)", opacity: 0.7 }} />

      {/* top bar: wordmark + build */}
      <div style={{ position: "absolute", top: 28, left: 40, display: "flex", alignItems: "center", gap: 14 }}>
        <img src="../../assets/logo-mark.svg" width={40} height={40} style={{ imageRendering: "pixelated" }} alt="" />
        <div style={{ fontFamily: "var(--font-display)", fontSize: 24, letterSpacing: "0.06em" }}>
          HARD<span style={{ color: "var(--team-ally)" }}>POINT</span>
        </div>
      </div>
      <div style={{ position: "absolute", top: 30, right: 40, fontFamily: "var(--font-mono)", fontSize: 12, color: "var(--fg-3)", letterSpacing: "0.16em", textAlign: "right" }}>
        v0.6.2 · GODOT 4.6<br/>
        <span style={{ color: "var(--neon-cyan)" }}>AUTH</span> · LAN BUILD
      </div>

      {/* center stack */}
      <div style={{ position: "absolute", inset: 0, display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", gap: 28 }}>
        <div style={{ textAlign: "center" }}>
          <div style={{ fontFamily: "var(--font-display)", fontSize: 44, letterSpacing: "0.05em", lineHeight: 1 }}>IDENTIFY PILOT</div>
          <div style={{ fontFamily: "var(--font-mono)", fontSize: 12, color: "var(--fg-3)", letterSpacing: "0.34em", marginTop: 10 }}>
            SELECT AUTHENTICATION METHOD
          </div>
        </div>

        <div style={{ display: "flex", gap: 20, alignItems: "stretch" }}>
          {/* GUEST */}
          <Panel title="PLAY AS GUEST" style={{ width: 360, display: "flex", flexDirection: "column" }}>
            <div style={{ display: "flex", flexDirection: "column", gap: 16 }}>
              <SignInField label="PILOT CALLSIGN" value="VESPER-09" />
              <div style={{ fontFamily: "var(--font-ui)", fontSize: 12, lineHeight: 1.45, color: "var(--fg-3)", letterSpacing: "0.04em" }}>
                Progress, ELO and loadouts save locally to <span style={{ fontFamily: "var(--font-mono)", color: "var(--fg-2)" }}>profile.cfg</span>. No account required for solo or LAN play.
              </div>
              <MBButton variant="primary" style={{ padding: "13px 22px", fontSize: 15 }}>DEPLOY AS GUEST</MBButton>
            </div>
          </Panel>

          {/* SIGN IN */}
          <Panel
            title="SIGN IN"
            action={<Chip tone="caution">OFFLINE · NOT WIRED</Chip>}
            style={{ width: 360, display: "flex", flexDirection: "column" }}
          >
            <div style={{ display: "flex", flexDirection: "column", gap: 16, opacity: 0.78 }}>
              <SignInField label="EMAIL" value="" placeholder="pilot@domain" disabled />
              <SignInField label="ACCESS KEY" value="" type="password" placeholder="••••••••••••" disabled />
              <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between" }}>
                <label style={{ fontFamily: "var(--font-ui)", fontSize: 12, letterSpacing: "0.06em", color: "var(--fg-3)", display: "flex", gap: 8, alignItems: "center", textTransform: "uppercase" }}>
                  <span style={{ width: 16, height: 16, border: "1px solid var(--rule-faint)", display: "inline-block", background: "var(--bg-void)" }} /> REMEMBER PILOT
                </label>
                <span style={{ fontFamily: "var(--font-ui)", fontSize: 12, letterSpacing: "0.06em", color: "var(--fg-dim)", textTransform: "uppercase" }}>REQUEST ACCESS</span>
              </div>
              <MBButton disabled style={{ padding: "13px 22px", fontSize: 15 }}>SIGN IN</MBButton>
            </div>
          </Panel>
        </div>

        <div style={{ fontFamily: "var(--font-mono)", fontSize: 11, letterSpacing: "0.2em", color: "var(--fg-3)", textTransform: "uppercase" }}>
          [ ENTER ] CONFIRM · ACCOUNTS ARRIVE IN A LATER BUILD
        </div>
      </div>
    </div>
  );
}

Object.assign(window, { SignIn });
