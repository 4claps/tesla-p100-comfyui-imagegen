#!/usr/bin/env python3
"""Rebuild out/index.html: one browse page for every picture and clip in the output folder."""
import os,re,html,collections,time
os.chdir("/data/imagegen/out")
files=[]
for r,d,f in os.walk("."):
    for x in f:
        if x.lower().endswith((".png",".mp4",".webm",".webp")): files.append(os.path.relpath(os.path.join(r,x),"."))
g=collections.defaultdict(list)
for p in files:
    b=os.path.basename(p); k=re.split(r"_(?:portrait|landscape|poster|objects|illustration|keeper|warm|f\d{3}|s\d|seed\d+|\d{5})",b)[0]
    g[("today: template tests" if b.startswith("t_") else "earlier")+" / "+k].append(p)
css="body{font-family:sans-serif;background:#151515;color:#ddd;margin:16px}h2{font-size:16px;margin:28px 0 8px;border-bottom:1px solid #444}div.g{display:grid;grid-template-columns:repeat(auto-fill,minmax(230px,1fr));gap:8px}figure{margin:0}img,video{width:100%;border-radius:4px;display:block}figcaption{font-size:11px;color:#999;word-break:break-all}a{color:inherit}"
o=["<!doctype html><meta charset=utf-8><meta name=viewport content=\"width=device-width,initial-scale=1\"><title>P100 outputs</title><style>"+css+"</style><h1>P100 image and video outputs</h1><p>"+str(len(files))+" files, page built "+time.strftime("%H:%M")+". Click a picture for full size.</p>"]
for k in sorted(g, key=lambda k:(not k.startswith("today"),k)):
    o.append("<h2>"+html.escape(k)+" ("+str(len(g[k]))+")</h2><div class=g>")
    for p in sorted(g[k]):
        q=html.escape(p)
        m="<video src=\""+q+"\" controls loop muted preload=metadata></video>" if p.endswith((".mp4",".webm")) else "<a href=\""+q+"\"><img loading=lazy src=\""+q+"\"></a>"
        o.append("<figure>"+m+"<figcaption>"+html.escape(os.path.basename(p))+"</figcaption></figure>")
    o.append("</div>")
open("index.html","w").write("\n".join(o)); print(len(files),"files",len(g),"groups")
