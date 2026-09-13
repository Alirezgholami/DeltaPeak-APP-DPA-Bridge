#!/usr/bin/env python3
from collections import defaultdict
from pathlib import Path
import re, sqlite3
ROOT=Path(__file__).resolve().parents[1]
def text(p): return (ROOT/p).read_text(encoding='utf-8')
def fail(m): raise SystemExit('DPA v0.5.12 DEDUPE QA FAILED: '+m)
def req(h,n,m):
    if n not in h: fail(m)
pub=text('pubspec.yaml'); info=text('lib/app_info.dart'); main=text('lib/main.dart'); dedupe=text('lib/data/peak_identity_deduper.dart'); home=text('lib/pages/home_page.dart')
req(pub,'version: 0.5.12+21','version mismatch'); req(info,"appVersion = '0.5.12'",'app info mismatch'); req(info,'buildNumber = 21','build mismatch'); req(main,'PeakIdentityDeduper.run(PeakRepository.instance.databasePath)','runtime hook missing')
for n in ('PEAK-DEDUP-NAME-PROVINCE-COUNTY-V2-20260913','same province + county','_sameRoute(','dedupe_same_county_removed_peaks','dedupe_same_route_merged','dedupe_distinct_routes_preserved','Peak dedupe safety stop'): req(dedupe,n,'missing '+n)
req(home,'دانشنامه قله های ایران','subtitle missing'); req(home,'فیلتر موارد نقص برای تکمیل','missing-data filter missing')
def norm(v):
    if v is None:return ''
    tr=str.maketrans({'ي':'ی','ى':'ی','ے':'ی','ك':'ک','ۀ':'ه','ة':'ه','ؤ':'و','إ':'ا','أ':'ا','ٱ':'ا'})
    s=str(v).replace('\u00a0',' ').replace('\u202f',' ').replace('\u200c',' ').strip().translate(tr); s=re.sub(r'[\u064b-\u065f\u0670\u06d6-\u06edـ]','',s); return re.sub(r'\s+',' ',s).strip().casefold()
def same_route(a,b):
    ah=(a['file_sha256'] or '').strip().lower(); bh=(b['file_sha256'] or '').strip().lower()
    if ah and bh:return ah==bh
    an,bn=norm(a['name']),norm(b['name']); return bool(an and an==bn and norm(a['trailhead'])==norm(b['trailhead']))
con=sqlite3.connect(ROOT/'assets/peaks.db'); con.row_factory=sqlite3.Row; peaks=list(con.execute('select * from peaks where coalesce(is_deleted,0)=0')); by=defaultdict(list)
for r in peaks:
    k=(norm(r['name']),norm(r['province']),norm(r['county']))
    if all(k):by[k].append(r)
groups=[g for g in by.values() if len(g)>1]; redundant=sum(len(g)-1 for g in groups)
if redundant!=59:fail(f'expected 59 redundant peaks, found {redundant}')
rr=0
for g in groups:
    routes=[]
    for p in g: routes.extend(con.execute('select * from gpx_routes where peak_id=? and coalesce(is_deleted,0)=0',(p['id'],)))
    classes=[]
    for r in routes:
        for c in classes:
            if same_route(c[0],r): c.append(r); break
        else: classes.append([r])
    rr+=sum(len(c)-1 for c in classes)
routes=con.execute('select count(*) from gpx_routes where coalesce(is_deleted,0)=0').fetchone()[0]; con.close()
if rr!=52:fail(f'expected 52 duplicate routes, found {rr}')
if len(peaks)-redundant!=1940:fail('canonical peak count must be 1940')
if routes-rr!=867:fail('canonical route count must be 867')
print('DPA v0.5.12 DEDUPE QA PASSED: 1999 -> 1940 peaks; 919 -> 867 active unique routes')
