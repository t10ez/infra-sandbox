import csv, statistics as st
D='/Users/jonathan/Workspace/t10e/poc-s3-guard-duty/results/'
rows=list(csv.DictReader(open(D+'stages.csv')))
data=[]
for r in rows:
    f=lambda k: float(r[k])
    data.append(dict(mb=int(r['size_mb']),rep=f('t_rep')-f('t_up'),scan=f('t_tag')-f('t_rep'),mv=f('t_app')-f('t_tag'),tot=f('t_app')-f('t_up')))
def fit(xs,ys):
    mx,my=st.mean(xs),st.mean(ys)
    b=sum((a-mx)*(c-my) for a,c in zip(xs,ys))/sum((a-mx)**2 for a in xs)
    return b, st.correlation(xs,ys)**2
xs=[d['mb'] for d in data]
rep_b,rep_r=fit(xs,[d['rep'] for d in data])
mv_b,mv_r=fit(xs,[d['mv'] for d in data])
sx=[d['mb'] for d in data if d['mb']!=100]; sy=[d['scan'] for d in data if d['mb']!=100]
sc_b,sc_r=fit(sx,sy)
med=lambda k: st.median(d[k] for d in data)
S=7.0; X0=110
bars=[]; grid=[]
for t in range(0,71,10):
    x=X0+t*S
    grid.append(f'<line class="grid" x1="{x}" x2="{x}" y1="10" y2="{20+8*34-6}"/><text x="{x}" y="{20+8*34+14}" text-anchor="middle">{t}{" s" if t==70 else ""}</text>')
for i,d in enumerate(data):
    y=20+i*34; x=X0
    bars.append(f'<text class="lbl" x="100" y="{y+15}" text-anchor="end">{d["mb"]} MB</text>')
    for k,c in (('rep','b-srr'),('scan','b-scan'),('mv','b-evt')):
        w=d[k]*S
        bars.append(f'<rect class="{c}" x="{x:.1f}" y="{y}" width="{w:.1f}" height="22"/>')
        x+=w
    bars.append(f'<text class="tot" x="{x+8:.1f}" y="{y+15}">{d["tot"]:.0f} s</text>')
trs=''.join(f'<tr><td>{d["mb"]} MB</td><td class="num">{d["rep"]:.1f} s</td><td class="num{" hot" if d["scan"]>20 else ""}">{d["scan"]:.1f} s</td><td class="num">{d["mv"]:.1f} s</td><td class="num">{d["tot"]:.1f} s</td><td class="num">{d["rep"]/d["tot"]*100:.0f}%</td></tr>' for d in data)
html=open(D+'stage_template.html').read()
html=(html.replace('@@GRID@@',''.join(grid)).replace('@@BARS@@',''.join(bars)).replace('@@ROWS@@',trs)
 .replace('@@REPMED@@',f'{med("rep"):.0f}').replace('@@REPB@@',f'{rep_b:.3f}').replace('@@REPR@@',f'{rep_r:.2f}')
 .replace('@@SCMED@@',f'{med("scan"):.1f}').replace('@@SCB@@',f'{sc_b:.3f}').replace('@@SCR@@',f'{sc_r:.2f}')
 .replace('@@MVMED@@',f'{med("mv"):.1f}').replace('@@MVB@@',f'{mv_b:.3f}').replace('@@MVR@@',f'{mv_r:.2f}'))
open(D+'stage-breakdown.html','w').write(html)
print('ok',round(rep_b,4),round(rep_r,2),round(sc_b,4),round(sc_r,2),round(mv_b,4),round(mv_r,2),med('rep'),med('scan'),med('mv'))
