#!/bin/bash
# Corrected-toast demonstration (v3), run only after the gates step returned 0.
# Route: the exact tested console build (gates step `next build` standalone output) served by the gates
# image, in front of the real gateway from the candidate tree, installed ONLY from the reviewed hash-locked
# closure gateway-lock.txt (pip --require-hashes --no-deps --only-binary :all:). No root image, skills,
# kits, document/media layers, runner or backend installs. Loopback only, HR_AUTH_DISABLED=1, no
# provider keys. Sequential worst case (EXECUTION-PACKET-v3.md section 2): 1,077 s inside the
# workflow's 1,140 s limit. Exit codes: 60 source/build integrity, 61 gateway install, 62 gateway never
# healthy, 63 console never answered, 64 Playwright package not as pinned, 65 image pull, 70-74 demo.mjs.
set -uo pipefail
in="$1"; out="$2"; build="$3"; d="$out/demo"; tree="$RUNNER_TEMP/hr725-tree"
mkdir -p "$d" "$tree"; codes="$d/exit-codes.tsv"; : > "$codes"; rec() { printf '%s\t%s\n' "$1" "$2" >> "$codes"; }
T() { local n="$1"; shift; timeout --signal=TERM --kill-after=5s "$n" "$@"; }
gw="hr725-gw-$GITHUB_RUN_ID"; ui="hr725-ui-$GITHUB_RUN_ID"
trap 'T 10 docker logs "$gw" > "$d/gateway.log" 2>&1 || true; T 10 docker logs "$ui" > "$d/console.log" 2>&1 || true; T 15 docker rm -f "$ui" "$gw" > /dev/null 2>&1 || true' EXIT
PYIMG=python@sha256:05a994d2344eb364cc186910f4fc8786a38215f39f00d0acc25bff33a08f4177   # python:3.12-slim (3.12.16, trixie) linux/amd64
NODEIMG=node@sha256:cacf10e99285cbbc891452e31249c1b5ec3ba225f40028fae946b75aeaf1b66a  # the gates image
PWIMG=mcr.microsoft.com/playwright@sha256:2f05f8a734509a7b3f26a912639488ee08f58a7b292d14d62271bcff9038768f  # v1.64.1-noble
PW_SHA512=HCrVhHr5QQuwYoswEUGTb7gGp522yflbv/ST8nF4sFWGuLjQCt17Q/EubpGGSNKYn1tsTCPZxqHhHCfVURu7UA==
PWC_SHA512=BC4s8y6SEVA6Q1rSxZTto8hI1KUI3xXlHGZgvGqP4IqPdI/a6FX9H29IDNz7vKo9l21b6LfYosScPL6M3xxyDQ==

# integrity (worst case 20 + 10 + 5 + 15 = 50 s)
T 20 tar -xf "$in/candidate.tar" -C "$tree" || exit 60
(cd "$tree" && T 10 sha256sum -c "$in/source.sha256") > "$d/source-integrity.log" 2>&1 || exit 60
(cd "$out" && T 5 sha256sum -c console-build-manifest.sha256) > "$d/build-integrity.log" 2>&1 || exit 60
(cd "$build/app" && T 15 sha256sum -c --quiet "$out/console-build.sha256") >> "$d/build-integrity.log" 2>&1 || exit 60
# images (worst case 90 + 240 + ~5 untimed inspects = 335 s); the node image is already present from the gates step
T 90 docker pull "$PYIMG" > "$d/pull-python.log" 2>&1 || { rec pull-python 1; exit 65; }
T 240 docker pull "$PWIMG" > "$d/pull-playwright.log" 2>&1 || { rec pull-playwright 1; exit 65; }
for i in "$PYIMG" "$NODEIMG" "$PWIMG"; do docker image inspect "$i" --format '{{.Id}} {{json .RepoDigests}}'; done > "$d/images.txt"
# Ephemeral per-run secrets in the entrypoint's own shapes (docker/entrypoint.sh L178 token_hex(32),
# L263 token_urlsafe(32)); never written to evidence.
KEY="$(python3 -I -c 'import secrets; print(secrets.token_hex(32))')"; SKEY="$(python3 -I -c 'import secrets; print(secrets.token_urlsafe(32))')"
chmod 0777 "$d"

