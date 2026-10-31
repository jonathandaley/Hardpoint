"""log_flood oracle (T143): no ERROR/WARNING line repeats more than
`flood_max_repeats` times in one peer log (digits normalized, so "peer 7" and
"peer 9" count as the same line). B-g: after quitting, the client logged
'Node not found: "Arena"' + 'Failed to get cached node' several times a second
forever; a flood is a symptom even when each line is individually allowed.
"""
import glob
import os
import re
from collections import Counter

from . import base

NAME = "log_flood"

DEFAULTS = {"flood_max_repeats": 20}


def flood_counts(path):
    c = Counter()
    with open(path, errors="replace") as f:
        for line in f:
            if line.startswith(("ERROR:", "WARNING:")):
                c[re.sub(r"\d+", "N", line.strip())] += 1
    return c


def run(ctx):
    run_dir = ctx.get("run_dir")
    logs = sorted(glob.glob(os.path.join(run_dir or "", "*.log")))
    if not logs:
        return base.verdict(NAME, base.SKIP, note="no *.log in run_dir")
    limit = int({**DEFAULTS, **ctx.get("thresholds", {})}["flood_max_repeats"])
    for path in logs:
        line, n = (flood_counts(path).most_common(1) or [("", 0)])[0]
        if n > limit:
            role = os.path.basename(path)[: -len(".log")]
            return base.verdict(NAME, base.FAIL, peer=role, magnitude=n,
                                note="%s.log: %dx %s" % (role, n, line[:140]))
    return base.verdict(NAME, base.PASS, note="no line repeats > %d times (%d logs)" % (limit, len(logs)))
