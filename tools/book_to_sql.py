import json,glob,re,sys,os
B=sys.argv[1]; out=sys.argv[2]; os.makedirs(out,exist_ok=True)
LEG={'series':('event','series',[]),'edition':('event','edition',[]),'host':('venue',None,[]),'brand':('org',None,['sponsor']),'supplier':('org',None,['supplier']),'media':('org',None,['media']),'investor':('org',None,['owner'])}
KINDS={'person','team','club','org','event','entry','class','venue','record'}
E=[];probs=[]
for f in sorted(glob.glob(B+'/entities/*.json')):
    k=f.split('/')[-1][:-5]; e=json.load(open(f))
    t=e.get('type'); lv=e.get('level') or None; sec=e.get('sectors') or []; lt=e.get('legacyType')
    if t in LEG:
        lt=lt or t; t,l2,s2=LEG[t]; lv=lv or l2; sec=sec or s2
    if t not in KINDS: probs.append(('kind',k,t)); t='org'
    if t=='event' and not lv: lv='event'
    if t!='event': lv=None
    if t!='org': sec=[]
    c=(e.get('country') or '').strip().upper()
    if c and not re.fullmatch(r'[A-Z]{3}',c): probs.append(('country',k,c)); c=''
    if not re.fullmatch(r'[a-z0-9][a-z0-9-]*',k): probs.append(('id',k))
    E.append({'id':k,'name':e['name'],'type':t,'sectors':sec,'level':lv,'country':c,'note':e.get('note') or '','legacy_type':lt})
ids={x['id'] for x in E}
L=[]
for f in sorted(glob.glob(B+'/links/*.json')):
    i=f.split('/')[-1][:-5]; l=json.load(open(f))
    ctx=l.get('context') or None
    if ctx and ctx not in ids: probs.append(('ctx',i,ctx)); ctx=None
    if l['from'] not in ids or l['to'] not in ids: probs.append(('dangling',i)); continue
    if l['from']==l['to']: probs.append(('self',i)); continue
    sd,ed=(l.get('start') or '').strip(),(l.get('end') or '').strip()
    for v in (sd,ed):
        if v and not re.match(r'^\d{4}(-\d{2})?',v): probs.append(('date',i,v))
    sd='' if sd and not re.match(r'^\d{4}',sd) else sd; ed='' if ed and not re.match(r'^\d{4}',ed) else ed
    cat=l.get('cat') if l.get('cat') in ('own','spon','ppl','str') else 'str'
    L.append({'id':i,'from_id':l['from'],'to_id':l['to'],'role':l.get('role') or '','cat':cat,'context_id':ctx,'start_date':sd,'end_date':ed,'source':l.get('source') or '','note':l.get('note') or ''})
print(len(E),len(L)); print(probs)
def chunks(rows,n):
    for i in range(0,len(rows),n): yield rows[i:i+n]
q=0
for i,ch in enumerate(chunks(E,450)):
    j=json.dumps(ch,ensure_ascii=False,separators=(',',':'))
    assert '$J$' not in j
    sql="insert into public.entities(id,name,type,sectors,level,country,note,legacy_type) select id,name,type,coalesce(sectors,'{}'),level,country,note,legacy_type from jsonb_to_recordset($J$"+j+"$J$::jsonb) as x(id text,name text,type text,sectors text[],level text,country text,note text,legacy_type text) on conflict (id) do update set name=excluded.name,type=excluded.type,sectors=excluded.sectors,level=excluded.level,country=excluded.country,note=excluded.note,legacy_type=excluded.legacy_type;"
    open(f'{out}/e{i}.sql','w').write(sql); print('e',i,len(sql))
for i,ch in enumerate(chunks(L,320)):
    j=json.dumps(ch,ensure_ascii=False,separators=(',',':'))
    sql="insert into public.links(id,from_id,to_id,role,cat,context_id,start_date,end_date,source,note) select * from jsonb_to_recordset($J$"+j+"$J$::jsonb) as x(id text,from_id text,to_id text,role text,cat text,context_id text,start_date text,end_date text,source text,note text) on conflict (id) do update set from_id=excluded.from_id,to_id=excluded.to_id,role=excluded.role,cat=excluded.cat,context_id=excluded.context_id,start_date=excluded.start_date,end_date=excluded.end_date,source=excluded.source,note=excluded.note;"
    open(f'{out}/l{i}.sql','w').write(sql); print('l',i,len(sql))
