#!/bin/bash
# HarnessRouter #725 console gates (v3). Every command has its own timeout; the sequential worst case
# (EXECUTION-PACKET-v3.md section 2) is 1,195 s inside the workflow's 1,350 s container limit.
# Runs once as uid 1000 inside node:20.20.2-bookworm (digest-pinned).
# Exit codes: 30 tools, 31-33 source sealing, 40 install, 50 unexpected negative result,
# 51 focused candidate failure, 52 type-check failure, 53 any required full gate failed (aggregate),
# 54 the tested build could not be handed to the demo. 0 only when every required result is 0.
set -uo pipefail
mkdir -p /tmp/home /tmp/work/base /tmp/work/candidate
OUT=/out; codes="$OUT/exit-codes.tsv"; : > "$codes"
rec() { printf '%s\t%s\n' "$1" "$2" >> "$codes"; }
TEST_DIR=src/components/hrui/setup
FOLDER_TEST=$TEST_DIR/SetupSettings.pluginFolder.test.tsx
HELPER_TEST=$TEST_DIR/pluginManifest.test.ts
PROD_CHANGED=$TEST_DIR/SetupSettings.tsx
PROD_NEW=$TEST_DIR/pluginManifest.ts
LOCK_SHA=b30f96b02f92a6101729c7eecef949f3f8b1246433850d7394cc36efbeb58467
W=/tmp/work
T() { local n="$1"; shift; timeout --signal=TERM --kill-after=5s "$n" "$@"; }   # 124/137 = timed out

T 5 sh -c 'node --version; npm --version; python3 --version' > "$OUT/tool-versions.txt" 2>&1 || exit 30
T 20 tar -xf /inputs/base.tar -C $W/base || exit 31
T 20 tar -xf /inputs/candidate.tar -C $W/candidate || exit 32
(cd $W/candidate && T 10 sha256sum -c /inputs/source.sha256) > "$OUT/source-integrity.log" 2>&1 || exit 33
echo "$LOCK_SHA  $W/candidate/ui/package-lock.json" | sha256sum -c - >> "$OUT/source-integrity.log" 2>&1 || exit 33
cmp $W/base/ui/package-lock.json $W/candidate/ui/package-lock.json || exit 33
cmp $W/base/ui/package.json $W/candidate/ui/package.json || exit 33

cd $W/candidate/ui
# 1. Install once. Strict npm ci; upstream tests.yml's `npm ci ... || npm install ...` fallback is not used.
T 240 npm ci --no-audit --no-fund > "$OUT/npm-ci.log" 2>&1; s=$?; rec npm-ci "$s"; [ "$s" = 0 ] || exit 40

# 2-3. Negative: keep the new folder-path test; restore production source to the base blob.
cp $W/base/ui/$PROD_CHANGED $PROD_CHANGED && rm -f $PROD_NEW
T 90 npx jest --ci --json --outputFile="$OUT/negative.json" $FOLDER_TEST > "$OUT/negative.log" 2>&1; s=$?; rec negative-focused "$s"
T 10 python3 - "$OUT/negative.json" "$s" > "$OUT/negative-check.log" 2>&1 <<'PY'
import json, sys
r = json.load(open(sys.argv[1]))
assert sys.argv[2] == "1", f"jest exit {sys.argv[2]}, expected 1"
EXPECT_FAIL = {
  "a malformed plugin.json is refused with the parser's own message",
  "two different malformations give two different notices",
}
EXPECT_PASS = {
  "a malformed plugin.json is never saved",
  "a valid plugin.json still installs",
}
assert r["numRuntimeErrorTestSuites"] == 0, "suite failed to run"
assert len(r["testResults"]) == 1, r["testResults"]
suite = r["testResults"][0]
assert not suite.get("testExecError") and "Test suite failed to run" not in (suite.get("message") or ""), suite.get("message")
got = {a["title"]: a for a in suite["assertionResults"]}
assert set(got) == EXPECT_FAIL | EXPECT_PASS, sorted(got)
for t in EXPECT_FAIL:
    a = got[t]; assert a["status"] == "failed", (t, a["status"])
    msg = "\n".join(a["failureMessages"])
    assert "expect(" in msg and ("toHaveBeenCalledWith" in msg or "toBe" in msg), (t, msg[:400])
