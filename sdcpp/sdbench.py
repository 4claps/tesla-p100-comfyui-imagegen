#!/usr/bin/env python3
"""stable-diffusion.cpp benchmark client: one sd-server, the fixed five-prompt set from prompts.sh plus a repeat prompt.
usage: sdbench.py --port 7860 --tag NAME --steps 4 [--cfg 1.0] [--sampler euler] [--seed 7] [--w 1024 --h 1024] [--extra JSON]
Prints one JSON line per image (wall seconds measured here) and saves the PNGs to --out."""
import argparse, base64, json, os, time, urllib.request
a = argparse.ArgumentParser()
a.add_argument("--port", type=int, default=7860); a.add_argument("--tag", required=True)
a.add_argument("--steps", type=int, default=4); a.add_argument("--cfg", type=float, default=1.0)
a.add_argument("--sampler", default="euler"); a.add_argument("--seed", type=int, default=7)
a.add_argument("--w", type=int, default=1024); a.add_argument("--h", type=int, default=1024)
a.add_argument("--extra", default=""); a.add_argument("--out", default="/data/imagegen/out/sdcpp")
a.add_argument("--only", default="")
o = a.parse_args()
PN = ["portrait", "landscape", "poster", "objects", "illustration"]
PT = [
 'Close-up portrait of an elderly fisherman with deep wrinkles, grey stubble and pale blue eyes, wearing a knitted wool cap, soft window light from the left, 85mm lens, shallow depth of field, natural skin texture',
 'Wide landscape of an alpine valley at sunrise, a winding river through pine forest, snow-capped peaks, low mist in the valley, wildflowers in the foreground, a small wooden cabin with smoke from the chimney, ultra detailed',
 'A vintage travel poster pinned to a brick wall, the poster shows a red steam train crossing a stone viaduct, large title text at the top reads "VISIT THE NORTHERN LINE", smaller text at the bottom reads "Departures daily at 9 AM", flat colors, art deco style',
 'A wooden kitchen table seen from above: three red apples on the left of a blue ceramic mug, two yellow lemons on the right of the mug, a folded green napkin below the mug, a silver spoon on the napkin, soft daylight',
 'Watercolor and ink illustration of a red fox reading a book under a large oak tree in autumn, falling orange leaves, a tiny lantern hanging from a branch, storybook style, visible paper texture',
]
KEEPER = 'A weathered lighthouse keeper in a yellow raincoat holding a brass lantern, standing on wet rocks at dusk, crashing waves behind him, a hand-painted wooden sign beside him reads "HOUSTON LIGHT", cinematic photograph, shallow depth of field, detailed skin and fabric texture'
os.makedirs(o.out, exist_ok=True)
def gen(name, prompt, seed):
    p = prompt + (f" <sd_cpp_extra_args>{o.extra}</sd_cpp_extra_args>" if o.extra else "")
    body = {"prompt": p, "negative_prompt": "", "steps": o.steps, "cfg_scale": o.cfg, "seed": seed, "width": o.w, "height": o.h,
            "sampler_name": o.sampler, "batch_size": 1}
    req = urllib.request.Request(f"http://127.0.0.1:{o.port}/sdapi/v1/txt2img", json.dumps(body).encode(), {"Content-Type": "application/json"})
    t0 = time.time()
    with urllib.request.urlopen(req, timeout=1800) as r:
        res = json.load(r)
    dt = time.time() - t0
    f = f"{o.out}/{o.tag}_{name}_s{seed}.png"
    imgs = res.get("images") or []
    if imgs:
        open(f, "wb").write(base64.b64decode(imgs[0].split(",")[-1]))
    print(json.dumps({"tag": o.tag, "image": name, "seed": seed, "wall_s": round(dt, 2), "file": f if imgs else None}), flush=True)
    return dt
# order as in the ComfyUI runs: keeper twice (first warms up), then a new prompt each time
sets = [("keeper_warm", KEEPER, 1), ("keeper", KEEPER, 1), ("keeper", KEEPER, 2)] + [(n, t, o.seed) for n, t in zip(PN, PT)]
if o.only:
    sets = [s for s in sets if s[0] in o.only.split(",")]
for n, t, s in sets:
    gen(n, t, s)
