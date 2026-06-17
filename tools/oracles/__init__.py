"""M1 oracle library for the MP autodebug harness.

Each oracle is a module exposing NAME (str) and run(ctx) -> verdict dict. The
driver (tools/sync_compare.py) loads one or more run directories, builds a ctx,
dispatches the oracles named by the scenario, and aggregates verdicts into a
single machine-readable PASS/FAIL report. Stdlib only.
"""