for t in EXPECT_PASS:
    assert got[t]["status"] == "passed", (t, got[t]["status"])
print("NEGATIVE_AS_EXPECTED")
PY
s=$?; rec negative-check "$s"; [ "$s" = 0 ] || exit 50

# 4. Restore the exact candidate source and verify it.
T 10 tar -xf /inputs/candidate.tar -C $W/candidate ui/$PROD_CHANGED ui/$PROD_NEW || exit 32
(cd $W/candidate && T 10 sha256sum -c /inputs/source.sha256) > "$OUT/source-integrity-restored.log" 2>&1 || exit 33
T 90 npx jest --ci --json --outputFile="$OUT/focused.json" $FOLDER_TEST $HELPER_TEST > "$OUT/focused.log" 2>&1; s=$?; rec focused "$s"; [ "$s" = 0 ] || exit 51

# 5. Type-check; abort before the expensive gates on any unexpected result.
T 90 npm run type-check > "$OUT/type-check.log" 2>&1; s=$?; rec type-check "$s"; [ "$s" = 0 ] || exit 52

# Full console gates (upstream tests.yml job `console`, working directory ui). All run; all required.
fail=0
gate() { local n="$1"; shift; "$@"; local s=$?; rec "$n" "$s"; [ "$s" = 0 ] || fail=1; }
gate licences-js          T 20 sh -c 'python3 ../scripts/check-licenses.py --js > /out/licences-js.log 2>&1'
gate licences-selftest    T 20 sh -c 'python3 ../scripts/test-check-licenses.py > /out/licences-selftest.log 2>&1'
gate jest-full            T 210 sh -c 'npm test -- --ci --passWithNoTests --json --outputFile=/out/jest-full.json > /out/jest-full.log 2>&1'
gate build                T 240 sh -c 'npm run build > /out/build.log 2>&1'
gate third-party-licences T 20 sh -c 'node scripts/third-party-licenses.mjs > /out/third-party-licences.txt 2> /out/third-party-licences.err'
gate source-final         T 10 sh -c 'cd /tmp/work/candidate && sha256sum -c /inputs/source.sha256 > /out/source-integrity-final.log 2>&1'
gate summary T 10 python3 - "$OUT" <<'PY'
import json, sys, pathlib
o = pathlib.Path(sys.argv[1]); s = {}; ok = True
for n in ("focused", "jest-full"):
    r = json.loads((o / f"{n}.json").read_text())
    s[n] = {k: r[k] for k in ("numTotalTestSuites","numPassedTestSuites","numFailedTestSuites","numRuntimeErrorTestSuites","numTotalTests","numPassedTests","numFailedTests","numPendingTests")}
    ok = ok and r["success"] is True and r["numFailedTests"] == 0 and r["numRuntimeErrorTestSuites"] == 0
s["exit_codes"] = dict(l.split("\t") for l in (o / "exit-codes.tsv").read_text().split("\n") if l)
(o / "summary.json").write_text(json.dumps(s, indent=2))
raise SystemExit(0 if ok else 1)
PY
[ "$fail" = 0 ] || { rec aggregate 1; exit 53; }

# Hand the exact tested build (standalone server, static, public: the Dockerfile's own COPY set) to the demo.
# Manifests are relative: console-build.sha256 lists ./paths under the build directory, and
# console-build-manifest.sha256 names console-build.sha256 relative to the evidence directory, so the
# host verifies them with `cd <build>/app` and `cd <evidence>` (demo.sh). Worst case 45 + 20 + 5 s.
T 45 sh -c 'cp -a .next/standalone/. /build/app/ && mkdir -p /build/app/.next && cp -a .next/static /build/app/.next/static && cp -a public /build/app/public' > "$OUT/build-handoff.log" 2>&1 || { rec build-handoff 1; exit 54; }
(cd /build/app && T 20 sh -c 'find . -type f ! -path "./.next/cache/*" -print0 | sort -z | xargs -0 sha256sum') > "$OUT/console-build.sha256" || { rec build-handoff 1; exit 54; }
(cd "$OUT" && T 5 sha256sum console-build.sha256) > "$OUT/console-build-manifest.sha256" || { rec build-handoff 1; exit 54; }
rec build-handoff 0; rec aggregate 0
exit 0
