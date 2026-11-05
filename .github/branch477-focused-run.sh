#!/bin/bash
# Only a changed integration fixture is executed; prior complete suites verified independently.
set -uo pipefail
export PIP_RETRIES=5 PIP_DEFAULT_TIMEOUT=15 PIP_DISABLE_PIP_VERSION_CHECK=1 PYTHONDONTWRITEBYTECODE=1
export DEBIAN_FRONTEND=noninteractive PIP_CACHE_DIR=/root/.cache/pip HOME=/tmp/validation-home
mkdir -p /work/base /work/feature /out /tmp/validation-home
tar -xf /inputs/base.tar -C /work/base || exit 30
tar -xf /inputs/feature.tar -C /work/feature || exit 31
(cd /work/feature && sha256sum -c /inputs/source.sha256) > /out/source-integrity.log 2>&1 || exit 32
(cd /work/feature && sha256sum -c /inputs/prior-source.sha256) > /out/prior-source-identity.log 2>&1 || exit 33
python - <<'PY_FIXTURE'
import io,tarfile,tempfile
from pathlib import Path
with tempfile.TemporaryDirectory() as t:
 p=Path(t);b=io.BytesIO()
 with tarfile.open(fileobj=b,mode='w') as a:
  m=tarfile.TarInfo('nested/value');m.size=3;a.addfile(m,io.BytesIO(b'yes'))
 b.seek(0)
 with tarfile.open(fileobj=b) as a:a.extractall(p,filter='data')
 assert (p/'nested/value').read_bytes()==b'yes'
 assert (p/'nested/value').read_bytes()!=b'no'
print('HARNESS_FIXTURE_PASS')
PY_FIXTURE
[ "$?" = 0 ] || exit 34
apt-get -o Acquire::Retries=3 update > /out/apt.log 2>&1 || exit 35
apt-get -o Acquire::Retries=3 install -y --no-install-recommends git ffmpeg ca-certificates curl procps unzip util-linux build-essential nodejs npm >> /out/apt.log 2>&1 || exit 36
python -m venv /opt/joint || exit 37
/opt/joint/bin/python -m pip install --retries 5 -r /inputs/joint-freeze.txt --report /out/install-report.json > /out/install.log 2>&1 || exit 38
/opt/joint/bin/python -m pip freeze --all > /out/installed-freeze.txt
python - <<'PY_FREEZE'
from pathlib import Path
assert set(Path('/inputs/joint-freeze.txt').read_text().splitlines()) == set(Path('/out/installed-freeze.txt').read_text().splitlines()), 'FROZEN_DEPENDENCY_MISMATCH'
PY_FREEZE
[ "$?" = 0 ] || exit 41
/opt/joint/bin/python -m pip check > /out/pip-check.log 2>&1 || exit 39
node --version > /out/node-version.txt
npm --version > /out/npm-version.txt
useradd -m -u 1001 validator || exit 40
mkdir -p /work/base/tests/integration
cp -a /work/feature/tests/integration/. /work/base/tests/integration/
chown -R 1001:1001 /work /out /tmp/validation-home
for lane in feature base; do
 (cd "/work/$lane" && runuser -u validator -- /opt/joint/bin/python -m pytest tests/integration -q -vv --junitxml="/out/$lane-integration.xml") > "/out/$lane-integration.log" 2>&1
 printf '%s\t%s\n' "$lane" "$?" >> /out/exit-codes.tsv
done
python - <<'PY_COMPARE' 2>&1 | tee /out/compare.log
from pathlib import Path
import xml.etree.ElementTree as ET,json
p=Path('/out');rows=dict(x.split('\t') for x in (p/'exit-codes.tsv').read_text().splitlines());summary={}
for lane in ('feature','base'):
 cases=list(ET.parse(p/(lane+'-integration.xml')).getroot().iter('testcase'))
 assert len(cases)==1,(lane,len(cases))
 case=cases[0]
 assert case.find('error') is None and case.find('skipped') is None,(lane,'setup error/skip')
 failed=case.find('failure')
 if lane=='feature':assert rows[lane]=='0' and failed is None,'FEATURE_INTEGRATION_NOT_PASS'
 else:assert rows[lane]=='1' and failed is not None and 'branch must create a new session' in failed.get('message',''),'BASE_CONTROL_NOT_EXPECTED_ASSERTION'
 summary[lane]={'tests':1,'result':'pass' if lane=='feature' else 'expected product regression assertion'}
(p/'fresh-integration-result.json').write_text(json.dumps(summary,indent=2)+'\n')
print(json.dumps(summary))
PY_COMPARE
