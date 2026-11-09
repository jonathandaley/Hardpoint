#!/usr/bin/env python3
"""T340: the mech builder -- from a description to a mech in the game, all in Code.

  python3 tools/new_mech.py Name [--class light|medium|heavy] [--roster] [--no-render]

First run: writes a starting builder tools/kit_mechs/<name>.js (the design kit's box language,
see tools/kit_mechs/README.md) and resources/mechs/<Name>.tres (stats from the class's reference
mech: light Cesh, medium Pegasus, heavy Everest). Every run, also after editing the builder:
  1. ports every builder through tools/kit_port.py (scripts/MechKit.gd, WeaponKit.gd),
  2. gives <Name> one weapon slot per kit mount (2-box mount = heavy slot, default a rifle) --
     other mechs' slots are never touched (some are hand-tuned),
  3. renders build/mech_review/<Name>/lineup.png (next to a light, medium and heavy mech of the
     roster, for scale and silhouette) and armed.png (close up with its guns, front and side).
Stats already in the .tres (health, speed, scales, description, abilities) are kept on reruns.
--roster adds it to the hangar / lobby roster (leave it off until the design is approved).
"""
import argparse
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import kit_port  # noqa: E402

REF = {"light": "Cesh", "medium": "Pegasus", "heavy": "Everest"}
STAT_KEYS = ["display_name", "description", "class_tag", "max_health", "walk_speed", "weapon_scale",
             "has_shields", "shield_max_hp", "has_energy_shield", "energy_shield_max_hp",
             "energy_shield_regen_rate", "energy_shield_regen_delay", "turn_acceleration",
             "leg_rotation_speed", "leg_hip_sweep", "leg_bob_magnitude", "leg_cycle_rate", "body_scale"]
GODOT = os.environ.get("GODOT", os.path.expanduser("~/bin/godot"))

# A plain starting biped in the kit's language (kit space: +Z is the mech's front, y up, metres
# at body_scale 1). Torso first, then the pelvis at x = 0, then per side: hip box, three
# M.between spans (thigh, shin, pastern) and a toe pad -- the order kit_port reads legs in.
TEMPLATE = """// T340: {name}, a {cls} mech authored in the design kit's box language (tools/new_mech.py).
// Same M API as design/preview/mech-engine.js; kit space (+Z forward). See tools/kit_mechs/README.md.
// palette: armor #6A6F78, detail #3A3F48, emissive #4FC3F7 e2.0   ({cls} - TODO: describe the look)
build: function (M) {{
  const A = M.armor, D = M.detail, MO = M.mount, SK = M.socket, E = M.emis;

  // ---- TORSO ----
  M.box(0.96, 0.90, 0.70, 0, 1.52, 0, A);                  // main
  M.box(0.56, 0.46, 0.08, 0, 1.54, 0.35, D);               // chest plate
  M.box(0.22, 0.22, 0.10, 0, 1.54, 0.40, E);               // core light
  M.glow(0, 1.54, 0.46, 0.4);
  M.box(0.80, 0.22, 0.54, 0, 1.06, 0, D);                  // torso-to-pelvis bevel

  // ---- HEAD ----
  M.box(0.42, 0.32, 0.44, 0, 2.02, 0.04, A);               // head
  M.box(0.30, 0.08, 0.08, 0, 2.04, 0.26, E);               // visor
  M.glow(0, 2.04, 0.32, 0.3);

  // ---- SHOULDERS + HARDPOINTS ----
  [-1, 1].forEach(function (s) {{
    M.box(0.32, 0.44, 0.54, s * 0.66, 1.62, 0, A);         // shoulder block
{mounts}
  }});

  // ---- PELVIS ----
  M.box(0.70, 0.30, 0.50, 0, 0.94, 0, D);

  // ---- LEGS ----
  [-1, 1].forEach(function (s) {{
    const hx = s * 0.34;
    const hip  = [hx, 0.95,  0.00];
    const knee = [hx, 0.60,  0.14];
    const ankle = [hx, 0.28, -0.08];
    const toe  = [hx, 0.12,  0.06];
    M.box(0.28, 0.26, 0.30, hip[0], hip[1], hip[2], A);
    M.between(hip, knee, 0.24, 0.28, A);                   // thigh
    M.between(knee, ankle, 0.20, 0.22, D);                 // shin
    M.between(ankle, toe, 0.16, 0.18, D);                  // pastern
    M.box(0.30, 0.12, 0.42, hx, 0.06, 0.06, A);            // toe pad
  }});
}}
"""
LIGHT_MOUNT = "    M.box(0.22, 0.18, 0.26, s * 0.66, 1.56, 0.32, MO);     // light mount"
HEAVY_MOUNT = ("    M.box(0.30, 0.24, 0.30, s * 0.70, 1.58, 0.30, MO);     // heavy mount (2 boxes = heavy slot)\n"
               "    M.box(0.20, 0.14, 0.20, s * 0.70, 1.76, 0.28, MO);")


