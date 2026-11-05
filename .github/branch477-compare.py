"""Retained-result comparison; missing evidence is never a pass."""
import json
from pathlib import Path
import xml.etree.ElementTree as ET
p=Path('/out');problems=[];summary={}
rows=dict(line.split('\t') for line in (p/'exit-codes.tsv').read_text().splitlines())
def cases(name):
 try:
  root=ET.parse(p/(name+'.xml')).getroot()
  result={}
  for c in root.iter('testcase'):
   key=c.get('classname','')+'::'+c.get('name','')
   if key in result:raise ValueError('duplicate case '+key)
   state='error' if c.find('error') is not None else 'failure' if c.find('failure') is not None else 'skip' if c.find('skipped') is not None else 'pass'
   result[key]=(state,c)
  if not result:raise ValueError('zero tests')
  return result
 except Exception as error:
  problems.append(name+': missing/unreadable JUnit '+str(error));return {}
for lane in ('gateway','runner','benchmark','conformance'):
 base=cases('base-'+lane);feature=cases('feature-'+lane)
 bad=lambda a:{k for k,(state,_) in a.items() if state in ('error','failure')}
 skip=lambda a:{k for k,(state,_) in a.items() if state=='skip'}
 newbad=bad(feature)-bad(base);newskip=skip(feature)-skip(base);missing=set(base)-set(feature)
 summary[lane]={'base_failures':sorted(bad(base)),'feature_failures':sorted(bad(feature)), 'new_failures':sorted(newbad),'new_skips':sorted(newskip),'missing_cases':sorted(missing)}
 if newbad or newskip or missing:problems.append(lane+': regressions/skips/missing cases')
 if rows.get('base-'+lane) not in ('0','1') or rows.get('feature-'+lane) not in ('0','1'):problems.append(lane+': abnormal/missing pytest exit')
for lane in ('schema','site','python-licenses','badge'):
 b=rows.get('base-'+lane);f=rows.get('feature-'+lane)
 summary[lane]={'base_exit':b,'feature_exit':f}
 if b is None or f is None or f!=b:problems.append(lane+': changed/missing exit')
expected=json.loads(Path('/inputs/new-tests.json').read_text())
for lane in ('gateway','runner','integration'):
 data=cases('focused-'+lane)
 executed={key.split('::')[-1].split('[')[0] for key,(state,_) in data.items() if state=='pass'}
 if set(expected[lane])-executed or any(s!='pass' for s,_ in data.values()) or rows.get('focused-'+lane)!='0':problems.append('focused-'+lane+': new tests not all executed/passed')
conformance=cases('feature-conformance')
executed={k.split('::')[-1].split('[')[0] for k,(s,_) in conformance.items() if s=='pass'}
if set(expected['conformance'])-executed:problems.append('new conformance tests not all passed')
negative=cases('base-regression')
failures=[c for s,c in negative.values() if s=='failure']
if rows.get('base-regression')!='1' or len(failures)!=1 or any(s in ('skip','error') for s,_ in negative.values()) or 'branch must create a new session' not in ET.tostring(failures[0],encoding='unicode'):
 problems.append('negative control did not reach the exact expected product assertion')
for name in ('apt-update','apt-install','gw-install','runner-install','joint-install','base-conformance-install','feature-conformance-install'):
 if rows.get(name)!='0':problems.append(name+': unavailable dependency/tool lane')
summary['problems']=problems
(p/'suite-comparison.json').write_text(json.dumps(summary,indent=2))
print(json.dumps(summary,indent=2))
raise SystemExit(1 if problems else 0)
