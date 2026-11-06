"""Strict retained JUnit comparison, explicit renamed regression cases only."""
import json,xml.etree.ElementTree as ET
from pathlib import Path
p=Path('/out');rows=dict(x.split('\t') for x in (p/'exit-codes.tsv').read_text().splitlines());summary={};problems=[]
def cases(name):
 root=ET.parse(p/(name+'.xml')).getroot();d={}
 for c in root.iter('testcase'):
  k=c.get('classname','')+'::'+c.get('name','')
  assert k not in d,('duplicate',name,k)
  d[k]=('error' if c.find('error') is not None else 'failure' if c.find('failure') is not None else 'skip' if c.find('skipped') is not None else 'pass',c)
 assert d,('empty',name)
 return d
def counts(d):return {s:sum(v[0]==s for v in d.values()) for s in ('pass','skip','failure','error')}
renames={'test_nonboolean_branch_is_ignored_not_coerced_or_rejected':'test_nonboolean_branch_is_refused_not_coerced','test_true_without_point_is_ignored_over_http':'test_true_without_point_is_refused_over_http','test_unavailable_checkpoint_is_http409_before_any_target_work[invalid-head]':'test_unavailable_checkpoint_is_http409_before_any_target_work[invalid-commit]'}
for lane in ('gateway','runner','benchmark','conformance'):
 b=cases('base-'+lane);f=cases('feature-'+lane);missing=set(b)-set(f);allowed=[]
 for k in missing:
  name=k.split('::')[-1];stem=name.split('[')[0]
  target=renames.get(name) or renames.get(stem)
  if lane=='gateway' and target and any(x.split('::')[-1].startswith(target) for x in f):allowed.append(k)
 unexpected=missing-set(allowed)
 newskip={k for k,v in f.items() if v[0]=='skip'}-{k for k,v in b.items() if v[0]=='skip'}
 lostpass=[k for k in b.keys() & f.keys() if b[k][0]=='pass' and f[k][0]!='pass']
 summary[lane]={'base':counts(b),'candidate':counts(f),'intentional_renames':sorted(allowed),'unexpected_missing':sorted(unexpected),'new_skips':sorted(newskip),'lost_pass':lostpass}
 if rows.get('base-'+lane)!='0' or rows.get('feature-'+lane)!='0' or unexpected or newskip or lostpass:problems.append(lane+' incomplete/failing/regressed')
for lane in ('gateway','runner','integration'):
 d=cases('focused-'+lane);summary['focused-'+lane]=counts(d)
 if rows.get('focused-'+lane)!='0' or any(v[0]!='pass' for v in d.values()):problems.append('focused-'+lane+' not all passed')
for lane in ('gateway','runner'):
 d=cases('negative-'+lane);summary['negative-'+lane]=counts(d)
 failed=[c for s,c in d.values() if s=='failure']
 summary['negative-'+lane]['failing_test_ids']=[k for k,(s,c) in d.items() if s=='failure']
 allowed_exceptions={'test_the_turn_is_the_selected_responses_place_in_its_session':'KeyError','test_a_checkpoint_newer_than_the_point_still_branches_from_it':'branching.BranchUnavailable'}
 def legitimate(k,c):
  message=c.find('failure').get('message','')
  return message.startswith('AssertionError') or (k.split('::')[-1] in allowed_exceptions and message.startswith(allowed_exceptions[k.split('::')[-1]]))
 if rows.get('negative-'+lane)!='1' or not failed or any(s in ('error','skip') for s,c in d.values()) or not all(legitimate(k,c) for k,(s,c) in d.items() if s=='failure'):problems.append('negative-'+lane+' unexpected failure shape')
for name in ('feature-schema-generate','apt-update','apt-install','gw-install','runner-install','joint-install','gw-pip-check','runner-pip-check','joint-pip-check','base-conformance-install','feature-conformance-install','base-schema','feature-schema','base-site','feature-site','base-python-licenses','feature-python-licenses','base-badge','feature-badge','base-integration'):
 if rows.get(name)!='0':problems.append(name+' not success')
summary['problems']=problems
(p/'suite-comparison.json').write_text(json.dumps(summary,indent=2)+'\n');print(json.dumps(summary,indent=2));raise SystemExit(bool(problems))
