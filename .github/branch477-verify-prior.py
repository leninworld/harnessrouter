"""Verify retained complete CI gates before reusing unchanged source evidence."""
import hashlib,json,subprocess,sys
from pathlib import Path
import xml.etree.ElementTree as ET
old='94a1dc14fa7fd3c7631ba446753123fa797753a8';base='8e1cf1b598a7ea864fda3a5de064b11289b6ac84'
def git(*args):return subprocess.check_output(['git',*args])
def verify_metadata(path):
 metadata=json.loads(Path(path).read_text())
 assert metadata['id']==41954591245
 assert metadata['head_branch']=='validation-response-branching-477-i4'
 assert metadata['path']=='.github/workflows/branch477-validation.yml'
 assert metadata['conclusion']=='failure'
 assert metadata['head_sha']=='f106ec78d17ab13cd98000440f0ae34ee025995e'
 assert git('rev-parse',metadata['head_sha']+'^').decode().strip()==old
 return metadata
if len(sys.argv)==3 and sys.argv[1]=='--metadata-only':
 verify_metadata(sys.argv[2]);print('PRIOR_RUN_METADATA_AND_PARENT_VERIFIED');raise SystemExit(0)
prior=Path(sys.argv[1]);out=Path(sys.argv[2]);feature=sys.argv[3]
metadata=verify_metadata(sys.argv[4])
assert git('rev-parse',feature+'^').decode().strip()==old
assert git('diff','--name-only',old,feature).decode().splitlines()==['tests/integration/test_response_branching.py']
assert (prior/'tested-head.txt').read_text().strip()==old
assert (prior/'tested.patch').read_bytes()==git('diff','--binary',base,old)
rows=dict(x.split('\t') for x in (prior/'exit-codes.tsv').read_text().splitlines())
summary={}
for name,expected in {'base-gateway':(1825,17),'feature-gateway':(1864,17),'base-runner':(1976,19),'feature-runner':(2076,19),'base-conformance':(173,0),'feature-conformance':(184,0),'base-benchmark':(18,0),'feature-benchmark':(18,0),'focused-gateway':(39,0),'focused-runner':(100,0)}.items():
 assert rows[name]=='0',(name,rows[name])
 cases=list(ET.parse(prior/(name+'.xml')).getroot().iter('testcase'))
 assert (len(cases),sum(c.find('skipped') is not None for c in cases))==expected,(name,len(cases))
 assert all(c.find('error') is None and c.find('failure') is None for c in cases),name
 summary[name]={'tests':len(cases),'skips':expected[1],'failures':0,'errors':0}
inventory_bytes=git('show',metadata['head_sha']+':.github/branch477-new-tests.json')
recorded_hashes=[line.split()[0] for line in (prior/'input-sha256.txt').read_text().splitlines() if line.endswith('/new-tests.json')]
assert len(recorded_hashes)==1 and hashlib.sha256(inventory_bytes).hexdigest()==recorded_hashes[0]
inventory=json.loads(inventory_bytes)
for key,report in [('gateway','focused-gateway.xml'),('runner','focused-runner.xml'),('conformance','feature-conformance.xml')]:
 cases=list(ET.parse(prior/report).getroot().iter('testcase'))
 passed={c.get('name','').split('[',1)[0] for c in cases if c.find('failure') is None and c.find('error') is None and c.find('skipped') is None}
 assert set(inventory[key]) <= passed,(key,set(inventory[key])-passed)
for name in ('apt-update','apt-install','gw-install','gw-pip-check','runner-install','runner-pip-check','joint-install','joint-pip-check','base-conformance-install','feature-conformance-install'):
 assert rows.get(name)=='0',(name,rows.get(name))
for name,value in rows.items():
 if name.startswith('apt-') or name.endswith(('-install','-pip-check','-conformance-install')):assert value=='0',(name,value)
for lane in ('schema','site','python-licenses','badge'):
 for side in ('base','feature'):assert rows[side+'-'+lane]=='0'
freeze=(prior/'joint-freeze.txt').read_bytes()
assert hashlib.sha256(freeze).hexdigest()=='5cd8ea2f322f86d8fab120f269403fff532c09ea68362969a23094bffd2ab47a'
assert all('==' in line and ' @ ' not in line and not line.startswith('-') for line in freeze.decode().splitlines() if line)
image=(prior/'image-digest.txt').read_text().strip();assert image=='python@sha256:b18b261e1b4974b4f321451ad5251ded85abb22c2b8b262da527dda1d031ab30'
out.write_text(json.dumps({'prior_run':41954591245,'prior_tested_head':old,'prior_run_conclusion':'failure: integration preflight; complete suites below passed','new_head':feature,'only_source_delta':'integration fixture model selection','complete_suites':summary,'other_complete_gates':'schema/site/python-licenses/badge pass on both sides','prior_unverified':['integration','negative control'],'image':image,'joint_freeze_sha256':hashlib.sha256(freeze).hexdigest()},indent=2)+'\n')
print('Prior complete gates and exact production-source identity verified; integration/control still require fresh execution.')