# Gateway container: the entrypoint's self-hosted environment (L72-L183); no runner; no HR_BACKENDS_INSTALLED.
# Its PID 1 only waits; install and server are separate bounded execs (worst case 10 + 180 + 5 + 90 = 285 s).
T 10 docker run -d --name "$gw" --init --cpus 1 --memory 2g --pids-limit 512 --user 1000:1000 \
  --tmpfs /data:rw,uid=1000,gid=1000,size=1g --tmpfs /tmp:rw,exec,uid=1000,gid=1000,size=2g \
  --mount "type=bind,src=$tree,dst=/src,readonly" --mount "type=bind,src=$in,dst=/inputs,readonly" \
  --mount "type=bind,src=$d,dst=/out" \
  -e HOME=/tmp -e PYTHONDONTWRITEBYTECODE=1 -e PIP_DISABLE_PIP_VERSION_CHECK=1 -e PIP_NO_CACHE_DIR=1 \
  -e HR_DATA_DIR=/data -e HARNESS_WORKSPACE=/data/workspaces -e HR_WS_MARKER_DIR=/data/ws-markers \
  -e HR_ENV_ROOT=/data/environments -e HR_BACKING=local -e HR_IDENTITY_MODE=off -e HR_CREDIT_GATE=off \
  -e POOL_MGMT_ENDPOINT=http://127.0.0.1:8081 -e HR_POOL_AUTH=none -e HR_SANDBOX_TRUST=owner \
  -e HARNESS_INTERNAL_KEY="$KEY" -e HR_SECRET_KEY="$SKEY" -e HR_VERSION=hr725-demo \
  "$PYIMG" python -c 'import signal,sys,time; signal.signal(signal.SIGTERM,lambda *_:sys.exit(0)); time.sleep(1200)' > /dev/null || { rec gateway-start 1; exit 61; }
T 180 docker exec "$gw" sh -c '
  set -e
  python -I - /src/gateway/requirements.txt /inputs/gateway-lock.txt <<"PY"
import re, sys
norm = lambda n: re.sub(r"[-_.]+", "-", n).lower()
def pins(path):
    out = {}
    for line in open(path):
        line = line.split("#")[0].strip()
        m = re.match(r"^([A-Za-z0-9_.-]+)(\[[^\]]*\])?==([^ \;]+)", line)
        if m: out[norm(m.group(1))] = m.group(3)
    return out
req, lock = pins(sys.argv[1]), pins(sys.argv[2])
bad = {k: (v, lock.get(k)) for k, v in req.items() if lock.get(k) != v}
assert not bad, f"lock disagrees with gateway/requirements.txt: {bad}"
print(f"LOCK_COVERS_REQUIREMENTS {len(req)} direct, {len(lock)} locked")
PY
  python -m venv /tmp/gw
  /tmp/gw/bin/pip install --require-hashes --no-deps --only-binary :all: --retries 3 --timeout 30 \
    -r /inputs/gateway-lock.txt --report /out/gateway-install-report.json
  /tmp/gw/bin/pip check
  /tmp/gw/bin/pip freeze --all' > "$d/gateway-install.log" 2>&1
s=$?; rec gateway-install "$s"; [ "$s" = 0 ] || exit 61
T 5 docker exec -d "$gw" sh -c 'cd /src/gateway && exec /tmp/gw/bin/python -m uvicorn app:app --host 127.0.0.1 --port 8080 --log-level warning > /out/gateway-server.log 2>&1' || { rec gateway-health 1; exit 62; }
ok=0; for _ in $(seq 1 30); do   # 30 x (probe <= 2 s + sleep 1 s) <= 90 s
  if T 2 docker exec "$gw" python -I -c 'import urllib.request,sys; sys.exit(0 if urllib.request.urlopen("http://127.0.0.1:8080/healthz",timeout=1).status==200 else 1)' 2>/dev/null; then ok=1; break; fi
  sleep 1; done
[ "$ok" = 1 ] || { rec gateway-health 1; exit 62; }; rec gateway-health 0

