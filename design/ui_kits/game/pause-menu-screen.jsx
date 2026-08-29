// Hardpoint UI Kit — Pause menu. NEW screen.
// Modal over a dimmed/blurred HUD: scrim + centered PanelContainer with
// RESUME / SETTINGS / RETURN TO HANGAR / QUIT, plus live match status.

/* eslint-disable */

function PauseMenu() {
  return (
    <div data-screen-label="Pause" style={{ position: "relative", width: "100%", height: "100%", overflow: "hidden", color: "var(--fg-1)" }}>
      {/* dimmed HUD behind */}
      <div style={{ position: "absolute", inset: 0, filter: "blur(3px) saturate(0.7)", opacity: 0.5, pointerEvents: "none" }}>
        <HUD />
      </div>

      {/* scrim */}
      <div style={{ position: "absolute", inset: 0, background: "var(--bg-scrim)" }} />

      {/* centered panel */}
      <div style={{ position: "absolute", inset: 0, display: "flex", alignItems: "center", justifyContent: "center" }}>
        <div style={{ width: 420, background: "var(--bg-panel)", border: "1px solid #000", boxShadow: "0 0 0 1px var(--rule-faint) inset, 0 0 60px rgba(0,0,0,0.7)" }}>
          {/* hazard cap */}
          <div style={{ height: 6, background: "repeating-linear-gradient(135deg,#f7c948 0 12px,#1a1410 12px 24px)", opacity: 0.75 }} />

          <div style={{ padding: "26px 28px" }}>
            <div style={{ display: "flex", alignItems: "baseline", gap: 12, marginBottom: 4 }}>
              <div style={{ fontFamily: "var(--font-display)", fontSize: 40, letterSpacing: "0.06em", lineHeight: 1 }}>PAUSED</div>
              <div style={{ flex: 1 }} />
              <div style={{ fontFamily: "var(--font-mono)", fontSize: 12, color: "var(--fg-3)", letterSpacing: "0.16em" }}>02:14 LEFT</div>
            </div>
            <div style={{ fontFamily: "var(--font-mono)", fontSize: 12, color: "var(--fg-3)", letterSpacing: "0.12em", marginBottom: 20 }}>
              MATH TEMPLE · BEACON DRAIN
            </div>

            {/* mini score */}
            <div style={{ display: "flex", gap: 10, marginBottom: 22 }}>
              <div style={{ flex: 1, background: "var(--bg-deep)", border: "1px solid var(--rule-faint)", borderLeft: "3px solid var(--team-ally)", padding: "8px 12px" }}>
                <div style={{ fontFamily: "var(--font-ui)", fontSize: 10, letterSpacing: "0.18em", color: "var(--team-ally-soft)" }}>ALLY</div>
                <div style={{ fontFamily: "var(--font-mono)", fontSize: 22, color: "var(--fg-1)" }}>742</div>
              </div>
              <div style={{ flex: 1, background: "var(--bg-deep)", border: "1px solid var(--rule-faint)", borderLeft: "3px solid var(--team-enemy)", padding: "8px 12px" }}>
                <div style={{ fontFamily: "var(--font-ui)", fontSize: 10, letterSpacing: "0.18em", color: "var(--team-enemy-soft)" }}>ENEMY</div>
                <div style={{ fontFamily: "var(--font-mono)", fontSize: 22, color: "var(--fg-1)" }}>681</div>
              </div>
            </div>

            {/* actions */}
            <div style={{ display: "flex", flexDirection: "column", gap: 10 }}>
              <MBButton variant="primary" style={{ padding: "13px 22px", fontSize: 15 }}>RESUME</MBButton>
              <MBButton style={{ padding: "12px 22px", fontSize: 14 }}>SETTINGS</MBButton>
              <MBButton style={{ padding: "12px 22px", fontSize: 14 }}>RETURN TO HANGAR</MBButton>
              <MBButton variant="danger" style={{ padding: "12px 22px", fontSize: 14 }}>QUIT TO DESKTOP</MBButton>
            </div>

            <div style={{ fontFamily: "var(--font-mono)", fontSize: 11, letterSpacing: "0.18em", color: "var(--fg-3)", textAlign: "center", marginTop: 18 }}>
              [ ESC ] RESUME
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

Object.assign(window, { PauseMenu });
