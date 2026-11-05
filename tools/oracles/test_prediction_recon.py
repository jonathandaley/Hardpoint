"""Red/green self-check for prediction_recon (T205; T268 warm-up).
Run: python3 -m tools.oracles.test_prediction_recon
"""
from . import base, prediction_recon


def _v(errs, start=50, step=2):
    evs = [{"tick": start + i * step, "type": "pred_recon", "payload": {"err": e, "snap": False}}
           for i, e in enumerate(errs)]
    log = base.PeerLog("client_1", [], evs)
    return prediction_recon.run({"primary": {"client_1": log}, "thresholds": {"pred_p95_m": 0.6}})["verdict"]


def main():
    settled = [0.05] * 70
    assert _v(settled) == base.PASS, "settled prediction"
    # B105 shape: ~1 s of start-up alignment from 0.9 m easing out, then settled
    assert _v([0.9, 0.85, 0.8, 0.8, 0.7, 0.6, 0.5, 0.4, 0.3, 0.2] + settled, step=6) == base.PASS, "start-up transient"
    assert _v([0.8] * 80) == base.FAIL, "prediction that never converges"
    assert _v([0.05] * 40 + [0.9] * 30) == base.FAIL, "divergence after warm-up"
    print("test_prediction_recon: ok")


if __name__ == "__main__":
    main()
