#!/bin/bash
# One approved attempt, only inside agent-controlled hosted Linux Docker.
set -uo pipefail
validation_started_seconds=$SECONDS
export PIP_RETRIES=5 PIP_DEFAULT_TIMEOUT=15 PIP_DISABLE_PIP_VERSION_CHECK=1 PYTHONDONTWRITEBYTECODE=1
export DEBIAN_FRONTEND=noninteractive
export PIP_CACHE_DIR=/root/.cache/pip
mkdir -p /work/feature /out /tmp/validation-home
export HOME=/tmp/validation-home
python - <<'PY'
import io,tarfile,tempfile,subprocess,sys,time,json
from pathlib import Path
with tempfile.TemporaryDirectory() as t:
 p=Path(t); b=io.BytesIO()
 with tarfile.open(fileobj=b,mode='w') as a:
  m=tarfile.TarInfo('nested/value');m.size=3;a.addfile(m,io.BytesIO(b'yes'))
 b.seek(0)
 with tarfile.open(fileobj=b) as a:a.extractall(p,filter='data')
 assert (p/'nested/value').read_bytes()==b'yes'
 assert (p/'nested/value').read_bytes()!=b'no'
# The reviewed init must reap a deliberately orphaned, tiny synthetic child.
code = "import os,time; pid=os.fork(); print(pid,flush=True) if pid else time.sleep(.1); os._exit(0)"
probe=subprocess.run([sys.executable,'-c',code],capture_output=True,text=True,timeout=3,check=True)
pid=int(probe.stdout.strip());deadline=time.monotonic()+3
while Path('/proc',str(pid)).exists() and time.monotonic()<deadline:time.sleep(.05)
assert not Path('/proc',str(pid)).exists(), 'orphan was not reaped by container init'
Path('/out/supervisor-fixture.json').write_text(json.dumps({'orphan_reaped':True,'pid1':Path('/proc/1/cmdline').read_bytes().replace(b"\0",b" ").decode()}))
print('HARNESS_FIXTURE_PASS: tar comparisons and orphan reaping')
PY
[ "$?" = 0 ] || exit 30
tar -xf /inputs/feature.tar -C /work/feature || exit 32
(cd /work/feature && sha256sum -c /inputs/source.sha256) > /out/source-integrity.log 2>&1 || exit 33
apt-get -o Acquire::Retries=3 update > /out/apt.log 2>&1
apt_update=$?
apt-get -o Acquire::Retries=3 install -y --no-install-recommends git ffmpeg ca-certificates curl procps unzip util-linux build-essential nodejs npm >> /out/apt.log 2>&1
apt_install=$?
printf 'apt-update\t%s\napt-install\t%s\n' "$apt_update" "$apt_install" > /out/exit-codes.tsv
node --version > /out/node-version.txt 2>&1
npm --version > /out/npm-version.txt 2>&1
useradd -m -u 1001 validator || exit 34
chown -R 1001:1001 /work /out /tmp/validation-home
resources() {
 python - "$1" <<'PY_RESOURCE'
import json,sys
from pathlib import Path
p=Path('/sys/fs/cgroup');data={}
for name in ('pids.current','pids.events','pids.peak','memory.current','memory.events'):
 try:data[name]=(p/name).read_text().strip()
 except OSError as error:data[name]='unavailable: '+str(error)
Path(sys.argv[1]).write_text(json.dumps(data,indent=2))
PY_RESOURCE
}
run() {
 local name="$1" folder="$2"; shift 2
 resources "/out/$name-resources-before.json"
 (cd "$folder" && runuser -u validator -- "$@") > "/out/$name.log" 2>&1
 local status="$?"
 resources "/out/$name-resources-after.json"
 printf '%s\t%s\n' "$name" "$status" >> /out/exit-codes.tsv
 return 0
}
install() {
 local lane="$1"; shift
 python -m venv "/opt/$lane" || return 1
 "/opt/$lane/bin/python" -m pip install --retries 5 "$@" --report "/out/$lane-install-report.json" > "/out/$lane-install.log" 2>&1
 local status="$?"
 printf '%s-install\t%s\n' "$lane" "$status" >> /out/exit-codes.tsv
 [ "$status" = 0 ] || return 1
 "/opt/$lane/bin/python" -m pip freeze --all > "/out/$lane-freeze.txt"
 "/opt/$lane/bin/python" -m pip check > "/out/$lane-pip-check.log" 2>&1
 printf '%s-pip-check\t%s\n' "$lane" "$?" >> /out/exit-codes.tsv
 return 0
}
GW=0; RUNNER=0; JOINT=0
install gw -r /inputs/gw-freeze.txt && GW=1
install runner -r /inputs/runner-freeze.txt && RUNNER=1
install joint -r /inputs/joint-freeze.txt && JOINT=1
python - <<'PY_LOCK'
from pathlib import Path
for name in ('gw','runner','joint'):
 assert set(Path('/inputs',name+'-freeze.txt').read_text().splitlines())==set(Path('/out',name+'-freeze.txt').read_text().splitlines()),name
