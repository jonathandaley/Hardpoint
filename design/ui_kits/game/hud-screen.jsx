// Hardpoint UI Kit — in-match HUD.
// Mirrors scripts/HUD.gd: top-left HP/shield, top-center beacon strip,
// bottom-right weapon slots, center crosshair, bot world-space bars.
// 3D view is a stylized stand-in for the arena render.

/* eslint-disable */

function ArenaView() {
  return (
    <div
      style={{
        position: "absolute",
        inset: 0,
        background:
          "linear-gradient(180deg, #1a1a22 0%, #14141a 38%, #0d0d14 72%, #1a1410 100%)",
        overflow: "hidden",
      }}
    >
      {/* sky bands */}
      <div
        style={{
          position: "absolute",
          inset: 0,
          background:
            "radial-gradient(ellipse at 60% 35%, rgba(40,224,198,0.06), transparent 50%), radial-gradient(ellipse at 30% 65%, rgba(255,77,51,0.06), transparent 60%)",
        }}
      />
      {/* horizon mountains */}
      <svg viewBox="0 0 1280 360" width="100%" height="360" style={{ position: "absolute", top: "30%", left: 0 }}>
        <polygon points="0,360 0,260 120,180 220,240 320,140 460,220 580,170 720,250 880,180 1000,240 1140,160 1280,220 1280,360" fill="#0d0d14" stroke="#1a1a22" />
        <polygon points="0,360 0,300 100,260 200,280 320,240 460,290 600,250 760,290 900,260 1060,300 1200,250 1280,290 1280,360" fill="#1a1410" opacity="0.85" />
      </svg>
      {/* arena floor */}
      <div
        style={{
          position: "absolute",
          bottom: 0,
          left: 0,
          right: 0,
          height: "45%",
          background:
            "linear-gradient(180deg, transparent 0%, #0a0a10 100%), repeating-linear-gradient(0deg, transparent 0 28px, rgba(40,224,198,0.05) 28px 30px)",
          perspective: "600px",
        }}
      >
        <div
          style={{
            position: "absolute",
            inset: 0,
            background:
              "repeating-linear-gradient(90deg, transparent 0 60px, rgba(255,255,255,0.04) 60px 61px)",
            transform: "perspective(400px) rotateX(60deg)",
            transformOrigin: "top",
          }}
        />
      </div>
      {/* beacon beam */}
      <div
        style={{
          position: "absolute",
          left: "62%",
          bottom: "12%",
          width: 6,
          height: 360,
          background:
            "linear-gradient(180deg, transparent, var(--team-ally) 60%, var(--team-ally))",
          boxShadow: "0 0 30px var(--team-ally)",
          opacity: 0.6,
        }}
      />
      <div
        style={{
          position: "absolute",
          left: "18%",
          bottom: "20%",
          width: 4,
          height: 280,
          background:
            "linear-gradient(180deg, transparent, var(--team-enemy) 60%, var(--team-enemy))",
          boxShadow: "0 0 20px var(--team-enemy)",
          opacity: 0.6,
        }}
      />

      {/* enemy mech silhouette (read: opaque dark, no normal maps) */}
      <svg viewBox="0 0 200 240" width={120} height={144} style={{ position: "absolute", left: "44%", top: "52%" }}>
        <g fill="#1a1a22" stroke="#000" strokeWidth="1.5">
          <rect x="60" y="50" width="80" height="70" />
          <rect x="80" y="20" width="40" height="22" />
          <rect x="35" y="55" width="22" height="50" />
          <rect x="143" y="55" width="22" height="50" />
          <rect x="22" y="70" width="14" height="38" />
          <rect x="164" y="70" width="14" height="38" />
          <rect x="65" y="125" width="28" height="70" />
          <rect x="107" y="125" width="28" height="70" />
        </g>
        <rect x="92" y="26" width="16" height="3" fill="var(--team-enemy)" />
      </svg>
      {/* ally mech further back */}
      <svg viewBox="0 0 200 240" width={66} height={80} style={{ position: "absolute", left: "70%", top: "60%", opacity: 0.85 }}>
        <g fill="#101820" stroke="#000" strokeWidth="1.5">
          <rect x="60" y="50" width="80" height="70" />
          <rect x="80" y="20" width="40" height="22" />
          <rect x="65" y="125" width="28" height="70" />
          <rect x="107" y="125" width="28" height="70" />
        </g>
        <rect x="92" y="26" width="16" height="3" fill="var(--team-ally)" />
      </svg>
    </div>
  );
}

