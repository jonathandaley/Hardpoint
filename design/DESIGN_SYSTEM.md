# Hardpoint — Design System

A reference kit for **Hardpoint**, a third-person mech-arena FPS with a beacon-drain win condition. This pack distills the game's visual + interaction vocabulary so designers (and Claude) can produce on-brand mocks, slides, and marketing pages without re-reading the entire Godot source tree each time.

> "Guns, grease, grit, gears." — SPEC.md §G

---

## What Hardpoint is

- **Genre:** third-person-shooter / beacon-control with massive, ponderous mechs and big guns. War-Robots-adjacent gameplay, distinct visual identity.
- **Engine:** Godot 4.6, Compatibility renderer (OpenGL ES 3.0). Targets low-end hardware (T3500-class).
- **Resolution:** chunky-pixel 3D — internal viewport 640 × 360, nearest-neighbor scaled to 1280 × 720. The UI inherits that grid.
- **Art direction:** Matrix-3 post-apocalyptic steam/cyberpunk. Rust, neon, grime, gears, mechanical bulk. Maps vary in theme (math temple, badlands, ironworks).
- **8 mechs** across Light / Medium / Heavy classes with optional abilities (Slip, Cesh, Seeker, Hornet, Hippogriff, Pegasus, Everest, Vesuvius).
- **15 weapons** across two slot sizes; LMB fires all, RMB fires a toggleable subset.

The game is single-player vs bots first; LAN multiplayer is wired but gated on the solo loop feeling good. Persistence is local (`user://profile.cfg`) with peer-broadcast ELO.

---

## Sources used to build this kit

Everything below was distilled from the project repository:

