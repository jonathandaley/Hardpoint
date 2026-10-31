"""scene_routes oracle (T144, B-f): no dead-end screens. Static repo scan, no
run data: builds the scene graph from `change_scene_to_file("res://...")`
literals in each scene's scripts (sub-scenes included) and checks every scene
reachable from the main scene can get back to it. B-f: Arena -> Hangar had no
route to TitleScreen/MPEntry, so after quitting an MP match only singleplayer
was reachable until restart. Dynamic targets (Game._rpc_change_scene(path)) are
MP-coordinated and not followed.
"""
import os
import re

from . import base

NAME = "scene_routes"

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
_EXT = re.compile(r'\[ext_resource type="(Script|PackedScene)" path="res://([^"]+)"')
_GOTO = re.compile(r'change_scene_to_file\(\s*"res://([^"]+\.tscn)"')


def _res(path):
    return os.path.join(REPO, path)


def scene_targets(scene, seen=None):
    """Targets reachable in one hop from `scene` (its scripts + sub-scenes')."""
    seen = set() if seen is None else seen
    if scene in seen or not os.path.exists(_res(scene)):
        return set()
    seen.add(scene)
    out = set()
    with open(_res(scene)) as f:
        for kind, path in _EXT.findall(f.read()):
            if kind == "PackedScene":
                out |= scene_targets(path, seen)
            elif os.path.exists(_res(path)):
                with open(_res(path)) as g:
                    out |= set(_GOTO.findall(g.read()))
    return out


def graph(main):
    """{scene: targets} for everything reachable from main. Autoload scripts
    (Game.gd etc.) can switch scenes from anywhere, so their literal targets
    are added to every scene."""
    autoload = set()
    with open(_res("project.godot")) as f:
        for path in re.findall(r'="\*res://([^"]+\.gd)"', f.read()):
            with open(_res(path)) as g:
                autoload |= set(_GOTO.findall(g.read()))
    g, todo = {}, [main]
    while todo:
        s = todo.pop()
        if s in g:
            continue
        g[s] = scene_targets(s) | autoload
        todo.extend(g[s])
    return g


def reaches(g, src, dst):
    seen, todo = set(), [src]
    while todo:
        s = todo.pop()
        if s == dst:
            return True
        if s not in seen:
            seen.add(s)
            todo.extend(g.get(s, ()))
    return False


def run(ctx):
    with open(_res("project.godot")) as f:
        m = re.search(r'run/main_scene="res://([^"]+)"', f.read())
    if not m:
        return base.verdict(NAME, base.SKIP, note="no run/main_scene in project.godot")
    main = m.group(1)
    g = graph(main)
    dead = sorted(s for s in g if not reaches(g, s, main))
    if dead:
        return base.verdict(NAME, base.FAIL, field="route", magnitude=len(dead),
                            note="no route back to %s from: %s" % (main, ", ".join(dead)))
    return base.verdict(NAME, base.PASS, note="all %d scenes reachable from %s can return to it" % (len(g), main))
