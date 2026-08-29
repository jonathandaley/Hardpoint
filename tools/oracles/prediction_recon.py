"""prediction_recon oracle: client-side prediction reconciliation quality.

Deliberate stub. V37 pins the netcode to interpolation-only for the current
batch; there is no prediction to reconcile until T131 lands (gated on the T129
LAN feel test). Registered so scenario manifests can already cite it and so
the suite output shows WHY it isn't checking anything.
"""
from . import base

NAME = "prediction_recon"


def run(_ctx):
    return base.verdict(NAME, base.SKIP,
                        note="V37 interpolation-only; activate when T131 client prediction lands")