PY_LOCK
[ "$?" = 0 ] || exit 44
# Only this measurement window gates full-suite admission, not installation/page-cache peaks.
python - <<'PY' &
import time,json
from pathlib import Path
p=Path('/sys/fs/cgroup');out=Path('/out/focus-memory.json'); peak=anon=0
while not Path('/out/focus-measurement-complete').exists():
 try:
  s=dict(x.split() for x in (p/'memory.stat').read_text().splitlines());anon=max(anon,int(s['anon']));peak=max(peak,int((p/'memory.current').read_text()))
  out.write_text(json.dumps({'anon_peak':anon,'current_peak':peak}));time.sleep(.1)
 except Exception as error:
  out.write_text(json.dumps({'error':str(error)}));break
PY
sampler=$!
[ "$RUNNER" = 0 ] || run focused-runner /work/feature /opt/runner/bin/python -m pytest runner/tests/test_response_branching.py -q --junitxml=/out/focused-runner.xml
# R2: execute the real generator and require byte-identical sealed outputs before tests.
if [ "$JOINT" = 1 ]; then
 run feature-schema-generate /work/feature /opt/joint/bin/python protocol/schema/build.py
 cmp /work/feature/protocol/schema/uhp-2026-10-19.schema.json /work/feature/protocol/conformance/uhp_conformance/uhp-2026-10-19.schema.json || exit 42
 (cd /work/feature && sha256sum -c /inputs/source.sha256) > /out/post-generation-source-integrity.log 2>&1 || exit 43
fi
[ "$JOINT" = 0 ] || run focused-integration /work/feature /opt/joint/bin/python -m pytest tests/integration -q --junitxml=/out/focused-integration.xml
touch /out/focus-measurement-complete
wait "$sampler"
python - <<'PY' > /out/admission.log 2>&1
import json
from pathlib import Path
try:
 data=json.loads(Path('/out/focus-memory.json').read_text())
 assert 'error' not in data, data
 assert 0 < data['anon_peak'] <= 5*1024**3, data
 print('MEMORY_ADMIT',data)
except Exception as error:
 print('MEMORY_DENY',repr(error));raise SystemExit(1)
PY
memory_admission=$?
# Retain independent evidence even if one dependency lane was unavailable. No retries.
if [ "$memory_admission" = 0 ]; then
 [ "$GW" = 0 ] || run feature-gateway /work/feature /opt/gw/bin/python -m pytest gateway/tests -q --junitxml=/out/feature-gateway.xml
 [ "$RUNNER" = 0 ] || run feature-runner /work/feature /opt/runner/bin/python -m pytest runner/tests -q -vv --junitxml=/out/feature-runner.xml
fi
(cd /work/feature && sha256sum -c /inputs/source.sha256) > /out/final-source-integrity.log 2>&1 || exit 45
python /inputs/compare.py