# Console: the tested standalone build, as entrypoint L2325-L2335 starts it (node server.js), auth gate off.
# Worst case 10 + 60 = 70 s.
T 10 docker run -d --name "$ui" --init --network "container:$gw" --cpus 1 --memory 1g --pids-limit 256 --user 1000:1000 \
  --tmpfs /tmp:rw,uid=1000,gid=1000,size=1g --mount "type=bind,src=$build/app,dst=/build,readonly" \
  -e HOME=/tmp -e NODE_ENV=production -e NEXT_TELEMETRY_DISABLED=1 -e NEXT_PUBLIC_HR_EDITION=selfhost \
  -e HR_AUTH_DISABLED=1 -e HARNESS_GATEWAY_URL=http://127.0.0.1:8080 -e HARNESS_INTERNAL_KEY="$KEY" \
  -e PORT=3000 -e HOSTNAME=127.0.0.1 \
  "$NODEIMG" sh -c 'cp -a /build /tmp/app && cd /tmp/app && exec node server.js' > /dev/null || { rec console-ready 1; exit 63; }
ok=0; for _ in $(seq 1 20); do   # 20 x (probe <= 2 s + sleep 1 s) <= 60 s
  if T 2 docker exec "$ui" node -e 'fetch("http://127.0.0.1:3000/",{signal:AbortSignal.timeout(1000)}).then(r=>process.exit(r.status<500?0:1),()=>process.exit(1))' 2>/dev/null; then ok=1; break; fi
  sleep 1; done
[ "$ok" = 1 ] || { rec console-ready 1; exit 63; }; rec console-ready 0
unset KEY SKEY

# Playwright (worst case 300 s): pinned image (browsers for 1.64.1) plus two npm tarballs sealed by registry integrity.
mkdir -p "$RUNNER_TEMP/hr725-fixture/bad-plugin"
printf '{"name": "x"' > "$RUNNER_TEMP/hr725-fixture/bad-plugin/plugin.json"     # the issue's truncated example
T 300 docker run --rm --init --network "container:$gw" --shm-size 512m --cpus 2 --memory 2g --pids-limit 512 --user pwuser \
  -e PW_SHA512="$PW_SHA512" -e PWC_SHA512="$PWC_SHA512" \
  --mount "type=bind,src=$in/demo.mjs,dst=/demo/demo.mjs,readonly" \
  --mount "type=bind,src=$RUNNER_TEMP/hr725-fixture,dst=/fixture,readonly" --mount "type=bind,src=$d,dst=/out" \
  "$PWIMG" bash -c '
    set -euo pipefail; cd /tmp
    timeout 90 node -e "
      const c=require(\"crypto\"),fs=require(\"fs\");
      const want={\"playwright\":process.env.PW_SHA512,\"playwright-core\":process.env.PWC_SHA512};
      (async()=>{for(const [n,h] of Object.entries(want)){
        const r=await fetch(\`https://registry.npmjs.org/\${n}/-/\${n}-1.64.1.tgz\`,{signal:AbortSignal.timeout(40000)}); if(!r.ok) process.exit(64);
        const b=Buffer.from(await r.arrayBuffer()); const got=c.createHash(\"sha512\").update(b).digest(\"base64\");
        if(got!==h){console.error(n,\"integrity mismatch\",got);process.exit(64);} fs.writeFileSync(n+\".tgz\",b);}})();
    " > /out/pw-fetch.log 2>&1 || exit 64
    mkdir -p node_modules/playwright node_modules/playwright-core
    tar -xzf playwright-core.tgz -C node_modules/playwright-core --strip-components=1
    tar -xzf playwright.tgz -C node_modules/playwright --strip-components=1
    node -p "require(\"playwright/package.json\").version+\" \"+require(\"playwright-core/package.json\").version" > /out/pw-version.txt
    grep -qx "1.64.1 1.64.1" /out/pw-version.txt || exit 64
    cp /demo/demo.mjs /tmp/demo.mjs && exec timeout 180 node /tmp/demo.mjs' > "$d/demo.log" 2>&1
s=$?; rec demo "$s"; exit "$s"