function HUD({ onPause }) {
  // animated tick — bots take damage / score drifts
  const [tick, setTick] = useState(0);
  useEffect(() => {
    const id = setInterval(() => setTick((t) => t + 1), 600);
    return () => clearInterval(id);
  }, []);

  const scoreA = 742 - Math.floor(tick * 0.5);
  const scoreB = 681 - Math.floor(tick * 0.9);

  return (
    <div
      data-screen-label="HUD"
      style={{
        position: "relative",
        width: "100%",
        height: "100%",
        overflow: "hidden",
        color: "var(--fg-1)",
        cursor: "none",
      }}
    >
      <ArenaView />

      {/* === TOP-LEFT — player stack === */}
      <div style={{ position: "absolute", top: 24, left: 24, display: "flex", flexDirection: "column", gap: 8 }}>
        <HudBar value={142} max={240} color="var(--hp-full)" height={22} width={260} readout="142 / 240" />
        <HudBar value={48} max={100} color="var(--shield)" height={14} width={260} />
        <div style={{ fontFamily: "var(--font-ui)", fontSize: 12, color: "var(--neon-cyan)", letterSpacing: "0.18em", marginTop: 2 }}>
          SPACE · JUMP+HEAL · <span style={{ color: "var(--hp-full)" }}>READY</span>
        </div>
        <div style={{ marginTop: 8, display: "flex", gap: 6 }}>
          <Chip tone="ally">PEGASUS</Chip>
          <Chip>LIFE 2 / 5</Chip>
        </div>
      </div>

      {/* === TOP-CENTER — beacon strip === */}
      <div style={{ position: "absolute", top: 16, left: "50%", transform: "translateX(-50%)" }}>
        <BeaconStrip
          beacons={[
            { state: 0 },
            { state: 2, capTeam: 0, progress: 0.65 },
            { state: -1, capTeam: 0, progress: 0.4 },
            { state: 1 },
            { state: 1 },
          ]}
          scoreA={scoreA}
          scoreB={scoreB}
          aliveA={3}
          totalA={5}
          aliveB={4}
          totalB={5}
        />
      </div>

      {/* === TOP-RIGHT — kill feed / mini scoreboard === */}
      <div
        style={{
          position: "absolute",
          top: 24,
          right: 24,
          fontFamily: "var(--font-mono)",
          fontSize: 12,
          letterSpacing: "0.06em",
          textAlign: "right",
          display: "flex",
          flexDirection: "column",
          gap: 4,
        }}
      >
        <div>
          <span style={{ color: "var(--team-ally-soft)" }}>VESPER-09</span>{" "}
          <span style={{ color: "var(--fg-3)" }}>›</span>{" "}
          <span style={{ color: "var(--rust)" }}>[BOT] HORNET-02</span>
        </div>
        <div>
          <span style={{ color: "var(--rust)" }}>[BOT] EVEREST-01</span>{" "}
          <span style={{ color: "var(--fg-3)" }}>›</span>{" "}
          <span style={{ color: "var(--team-enemy-soft)" }}>BIRCH</span>
        </div>
        <div style={{ opacity: 0.6 }}>
          <span style={{ color: "var(--team-ally-soft)" }}>SLIP-03</span>{" "}
          <span style={{ color: "var(--fg-3)" }}>›</span>{" "}
          <span style={{ color: "var(--rust)" }}>[BOT] CESH-05</span>
        </div>
        <div style={{ marginTop: 10, color: "var(--fg-3)", letterSpacing: "0.2em" }}>02:14 LEFT</div>
      </div>

      {/* === WORLD-SPACE BOT BAR over enemy mech === */}
      <div style={{ position: "absolute", left: "47%", top: "47%" }}>
        <div style={{ fontFamily: "var(--font-mono)", fontSize: 10, color: "var(--team-enemy-soft)", letterSpacing: "0.14em", textAlign: "center", marginBottom: 3 }}>
          HORNET-02
        </div>
        <div style={{ width: 64, height: 6, background: "rgba(0,0,0,0.85)", border: "1px solid #000", position: "relative" }}>
          <div style={{ position: "absolute", inset: 0, width: "38%", background: "var(--hp-enemy)" }} />
        </div>
      </div>

      {/* === CENTER crosshair === */}
      <div style={{ position: "absolute", left: "50%", top: "50%", transform: "translate(-50%,-50%)" }}>
        <Crosshair state="locked" />
      </div>
      <div style={{ position: "absolute", left: "50%", top: "calc(50% + 50px)", transform: "translateX(-50%)", fontFamily: "var(--font-mono)", fontSize: 11, color: "var(--team-enemy)", letterSpacing: "0.18em" }}>
        LOCK 1.00 · 84m
      </div>

      {/* === BOTTOM-RIGHT — weapon slots === */}
      <div style={{ position: "absolute", bottom: 24, right: 24, display: "flex", gap: 8 }}>
        <WeaponSlot slot="1" name="RIFLE L" glyph="█▌" ammoPct={0.78} active />
        <WeaponSlot slot="2" name="SNIPER L" glyph="▙█" ammoPct={0.33} />
        <WeaponSlot slot="3" name="MGUN L" glyph="▞▚" ammoPct={0.55} reload />
        <WeaponSlot slot="4" name="MISSILE H" glyph="◤◣" ammoPct={1} dim />
      </div>

      {/* === BOTTOM-LEFT — minimap === */}
      <div style={{ position: "absolute", bottom: 24, left: 24, width: 160, height: 160, background: "rgba(13,13,20,0.7)", border: "1px solid var(--rule)", position: "absolute" }}>
        <Micro style={{ position: "absolute", top: 4, left: 6 }}>MATH TEMPLE</Micro>
        {/* beacons */}
        <div style={{ position: "absolute", left: "20%", top: "70%", width: 8, height: 8, background: "var(--team-ally)", borderRadius: "50%", boxShadow: "0 0 6px var(--team-ally)" }} />
        <div style={{ position: "absolute", left: "55%", top: "60%", width: 8, height: 8, background: "var(--caution)", borderRadius: "50%", boxShadow: "0 0 6px var(--caution)" }} />
        <div style={{ position: "absolute", left: "50%", top: "40%", width: 8, height: 8, background: "var(--bg-raised)", borderRadius: "50%" }} />
        <div style={{ position: "absolute", left: "80%", top: "30%", width: 8, height: 8, background: "var(--team-enemy)", borderRadius: "50%", boxShadow: "0 0 6px var(--team-enemy)" }} />
        <div style={{ position: "absolute", left: "70%", top: "70%", width: 8, height: 8, background: "var(--team-enemy)", borderRadius: "50%", boxShadow: "0 0 6px var(--team-enemy)" }} />
        {/* player triangle */}
        <svg viewBox="-10 -10 20 20" width="14" height="14" style={{ position: "absolute", left: "40%", top: "55%", transform: "rotate(35deg)" }}>
          <polygon points="0,-7 6,5 -6,5" fill="var(--team-ally)" stroke="#000" />
        </svg>
      </div>

      {/* === ESC hint === */}
      <button
        onClick={onPause}
        style={{
          position: "absolute",
          top: 16,
          left: "50%",
          transform: "translateX(-50%) translateY(60px)",
          background: "transparent",
          border: "none",
          fontFamily: "var(--font-ui)",
          fontSize: 10,
          letterSpacing: "0.3em",
          color: "var(--fg-3)",
          textTransform: "uppercase",
          cursor: "pointer",
        }}
      >
        [ ESC ] PAUSE · RETURN TO HANGAR
      </button>
    </div>
  );
}

Object.assign(window, { HUD });
