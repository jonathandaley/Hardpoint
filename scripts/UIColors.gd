class_name UIColors

# Design tokens from colors_and_type.css (Design System project).
# Only tokens referenced in game code live here — see the Design project for the full palette.

# Surfaces
const BG_BAR    := Color("#08080d")   # --bg-bar:    HUD track behind value fills
const BG_RAISED := Color("#232330")   # --bg-raised: cards, neutral accent

# HUD state signal
const HP_FULL      := Color("#00ff33")  # --hp-full:   ally/local health & ammo
const HP_ENEMY     := Color("#ff4d33")  # --hp-enemy:  enemy health bar
const SHIELD       := Color("#3380ff")  # --shield:    shield bar (= ally blue)
const DAMAGE_FLASH := Color("#cc0000")  # --damage-flash: full-screen vignette

# Industrial accents
const CAUTION   := Color("#f7c948")  # --caution:   ammo, lock charging, charge overlay
const NEON_CYAN := Color("#28e0c6")  # --neon-cyan: lock-on, ELO chip

# Team signal
const TEAM_ALLY  := Color("#3380ff")  # --team-ally
const TEAM_ENEMY := Color("#ff4d33")  # --team-enemy

# Foreground
const FG_DIM := Color("#4d4d57")  # --fg-dim: disabled / reloading states
