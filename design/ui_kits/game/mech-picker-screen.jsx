// Hardpoint UI Kit — MechPicker.
// The mech selection / loadout screen (formerly "Hangar"): top bar, tabs,
// roster column, schematic preview, loadout + skills. Kept as the picker;
// the lived-in repair-bay Hangar lives in Hangar.jsx.

/* eslint-disable */

const HANGAR_MECHS = [
  { name: "SLIP",       slots: "L",     hp: 120, speed: 12, klass: "LIGHT" },
  { name: "CESH",       slots: "L",     hp: 130, speed: 8,  klass: "LIGHT",  ability: "STEALTH" },
  { name: "SEEKER",     slots: "H",     hp: 140, speed: 9,  klass: "LIGHT" },
  { name: "HORNET",     slots: "L · L", hp: 180, speed: 10, klass: "MEDIUM" },
  { name: "HIPPOGRIFF", slots: "L · L · L", hp: 200, speed: 7, klass: "MEDIUM" },
  { name: "PEGASUS",    slots: "L · L", hp: 160, speed: 7,  klass: "MEDIUM", ability: "JUMP+HEAL" },
  { name: "EVEREST",    slots: "H · H", hp: 320, speed: 3,  klass: "HEAVY",  ability: "SHIELD" },
  { name: "VESUVIUS",   slots: "H · H · H", hp: 360, speed: 4, klass: "HEAVY" },
];

function HangarMechPreview({ mech }) {
  // Schematic mech "decal" — stencil outline, never a 3D render.
  return (
    <div
      style={{
        position: "relative",
        flex: 1,
        background:
          "radial-gradient(ellipse at 50% 70%, rgba(40,224,198,0.08), transparent 60%), var(--bg-deep)",
        border: "1px solid #000",
        boxShadow: "inset 0 0 60px rgba(0,0,0,0.7)",
        overflow: "hidden",
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
      }}
    >
      {/* grid floor */}
      <div
        style={{
          position: "absolute",
          inset: 0,
          background:
            "linear-gradient(to bottom, transparent 50%, rgba(40,224,198,0.05) 100%), repeating-linear-gradient(90deg, transparent 0 39px, rgba(40,224,198,0.07) 39px 40px), repeating-linear-gradient(0deg, transparent 0 39px, rgba(40,224,198,0.06) 39px 40px)",
          maskImage: "linear-gradient(to bottom, transparent 50%, #000 70%, #000 100%)",
        }}
      />
      {/* hazard frame */}
      <div
        style={{
          position: "absolute",
          inset: 8,
          border: "1px dashed var(--rust)",
          opacity: 0.35,
        }}
      />
      {/* schematic */}
      <svg viewBox="0 0 200 240" width="260" height="312" style={{ filter: "drop-shadow(0 0 20px rgba(51,128,255,0.4))" }}>
        <g stroke="var(--team-ally-soft)" strokeWidth="2" fill="none">
          {/* head */}
          <rect x="80" y="20" width="40" height="22" />
          <line x1="92" y1="26" x2="108" y2="26" stroke="var(--neon-cyan)" strokeWidth="3" />
          {/* torso */}
          <rect x="60" y="50" width="80" height="70" />
          <line x1="60" y1="80" x2="140" y2="80" />
          <line x1="100" y1="50" x2="100" y2="120" />
          {/* shoulders */}
          <rect x="35" y="55" width="22" height="50" />
          <rect x="143" y="55" width="22" height="50" />
          {/* arms / weapons */}
          <rect x="22" y="70" width="14" height="38" />
          <rect x="164" y="70" width="14" height="38" />
          {/* legs */}
          <rect x="65" y="125" width="28" height="70" />
          <rect x="107" y="125" width="28" height="70" />
          {/* feet */}
          <rect x="60" y="195" width="38" height="14" />
          <rect x="102" y="195" width="38" height="14" />
        </g>
        {/* hardpoint markers */}
        <g fill="var(--rust)">
          <rect x="22" y="68" width="14" height="2" />
          <rect x="164" y="68" width="14" height="2" />
        </g>
      </svg>
      {/* class watermark */}
      <div
        style={{
          position: "absolute",
          bottom: 12,
          left: 16,
          fontFamily: "var(--font-display)",
          fontSize: 56,
          color: "rgba(255,255,255,0.04)",
          letterSpacing: "0.1em",
          lineHeight: 1,
        }}
      >
        {mech.klass}
      </div>
      <div style={{ position: "absolute", bottom: 10, right: 12, fontFamily: "var(--font-mono)", fontSize: 11, color: "var(--fg-3)", letterSpacing: "0.14em" }}>
        UNIT_ID 04 · CHASSIS {mech.name}
      </div>
    </div>
  );
}

