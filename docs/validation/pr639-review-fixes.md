# PR639 review fixes — retained Docker results

Summary of recorded results; not a terminal capture.

```text
Merged candidate: 51e4c1b444e05376169055663d3cc0872935ab38
Contributor preserved: 4824d8475d5fb89864b646dd8eea2278ffb07dff
Contribution diff 89aed57..51e4c1b (also f8edb7d..85fe9bb)
SHA256: 0bcb2204fdc46a89842e55fe274759d6eb6447e1a0175e98ce79c7ef660b2be2
Fresh run42251215420 on51e4c1b: SUCCESS
Run checked out fork-only validation child a776f94 (.github files only)
Gateway1854PASS/17skip | Runner2067PASS/19skip | HTTP/Git integration1PASS
Focused runner105PASS; all5new upstream tests PASS; schema generation PASS
All16 source hashes verified; no lost cases or new skips
Hosted Docker: Python3.12, 2CPU, 6GiB, test UID1001
```

Reused on85fe9bb (identical unaffected inputs): conformance190PASS, benchmark18PASS, site/licenses/badgePASS. New regressions on previous PR headf8edb7d: gateway16 + runner2 expected failures, no errors/skips.

Earlier run42246487772 concluded FAILURE: comparator rejected two expected assertion-message formats. Raw passing suites/controls retained; no rerun of that run.

Fixes: origin only on branch response; invalid branch400 before execution; restore using checkpoint HEAD without stale head marker.

Limits: synthetic identity/provider settings and provider executable; real HTTP/Git/checkpoints/backing. No independent live-provider, native-Qwen/vLLM, default-relay or console test claim.