- **GitHub:** [github.com/jonathandaley/Hardpoint](https://github.com/jonathandaley/Hardpoint) — private, default branch `main`.
  - `README.md` — controls, mech roster, project layout
  - `DESIGN.md` — architecture + locked non-goals (no normal maps, no transparent materials, pixel-art atlases, blob shadows only)
  - `SPEC.md` — invariants V1–V41, tasks T1–T132, bug log; the canonical "why + what"
  - `GRAPHICS_PLAN.md` — graphics tasks, draw-call budgets, palette rules
  - `MP_PLAN.md` — multiplayer phase plan
  - `icon.svg` — project icon → `assets/logo-mark.svg`
  - `scenes/ui/*.tscn` — `TitleScreen`, `Hangar`, `HUD`, `Lobby`, `Settings`, `MPEntry`, `PauseMenu`, `SignIn`
  - `scripts/HUD.gd` — HUD layout numbers, color constants, bar geometries

There are no Figma files; the codebase is the source of truth.

**Encourage the reader:** the repo is the canonical reference for in-game asset specs (mech palettes, weapon slot rules, beacon mechanics). When making real production work, browse it — the SPEC's `§V` invariants will save you from regressions.

---

## Index

| File | What's in it |
|---|---|
| `README.md` | This document. Brand context + foundations + content + iconography rules. |
| `colors_and_type.css` | CSS variables for every color, font family, type size, spacing, shadow. Import in any mock. |
| `SKILL.md` | Agent-skill front-matter so this kit works inside Claude Code. |
| `assets/logo-mark.svg` | The project mark (128px, Pegasus mech bust in a targeting reticle). |
| `preview/*.html` | Small specimen cards for the Design System tab — colors, type, components, brand. |
| `ui_kits/game/` | High-fidelity HTML+JSX recreation of the game's UI screens (TitleScreen, Hangar, HUD). |

---

## Content fundamentals

The UI never addresses the player in friendly second-person. Copy is **terse, military, mechanical**.

- **Casing:** every label is `UPPERCASE` with wide tracking. Body prose (rare) is sentence case.
- **Voice:** imperative or stative. "SELECT NEXT MECH", "READY UP", "FIND MATCH", "SPECTATING ALLY: HORNET", "YOU WIN" / "YOU LOSE".
- **Pronouns:** zero. The HUD does not say "your health"; it says `HP 142 / 240`.
- **Numbers:** always digits, never words. Distance in `m`, time in `s` or `0.7s`, damage as raw int.
- **No emoji.** No exclamation marks. No "✨" or friendly UX flourishes.
- **Bracket tags** for status: `[BOT]`, `[DC]`, `[LOCKED]`. Used in scoreboards and lobby rows.
- **Sentence-length tooltips** (rare, in Settings only) — explain what changes when and where the change takes effect, nothing more.

Example pairs (game copy → throwaway equivalent):

| Hardpoint voice | Avoid |
|---|---|
| `FIND MATCH` | "Let's play!" |
| `RETURN TO HANGAR` | "Back to menu" |
| `YOU LOSE` | "Better luck next time 😅" |
| `LOCK 0.72s` | "Locking on…" |
| `[BOT]` row in scoreboard | "Computer player" |

---

## Visual foundations

### Color
The palette is **dark, oily, gun-metal navy** with two violently saturated signal channels (team blue, team red) and three industrial accents (rust, caution-yellow, neon-cyan). All hex values live in `colors_and_type.css`.

- **Backgrounds:** `--bg-void #0d0d14` is the floor; raise in steps of `--bg-deep #14141a` → `--bg-panel #1a1a22` → `--bg-raised #232330`. Never use plain black.
- **Teams:** local team is **always** `--team-ally #3380ff`; opposing team is **always** `--team-enemy #ff4d33` (V122 in SPEC). Never swap, never green-vs-red.
- **HUD signal:** health `--hp-full #00ff33`, shield `--shield #3380ff`, damage flash `--damage-flash #cc0000` with α tween.
- **Industrial accents:** `--rust #b85c2a`, `--caution #f7c948`, `--neon-cyan #28e0c6`, `--oil #1a1410`. Used sparingly — borders, lock-on glow, hazard chevrons.

### Type
Three families, all from Google Fonts (the game ships Godot's default; we substitute — see Substitutions below).

- **Display — `Black Ops One`**: blocky stencil, UPPERCASE, 32–80px. Title screen and match-end headers only.
- **UI — `Chakra Petch`**: condensed geometric sans, 11–28px. Tabs, body, button labels.
- **Mono — `Share Tech Mono`**: HUD readouts, peer IDs, weapon stats. Anything that's a number.
- **Pixel — `VT323`**: optional accent for beacon-state labels, kill-feed, retro overlays. Use sparingly.

Letter-spacing is generous everywhere (.04–.18em). Body line-height ~1.45; uppercase labels 1.1.

### Spacing & shape
- **4px grid.** All padding, gaps, and offsets are multiples of 4 — mirrors the Godot scenes' `offset_left/top` values.
- **Square corners.** `--radius-0` is the default. The only allowed radius is `--radius-2` (2 px) on HUD bar end caps. No pill buttons, no rounded cards.
- **Dividers:** 2px `--rule #4d4d4d` for primary section separators (matches the `ColorRect` rules used in `Hangar.tscn`, `Settings.tscn`); 1px hairlines inside cards.

### Backgrounds & imagery
- **Backgrounds are solid color or extremely low-contrast vignettes.** No gradients in flat UI surfaces. The 3D game view itself is the "image".
- **Imagery is in-engine 3D screenshots, never illustrations.** Pixel-art atlases at 128–256 px, nearest-neighbor sampled. Colors stay within the gun-metal + accent palette.
- **No bluish-purple gradients. No hand-drawn illustrations. No emoji cards.** Mood comes from grime + flat shading + saturated neon, not photoshop.
- **Full-bleed marketing imagery should be desaturated apart from neon HUD pickups** (lock-on cyan, beacon team colors).

### Borders, shadows, glow
- **Outer shadow:** 1px black inset + 2px solid drop. Cards look pressed into the panel, not floated.
- **Inner shadow vignette:** used only for the full-screen damage flash (`--damage-flash`) and the lock-on indicator.
- **Glow:** team color, lock cyan, caution yellow. ~12–14px blur. Used on active buttons, locked targets, hazard chevrons. Never on neutral chrome.

### Layout rules
- **Fixed UI canvas reference:** 640 × 360. Everything scales by 2× on real screens. Min-tap is 32 × 32 in game units (~64 in 2× pixels).
- **Top-left:** player health + shield + ability label.
- **Top-center:** beacon dots and team score bars.
- **Top-right:** kill-feed / multiplayer scoreboard toggle.
- **Bottom-right:** weapon slots 1–4 (active subset highlighted).
- **Bottom-center:** crosshair, lock progress, eligible-target indicator.
- **Modal overlays** (squad picker, settings, match-end) fade in a `--bg-scrim` and center a `PanelContainer`.

### Animation
- **Tween over keyframes.** All FX is opaque emissive + Tween (V7) — no transparent materials, no particle-system reliance.
- **Damage flash:** alpha 0.45 → 0 over ~225 ms. Use the same on hit-spark VFX.
- **Hover states (UI):** 120 ms color shift to next-lighter surface. No scale.
- **Active states:** instant — no transition. The game runs at low resolution and high tempo; press is its own animation.
- **No bounces. No spring overshoot. No parallax. No looping background sweeps.**

### Transparency & blur
- **Transparency is permitted in HTML mocks but never in 3D materials** (V7).
- **Blur is rare.** Use only for the squad-picker scrim (~10px) or the title screen background. Never on HUD chrome.

---

## Iconography

### What ships with the codebase
- `icon.svg` (now `assets/logo-mark.svg`) — a 128×128 flat-shaded Pegasus mech bust (three-blade crest, gold visor and heal core) inside a blue targeting reticle. The only "logo" the project owns.
- **No icon font.** No SVG sprite. No PNG icon set. The Godot HUD uses **typography and ColorRects only** — health bars, score bars, beacon dots are all drawn as colored rectangles or `_draw()` calls.

### How we substitute
Because the codebase has no icon set, this kit ships a small **hand-drawn 2-px-stroke SVG glyph collection** in `preview/brand-iconography.html`. Specs:

- 24×24 viewBox, 2 px stroke, **butt** caps, **miter** joins (no rounding).
- Single-color outline (`--fg-2` default; tint to `--team-ally` / `--team-enemy` / `--caution` for state).
- Geometric, never decorative. Match the chunky-pixel game language — if a glyph has a curve, it's a single circle.

**FLAG: this is a substitution.** If you ship a real icon set for the game UI, replace `brand-iconography.html` with your own. CDN candidates with the closest visual stroke + weight: **Lucide** (`https://unpkg.com/lucide-static`) — 2px stroke, square caps. Or **Iconoir** — slightly more decorative, also free. **Do NOT use Heroicons** (too rounded) or **Phosphor regular** (too friendly).

### Emoji & unicode
- **Emoji: never.** They break the tone.
- **Unicode block characters** (`█ ▌ ▙ ▚ ◤`) are used as placeholder weapon icons in the design system (see `components-weapon-slots.html`). In production this would be replaced with real pixel-art weapon thumbs.
- **Symbols like ›, ·, /, |** are used as inline separators in HUD readouts: `HP 142 / 240`, `PEER 03 · ELO 1842`.

---

## Font substitutions

The Godot project ships **only the engine's default font** — there is no licensed display face. This kit substitutes:

| Role | Substitute | Why |
|---|---|---|
| Display | **Black Ops One** (Google Fonts) | Stencil, blocky, free, captures the military stencil look the SPEC implies. |
| UI | **Chakra Petch** (Google Fonts) | Condensed techy sans, 7 weights, very legible at small sizes. |
| Mono | **Share Tech Mono** (Google Fonts) | Single weight, sci-fi-leaning monospace. |
| Pixel | **VT323** (Google Fonts) | A staple terminal/pixel face; matches the 640 × 360 chunky aesthetic. |

**Action item for the user:** if you have a different display face in mind for marketing/store-page work (e.g. a custom stencil), drop the `.woff2` files in `fonts/` and update `colors_and_type.css`.

---

## What's intentionally not here

- **Mech 3D renders** — these live in the Godot project as `MechVisuals.gd` + per-mech geometry. Use in-engine screenshots when you need a hero shot.
- **Per-arena environment art** — each map (Math Temple, Badlands, Ironworks) has its own palette and floor pattern; treat them as separate moodboards, not part of the core UI kit.
- **Audio cues** — the SPEC defines a bus layout (Master / SFX / Music) and asset folders, but audio is out of scope for a visual design system.
- **Marketing site / store page** — the project has no website yet. The UI kit only recreates in-game screens.

---

## How to use

1. Import `colors_and_type.css` at the top of any mock.
2. Pull components from `ui_kits/game/` as JSX modules; they are the canonical implementation of buttons, HUD bars, weapon slots, roster rows.
3. Mirror the SPEC invariants when designing new flows: local team always blue (V122), local HUD always top-left, beacon dots match map XZ, no transparent materials in any 3D mock.
4. When in doubt, re-read the relevant `.tscn` file — the offset coordinates are the source of truth for spacing.
