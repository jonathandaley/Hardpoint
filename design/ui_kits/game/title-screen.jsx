// Hardpoint UI Kit — TitleScreen.
// Mirrors scenes/ui/TitleScreen.tscn — minimal: title + 2 buttons + bg.

/* eslint-disable */

function TitleScreen({ onSingleplayer, onMultiplayer, onSettings }) {
  return (
    <div
      data-screen-label="Title"
      style={{
        position: "relative",
        width: "100%",
        height: "100%",
        background: "var(--bg-void)",
        overflow: "hidden",
        color: "var(--fg-1)",
      }}
    >
      {/* faint hangar floor vignette */}
      <div
        style={{
          position: "absolute",
          inset: 0,
          background:
            "radial-gradient(ellipse at 50% 75%, rgba(40,224,198,0.05), transparent 55%), radial-gradient(ellipse at 50% 0%, rgba(255,77,51,0.08), transparent 60%)",
        }}
      />
      {/* scanline */}
      <div
        style={{
          position: "absolute",
          inset: 0,
          background:
            "repeating-linear-gradient(0deg, rgba(255,255,255,0.012) 0 1px, transparent 1px 3px)",
          pointerEvents: "none",
        }}
      />
      {/* hazard strip top */}
      <div
        style={{
          position: "absolute",
          top: 0,
          left: 0,
          right: 0,
          height: 8,
          background:
            "repeating-linear-gradient(135deg,#f7c948 0 14px,#1a1410 14px 28px)",
          opacity: 0.7,
        }}
      />

      {/* version stamp */}
      <div
        style={{
          position: "absolute",
          top: 20,
          right: 20,
          fontFamily: "var(--font-mono)",
          fontSize: 12,
          color: "var(--fg-3)",
          letterSpacing: "0.16em",
          textAlign: "right",
        }}
      >
        v0.6.2 · GODOT 4.6<br/>
        <span style={{ color: "var(--neon-cyan)" }}>PILOT</span> VESPER-09 · ELO 1842
      </div>

      {/* center stack */}
      <div
        style={{
          position: "absolute",
          inset: 0,
          display: "flex",
          flexDirection: "column",
          alignItems: "center",
          justifyContent: "center",
          gap: 36,
        }}
      >
        <div style={{ display: "flex", alignItems: "center", gap: 24 }}>
          <img src="../../assets/logo-mark.svg" width={96} height={96} style={{ imageRendering: "pixelated" }} alt="" />
          <div>
            <div
              style={{
                fontFamily: "var(--font-display)",
                fontSize: 96,
                letterSpacing: "0.06em",
                lineHeight: 0.95,
                textShadow: "0 0 32px rgba(51,128,255,0.25)",
              }}
            >
              HARD<span style={{ color: "var(--team-ally)" }}>POINT</span>
            </div>
          </div>
        </div>

        <div style={{ display: "flex", flexDirection: "column", gap: 12, width: 320 }}>
          <MBButton variant="primary" onClick={onSingleplayer} style={{ padding: "14px 22px", fontSize: 16 }}>
            SINGLEPLAYER
          </MBButton>
          <MBButton onClick={onMultiplayer} style={{ padding: "14px 22px", fontSize: 16 }}>
            MULTIPLAYER · LAN
          </MBButton>
          <MBButton variant="ghost" onClick={onSettings} style={{ padding: "10px 22px", fontSize: 13 }}>
            SETTINGS
          </MBButton>
        </div>

        <div
          style={{
            fontFamily: "var(--font-mono)",
            fontSize: 11,
            letterSpacing: "0.2em",
            color: "var(--fg-3)",
            textTransform: "uppercase",
          }}
        >
          [ ESC ] RELEASE MOUSE · [ ENTER ] CONFIRM
        </div>
      </div>

      {/* bottom hazard */}
      <div
        style={{
          position: "absolute",
          bottom: 0,
          left: 0,
          right: 0,
          height: 8,
          background:
            "repeating-linear-gradient(135deg,#f7c948 0 14px,#1a1410 14px 28px)",
          opacity: 0.7,
        }}
      />
    </div>
  );
}

Object.assign(window, { TitleScreen });