def stats_of(path):
    """key -> raw value text from a MechDef .tres [resource] section, plus ability paths."""
    src = open(path).read()
    res = src[src.index("[resource]"):]
    vals = {}
    for k in STAT_KEYS:
        m = re.search(r"^%s = (.+)$" % k, res, re.M)
        if m:
            vals[k] = m.group(1)
    ids = dict(re.findall(r'\[ext_resource type="Resource" path="(res://resources/abilities/[^"]+)" id="(\w+)"\]', src))
    by_id = {v: k for k, v in ids.items()}
    m = re.search(r"^abilities = \[(.*)\]$", res, re.M)
    abil = [by_id[i] for i in re.findall(r'ExtResource\("(\w+)"\)', m.group(1))] if m else []
    return vals, abil


def write_tres(path, name, vals, abil, slots):
    ext = ['[ext_resource type="Script" path="res://scripts/MechDef.gd" id="1"]',
           '[ext_resource type="PackedScene" path="res://scenes/mech/Mech.tscn" id="2"]',
           '[ext_resource type="Script" path="res://scripts/WeaponSlotDef.gd" id="3"]',
           '[ext_resource type="PackedScene" path="res://scenes/weapons/RifleLight.tscn" id="4"]',
           '[ext_resource type="PackedScene" path="res://scenes/weapons/RifleHeavy.tscn" id="5"]']
    for i, a in enumerate(abil):
        ext.append('[ext_resource type="Resource" path="%s" id="%d"]' % (a, 6 + i))
    subs = []
    for i, (pos, heavy) in enumerate(slots):
        subs.append('[sub_resource type="Resource" id="%d"]\nscript = ExtResource("3")\nslot_size = %d\n'
                    'position = Vector3(%s)\nweapon_scene = ExtResource("%s")\n'
                    % (i + 1, 1 if heavy else 0, ", ".join(kit_port.f(x) for x in pos), "5" if heavy else "4"))
    # script = first: a property above it in a .tres is dropped (T265)
    res = ['[resource]', 'script = ExtResource("1")']
    vals = dict(vals, display_name='"%s"' % name)
    for k in STAT_KEYS:
        if k in vals:
            res.append("%s = %s" % (k, vals[k]))
    res.append("abilities = [%s]" % ", ".join('ExtResource("%d")' % (6 + i) for i in range(len(abil))))
    res.append("weapon_slots = [%s]" % ", ".join('SubResource("%d")' % (i + 1) for i in range(len(slots))))
    res.append('scene = ExtResource("2")')
    text = ('[gd_resource type="Resource" script_class="MechDef" load_steps=%d format=3]\n\n' % (len(ext) + len(subs) + 1)
            + "\n".join(ext) + "\n\n" + "\n".join(subs) + "\n" + "\n".join(res) + "\n")
    open(path, "w").write(text)


def add_to_roster(name):
    entry = '"res://resources/mechs/%s.tres",' % name
    for rel in ("scripts/Hangar.gd", "scripts/Lobby.gd"):
        path = os.path.join(ROOT, rel)
        src = open(path).read()
        if entry in src:
            continue
        m = re.search(r"const ROSTER: Array = \[\n(.*?)\n\]", src, re.S)
        last = m.group(1).rstrip().split("\n")[-1]
        indent = re.match(r"\s*", last).group(0)
        src = src[:m.end(1)] + "\n" + indent + entry + src[m.end(1):]
        open(path, "w").write(src)
        print("  added to the roster in " + rel)


