import json,xml.etree.ElementTree as E
from pathlib import Path
p=Path('/out');rows=dict(x.split('\t') for x in (p/'exit-codes.tsv').read_text().splitlines());summary={}
for n in ['apt-update','apt-install','gw-install','gw-pip-check','feature-gateway','runner-install','runner-pip-check','joint-install','joint-pip-check','feature-schema-generate','focused-runner','focused-integration','feature-runner']:
 assert rows.get(n)=='0',(n,rows.get(n))
for n in ['focused-runner','focused-integration','feature-runner']:
 cases=list(E.parse(p/(n+'.xml')).getroot().iter('testcase'));assert cases,n
 assert all(c.find('failure') is None and c.find('error') is None for c in cases),n
 ids=[c.get('classname','')+'::'+c.get('name','') for c in cases];assert len(ids)==len(set(ids)),n
 summary[n]={'passed':sum(c.find('skipped') is None for c in cases),'skipped':sum(c.find('skipped') is not None for c in cases),'ids':ids}
 if n!='feature-runner':assert summary[n]['skipped']==0,n
old=list(E.parse('/inputs/previous-runner.xml').getroot().iter('testcase'))
new={c.get('classname','')+'::'+c.get('name',''):c for c in cases}
for c in old:
 k=c.get('classname','')+'::'+c.get('name','');assert k in new,('lostcase',k)
 assert (c.find('skipped') is not None)==(new[k].find('skipped') is not None),('changedskip',k)
new_ids=set(new)-{c.get('classname','')+'::'+c.get('name','') for c in old}
assert len(new_ids)==5 and all('test_turn_bound_to_its_session' in x for x in new_ids),new_ids
assert all(new[k].find('skipped') is None for k in new_ids),('newcaseskipped',new_ids)
assert summary['feature-runner']['skipped']==19
assert summary['focused-integration']=={'passed':1,'skipped':0,'ids':summary['focused-integration']['ids']}
assert len(summary['focused-integration']['ids'])==1
summary['new_upstream_cases']=sorted(new_ids)
(p/'verification.json').write_text(json.dumps(summary,indent=2)+'\n');print(json.dumps({k:({a:b for a,b in v.items() if a!='ids'} if isinstance(v,dict) else v) for k,v in summary.items()}))

g=list(E.parse(p/'feature-gateway.xml').getroot().iter('testcase'));oldg=list(E.parse('/inputs/previous-gateway.xml').getroot().iter('testcase'))
key=lambda c:c.get('classname','')+'::'+c.get('name','')
gm={key(c):c for c in g};assert len(gm)==len(g)==len(oldg)
assert set(gm)=={key(c) for c in oldg}
assert all(c.find('failure') is None and c.find('error') is None for c in g)
assert sum(c.find('skipped') is not None for c in g)==17
assert all((c.find('skipped') is not None)==(gm[key(c)].find('skipped') is not None) for c in oldg)
summary['feature-gateway']={'passed':len(g)-17,'skipped':17}
(p/'verification.json').write_text(json.dumps(summary,indent=2)+'\n');print(summary['feature-gateway'])