function MechPicker({ onPlay, onSettings }) {
  const [tab, setTab] = useState("MECH");
  const [selectedIdx, setSelectedIdx] = useState(3);
  const mech = HANGAR_MECHS[selectedIdx];

  return (
    <div
      data-screen-label="MechPicker"
      style={{
        background: "var(--bg-void)",
        color: "var(--fg-1)",
        width: "100%",
        height: "100%",
        display: "flex",
        flexDirection: "column",
        position: "relative",
      }}
    >
      {/* top bar */}
      <div
        style={{
          padding: "12px 18px",
          display: "flex",
          alignItems: "center",
          gap: 14,
          borderBottom: "2px solid var(--rule)",
        }}
      >
        <img src="../../assets/logo-mark.svg" width={28} height={28} style={{ imageRendering: "pixelated" }} alt="" />
        <div style={{ fontFamily: "var(--font-display)", fontSize: 22, letterSpacing: "0.06em" }}>SELECT MECH</div>
        <div style={{ flex: 1 }} />
        <Chip tone="elo">ELO 1842</Chip>
        <Chip tone="caution">COINS 8,420</Chip>
        <Chip>WINS 47 · LOSSES 31</Chip>
        <div style={{ fontFamily: "var(--font-ui)", fontWeight: 600, fontSize: 16, letterSpacing: "0.1em", color: "var(--fg-1)" }}>
          PILOT · <span style={{ color: "var(--neon-cyan)" }}>VESPER-09</span>
        </div>
      </div>

      {/* tabs */}
      <div style={{ padding: "0 18px", borderBottom: "2px solid var(--rule)" }}>
        <Tabs tabs={["MECH", "PILOT", "SKILL TREE", "PROFILE"]} active={tab} onChange={setTab} />
      </div>

      {/* body */}
      <div style={{ flex: 1, padding: 18, display: "grid", gridTemplateColumns: "280px 1fr 280px", gap: 14, minHeight: 0 }}>
        {/* left: squad */}
        <div style={{ display: "flex", flexDirection: "column", minHeight: 0 }}>
          <Micro>YOUR SQUAD · 5 LIVES</Micro>
          <div style={{ marginTop: 8, overflow: "auto", flex: 1 }}>
            {HANGAR_MECHS.map((m, i) => (
              <MechRosterRow
                key={m.name}
                name={m.name}
                slots={m.slots}
                hp={m.hp}
                speed={m.speed}
                active={i === selectedIdx}
                badge={i < 5 ? `SLOT ${i + 1}` : null}
                onSelect={() => setSelectedIdx(i)}
              />
            ))}
          </div>
        </div>

        {/* center: preview */}
        <div style={{ display: "flex", flexDirection: "column", gap: 10, minHeight: 0 }}>
          <HangarMechPreview mech={mech} />
          <div style={{ display: "flex", alignItems: "center", gap: 16 }}>
            <div>
              <div style={{ fontFamily: "var(--font-display)", fontSize: 32, letterSpacing: "0.06em", lineHeight: 1 }}>
                {mech.name}
              </div>
              <div style={{ fontFamily: "var(--font-mono)", fontSize: 12, color: "var(--fg-3)", letterSpacing: "0.2em", marginTop: 4 }}>
                CLASS {mech.klass} · SLOTS {mech.slots}
              </div>
            </div>
            <div style={{ marginLeft: "auto", display: "flex", gap: 8 }}>
              {mech.ability && <Chip tone="caution">{mech.ability}</Chip>}
              <Chip>HP {mech.hp}</Chip>
              <Chip>SPD {mech.speed}</Chip>
            </div>
          </div>
        </div>

        {/* right: loadout */}
        <div style={{ display: "flex", flexDirection: "column", gap: 14, minHeight: 0 }}>
          <Panel title="LOADOUT">
            <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
              {mech.slots.split(" · ").map((s, i) => (
                <div
                  key={i}
                  style={{
                    display: "flex",
                    alignItems: "center",
                    gap: 8,
                    padding: "6px 8px",
                    background: "var(--bg-deep)",
                    border: "1px solid var(--rule-faint)",
                  }}
                >
                  <Chip tone={s === "H" ? "bot" : "neutral"}>{s}</Chip>
                  <div style={{ fontFamily: "var(--font-ui)", fontSize: 13, letterSpacing: "0.08em", textTransform: "uppercase" }}>
                    {["RIFLE", "MGUN", "SNIPER"][i % 3]} {s}
                  </div>
                  <div style={{ marginLeft: "auto", fontFamily: "var(--font-mono)", fontSize: 11, color: "var(--fg-3)" }}>
                    {[12, 30, 4][i % 3]} / mag
                  </div>
                </div>
              ))}
            </div>
          </Panel>
          <Panel title="PILOT SKILLS · 3 SP">
            <div style={{ display: "flex", flexDirection: "column", gap: 6 }}>
              {[
                ["DAMAGE", 4, "+6.0%"],
                ["HEALTH", 3, "+6.0%"],
                ["RELOAD SPEED", 2, "+8.0%"],
                ["LOCK SPEED", 1, "+5.0%"],
              ].map((row) => (
                <div key={row[0]} style={{ display: "flex", alignItems: "center", gap: 8, fontSize: 12, fontFamily: "var(--font-mono)" }}>
                  <span style={{ color: "var(--fg-2)", letterSpacing: "0.08em", flex: 1 }}>{row[0]}</span>
                  <span style={{ color: "var(--neon-cyan)" }}>L{row[1]}/12</span>
                  <span style={{ color: "var(--fg-3)" }}>{row[2]}</span>
                </div>
              ))}
            </div>
          </Panel>
        </div>
      </div>

      {/* bottom action bar */}
      <div
        style={{
          padding: 18,
          borderTop: "2px solid var(--rule)",
          display: "flex",
          alignItems: "center",
          gap: 12,
        }}
      >
        <Micro>SP STATUS: <span style={{ color: "var(--hp-full)" }}>READY</span> · MAP <span style={{ color: "var(--fg-1)" }}>MATH TEMPLE</span> · 5 BEACONS</Micro>
        <div style={{ flex: 1 }} />
        <MBButton variant="ghost" onClick={onSettings}>SETTINGS</MBButton>
        <MBButton variant="primary" onClick={onPlay} style={{ padding: "12px 32px" }}>
          FIND MATCH
        </MBButton>
      </div>
    </div>
  );
}

Object.assign(window, { MechPicker });