def render(name, out_dir):
    os.makedirs(out_dir, exist_ok=True)
    env = dict(os.environ, XDG_DATA_HOME=os.path.join(out_dir, ".userdata"))  # never the real profile
    xv = ["xvfb-run", "-a", "-s", "-screen 0 1280x720x24", GODOT, "--resolution", "1280x720", "--path", ROOT]
    names = ",".join([REF["light"], REF["medium"], name, REF["heavy"]])
    subprocess.run(xv + ["res://tools/art/lineup.tscn", "--", os.path.join(out_dir, "lineup.png"), "200", names],
                   env=env, capture_output=True, timeout=300)
    subprocess.run(xv + ["res://tools/art/armed.tscn", "--", out_dir, name], env=env, capture_output=True, timeout=300)
    armed = os.path.join(out_dir, name + ".png")
    if os.path.exists(armed):
        os.replace(armed, os.path.join(out_dir, "armed.png"))
    for f in ("lineup.png", "armed.png"):
        p = os.path.join(out_dir, f)
        print("  %s %s" % ("render:" if os.path.exists(p) else "MISSING render:", os.path.relpath(p, ROOT)))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("name", help="mech name, one capital (Ironhide, not IronHide): it keys the kit data")
    ap.add_argument("--class", dest="cls", choices=sorted(REF), default="medium")
    ap.add_argument("--roster", action="store_true", help="add it to the hangar / lobby roster")
    ap.add_argument("--no-render", action="store_true")
    a = ap.parse_args()
    name = a.name
    if name != name.capitalize() or not name.isalpha():
        raise SystemExit("name must be letters with one leading capital (kit data is keyed by the capitalized file name): %s" % name)
    builder = os.path.join(HERE, "kit_mechs", name.lower() + ".js")
    tres = os.path.join(ROOT, "resources", "mechs", name + ".tres")
    if not os.path.exists(builder):
        mounts = HEAVY_MOUNT if a.cls == "heavy" else LIGHT_MOUNT
        open(builder, "w").write(TEMPLATE.format(name=name, cls=a.cls, mounts=mounts))
        print("wrote %s (a starting biped: edit it to the description, then rerun)" % os.path.relpath(builder, ROOT))
    subprocess.run([sys.executable, os.path.join(HERE, "kit_port.py")], check=True, capture_output=True)
    # its armor / detail pixel tiles from the palette line, then let Godot import new files
    genv = dict(os.environ, XDG_DATA_HOME=os.path.join(ROOT, "build", "mech_review", ".userdata"))
    subprocess.run([GODOT, "--headless", "--path", ROOT, "-s", "res://tools/kit_tiles.gd"], env=genv,
                   capture_output=True, check=True, timeout=300)
    subprocess.run([GODOT, "--headless", "--path", ROOT, "--import"], env=genv, capture_output=True, timeout=600)
    _, m = kit_port.build_one(builder)
    groups = kit_port.hardpoint_groups(m)
    if not groups:
        raise SystemExit("%s has no mount boxes (M.mount): a mech needs at least one hardpoint" % os.path.basename(builder))
    slots = [(c, n >= 2) for c, n in sorted(groups, key=lambda gn: gn[0][0])]  # left to right
    existed = os.path.exists(tres)
    if existed:
        vals, abil = stats_of(tres)
    else:
        vals, abil = stats_of(os.path.join(ROOT, "resources", "mechs", REF[a.cls] + ".tres"))
        vals["description"] = '"TODO: one line for the hangar."'
        vals["class_tag"] = '"%s"' % a.cls.capitalize()
        abil = []  # abilities and shields are design calls, not copied from the reference
        for k in ("has_shields", "shield_max_hp", "has_energy_shield", "energy_shield_max_hp",
                  "energy_shield_regen_rate", "energy_shield_regen_delay"):
            vals.pop(k, None)
    write_tres(tres, name, vals, abil, slots)
    print("%s %s: %d slot(s) on its mounts (%s)" % ("updated" if existed else "wrote", os.path.relpath(tres, ROOT),
          len(slots), ", ".join("heavy" if h else "light" for _, h in slots)))
    if a.roster:
        add_to_roster(name)
    if not a.no_render:
        render(name, os.path.join(ROOT, "build", "mech_review", name))


if __name__ == "__main__":
    main()
