import csv, os, glob, sys, json, yaml
SC='C:/Users/hrach/AppData/Local/Temp/claude/C--Users-hrach-Documents-coreval/ec04e390-0282-4a3c-b0eb-c1ca4c044f17/scratchpad'
UP='data-raw/upstream/cdisc-open-rules'
ROOT={'published':f'{UP}/Published','deprecated_dir':f'{UP}/Deprecated',
      'fda_business_rules_draft':f'{UP}/Unpublished/FDA Business Rules',
      'sdtmig_draft':f'{UP}/Unpublished/SDTMIG','sendig_draft':f'{UP}/Unpublished/SENDIG'}
folders={r['id']:r for r in csv.DictReader(open(f'{SC}/folders.csv',newline='',encoding='utf-8'))}
fails=[r for r in csv.DictReader(open('tests/conformance/scoreboard.csv',newline='',encoding='utf-8')) if r['status']=='FAIL']

def read_csv(p):
    with open(p,encoding='utf-8-sig',newline='') as fh: return list(csv.DictReader(fh))

def norm(v):
    v=(v or '').strip()
    # numeric-insensitive compare: "200.00" == "200"
    try:
        f=float(v)
        return ('num',f)
    except ValueError:
        return ('str',v)

def phantom_operations(rd):
    """Signature 3: the sheet reports an Operations variable ($name) that the
    rule as published does not define. The answers were generated from a
    different version of the rule. CORE-000884's negative sheet reports
    $age_count and $agetxt_count; the shipped rule declares only $ageu_count."""
    try:
        rule = yaml.safe_load(open(os.path.join(rd, 'rule.yml'), encoding='utf-8')) or {}
    except Exception:
        return []
    declared = {o.get('id') for o in (rule.get('Operations') or []) if o.get('id')}
    out = []
    for rc in glob.glob(os.path.join(rd, '*', '*', 'results', 'results.csv')) +               glob.glob(os.path.join(rd, '*', 'results', 'results.csv')):
        for row in read_csv(rc):
            var = (row.get('Variable') or '').strip()
            if var.startswith('$') and var not in declared:
                out.append(f'sheet reports {var}, which the rule does not declare '
                           f'(it declares {sorted(declared) or "none"})')
                break
    return out

def sheet_never_generated(rd):
    """Signature 2: a `negative` case whose results.csv is header-only while its
    data differs from the matching `positive` case. The fixture injected a
    violation and recorded no answer for it, so an empty expectation there is
    an absent answer, not a statement that the data is clean. Proven on
    CORE-000339, whose negative ts.csv carries 7 corrupted TSVCDREF values
    ('ISO3166-1 alpha-3', 'ISO 3166-1 alpha-') against a positive case where
    all 7 are correct - and whose negative sheet is empty."""
    out=[]
    for neg in sorted(glob.glob(os.path.join(rd,'negative','*'))+[os.path.join(rd,'negative')]):
        rc=os.path.join(neg,'results','results.csv')
        dd=os.path.join(neg,'data')
        if not os.path.exists(rc) or not os.path.isdir(dd): continue
        if len([r for r in read_csv(rc)])>0: continue          # sheet has expectations
        pos=neg.replace(os.sep+'negative'+os.sep,os.sep+'positive'+os.sep)                .replace(os.sep+'negative',os.sep+'positive')
        pd_=os.path.join(pos,'data')
        if not os.path.isdir(pd_): continue
        for f in glob.glob(os.path.join(dd,'*.csv')):
            g=os.path.join(pd_,os.path.basename(f))
            if os.path.exists(g) and open(f,'rb').read()!=open(g,'rb').read():
                out.append(f'{os.path.basename(neg)}: empty sheet but {os.path.basename(f)} differs from the positive case')
                break
    return out

report=[]
for r in fails:
    rid=r['id']; f=folders.get(rid)
    if not f: report.append((rid,r['source'],'NO_FOLDER',0,0,[])); continue
    rd=os.path.join(ROOT[f['source']], f['folder'])
    cases=[]
    for pol in ('positive','negative'):
        base=os.path.join(rd,pol)
        if os.path.isdir(os.path.join(base,'data')): cases.append(base)
        else: cases.extend(sorted(glob.glob(os.path.join(base,'*'))))
    checked=mismatch=0; ex=[]
    for c in cases:
        rc=os.path.join(c,'results','results.csv')
        if not os.path.exists(rc): continue
        for row in read_csv(rc):
            ds,rec,var,val=row.get('Dataset',''),row.get('Record',''),row.get('Variable',''),row.get('Value','')
            if not var.strip() or not rec.strip(): continue      # placeholder / dataset-level
            dp=os.path.join(c,'data',ds.lower().replace('.csv','')+'.csv')
            if not os.path.exists(dp): continue
            data=read_csv(dp)
            try: i=int(rec)
            except ValueError: continue
            if i<1 or i>len(data): 
                checked+=1; mismatch+=1
                ex.append(f'{ds}#{i} {var}: record {i} does not exist ({len(data)} rows)')
                continue
            if var not in data[i-1]:
                continue                                          # variable absent = its own finding
            actual=data[i-1][var]
            checked+=1
            if norm(actual)!=norm(val):
                mismatch+=1
                if len(ex)<3: ex.append(f'{ds}#{i} {var}: sheet says {val!r}, data has {actual!r}')
    ungen = sheet_never_generated(rd) or phantom_operations(rd)
    if not mismatch and ungen:
        mismatch = -1                      # proven by signature 2, not the value test
        ex = ungen[:2]
    report.append((rid,r['source'],'',checked,mismatch,ex))

print(f'{"rule":<27}{"source":<24}{"rows":>6}{"bad":>5}  evidence')
stale=[];clean=[];nodata=[]
for rid,src,note,ch,mm,ex in report:
    if mm>0: tag='STALE (values contradict data)'; stale.append(rid)
    elif mm<0: tag='STALE (answer never generated)'; stale.append(rid)
    elif ch==0: tag='no-checkable-rows'; nodata.append(rid)
    else: tag='sheet matches data'; clean.append(rid)
    print(f'{rid:<27}{src:<24}{ch:>6}{mm:>5}  {tag}')
    for e in ex: print(f'{"":<27}    - {e}')
print()
print(f'STALE (sheet contradicts its own data): {len(stale)}')
print(f'sheet matches its data (needs another explanation): {len(clean)}')
print(f'nothing checkable (dataset-level/placeholder only): {len(nodata)}')
json.dump({'stale':stale,'clean':clean,'nodata':nodata}, open(f'{SC}/audit.json','w'))
