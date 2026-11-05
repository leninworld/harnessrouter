# Response branching #477 — retained Docker results

Composite evidence summary; this is not a terminal capture.

```text
Feature: f8edb7df63eee7f42378cba625c6c006957c5df7
Patch SHA256: ccff187b758da9166974499d3fd765119c2d9bc9293acbcb82f51860095608f2
Full feature suites: 94a1dc1 / run 41954591245
Gateway: 1847 passed, 17 skipped | Runner: 2057 passed, 19 skipped
Conformance unit suite: 184 passed | Benchmark: 18 passed
Schema / site / licenses / badge: passed on both sides
Fresh integration: f8edb7d / run 41958454649 — PASS
Base control: expected "branch must create a new session" failure
API: branch first of 3; original unchanged; no future/CLI-secret files
Durability: continuation after workspace and marker removal — PASS
Hosted Docker: Python 3.12, 2 CPU, 6 GiB, non-root UID 1001
Image: sha256:b18b261e1b4974b4f321451ad5251ded85abb22c2b8b262da527dda1d031ab30
```

The earlier run concluded as failure on its old integration fixture; its complete suites above passed. Only that fixture changed afterward; unchanged source identity was verified before the fresh run.

Limits: synthetic identity/provider configuration in owner-trust mode and a replaced paid CLI; real HTTP, Git, checkpoints and backing. No live-provider, native-CLI, default-relay or console test claim.
