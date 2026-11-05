"""Complete runner coverage, one module per fresh pytest process; no retries or exclusions."""
import json,os,subprocess,sys,time
from pathlib import Path
import xml.etree.ElementTree as ET
lane=sys.argv[1];root=Path('/work')/lane;out=Path('/out');folder=out/(lane+'-runner-diagnostic-modules');folder.mkdir()
files=sorted(root.joinpath('runner/tests').rglob('test_*.py'))
expected=json.loads(Path('/inputs/new-tests.json').read_text())['runner_modules_'+lane]
assert [str(f.relative_to(root)) for f in files]==expected and expected, 'Runner module inventory mismatch'
reports=[];suites=ET.Element('testsuites');valid=True;started=time.monotonic()
for file in files:
 report=folder/(file.stem+'.xml');log=folder/(file.stem+'.log')
 with log.open('wb') as output:
  try:
   result=subprocess.run(['/opt/runner/bin/python','-m','pytest',str(file.relative_to(root)),'-q','--junitxml='+str(report)],cwd=root,stdout=output,stderr=subprocess.STDOUT,timeout=240)
   code=result.returncode
  except subprocess.TimeoutExpired:
   code=124
 item={'file':str(file.relative_to(root)),'exit':code,'complete':False}
 try:
  item['pids_current']=Path('/sys/fs/cgroup/pids.current').read_text().strip()
 except OSError as error:item['pids_current']='unavailable: '+str(error)
 try:
  data=ET.parse(report).getroot();nodes=[data] if data.tag=='testsuite' else list(data.findall('testsuite'))
  assert nodes and any(list(n.iter('testcase')) for n in nodes)
  for node in nodes:suites.append(node)
  item['complete']=code in (0,1)
 except Exception as error:
  item['error']=str(error)
 if not item['complete']:valid=False
 reports.append(item)
 # Retain partial progress even on infrastructure termination. Never count missing modules as pass.
 (out/(lane+'-runner-diagnostic-modules.json')).write_text(json.dumps({'expected':[str(f.relative_to(root)) for f in files],'reports':reports,'complete':len(reports)==len(files) and valid,'elapsed_s':time.monotonic()-started},indent=2))
 ET.ElementTree(suites).write(out/(lane+'-runner-diagnostic.xml'),encoding='utf-8',xml_declaration=True)
print(json.dumps({'modules':len(files),'complete':valid,'failed':[r['file'] for r in reports if r['exit']!=0]}))
raise SystemExit(2 if not valid else 1 if any(r['exit']!=0 for r in reports) else 0)
