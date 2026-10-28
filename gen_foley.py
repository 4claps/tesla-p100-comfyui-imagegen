#!/usr/bin/env python3
"""Add generated sound to a silent clip with HunyuanVideo-Foley on a ComfyUI server (custom node ComfyUI-HunyuanVideo-Foley). Prints one JSON line.
  gen_foley.py --port 8188 --video /data/imagegen/out/clip.mp4 --prompt "boots on gravel, fabric rustle" --prefix clip_foley [--fps 24] [--seed 1]
The clip is uploaded to the server's input folder, its frames go to the Foley sampler, and the new audio is muxed back with CreateVideo."""
import argparse, json, os, time, urllib.request, uuid
a = argparse.ArgumentParser()
a.add_argument("--host", default="127.0.0.1"); a.add_argument("--port", type=int, default=8188)
a.add_argument("--video", required=True); a.add_argument("--prompt", required=True); a.add_argument("--negative", default="noisy, harsh, music, speech")
a.add_argument("--prefix", default="foley"); a.add_argument("--fps", type=float, default=24.0); a.add_argument("--frames", type=int, default=49)
a.add_argument("--steps", type=int, default=50); a.add_argument("--cfg", type=float, default=4.5); a.add_argument("--seed", type=int, default=1)
a.add_argument("--model", default="hunyuanvideo_foley.safetensors"); a.add_argument("--precision", default="fp16"); a.add_argument("--quant", default="none")
a.add_argument("--timeout", type=int, default=3600)
o = a.parse_args()
U = f"http://{o.host}:{o.port}"
name = os.path.basename(o.video)
b = uuid.uuid4().hex  # multipart upload into ComfyUI's input folder
body = (f'--{b}\r\nContent-Disposition: form-data; name="image"; filename="{name}"\r\nContent-Type: video/mp4\r\n\r\n').encode() + open(o.video, "rb").read() + \
       (f'\r\n--{b}\r\nContent-Disposition: form-data; name="overwrite"\r\n\r\ntrue\r\n--{b}--\r\n').encode()
req = urllib.request.Request(U + "/upload/image", data=body, headers={"Content-Type": f"multipart/form-data; boundary={b}"})
up = json.loads(urllib.request.urlopen(req, timeout=120).read())
wf = {
 "1": {"class_type": "LoadVideo", "inputs": {"file": up["name"]}},
 "2": {"class_type": "GetVideoComponents", "inputs": {"video": ["1", 0]}},
 "3": {"class_type": "HunyuanModelLoader", "inputs": {"model_name": o.model, "precision": o.precision, "quantization": o.quant}},
 "4": {"class_type": "HunyuanDependenciesLoader", "inputs": {"vae_name": "vae_128d_48k_fp16.safetensors", "synchformer_name": "synchformer_state_dict_fp16.safetensors"}},
 "5": {"class_type": "HunyuanFoleySampler", "inputs": {"hunyuan_model": ["3", 0], "hunyuan_deps": ["4", 0], "frame_rate": o.fps, "duration": round(o.frames / o.fps, 2),
        "prompt": o.prompt, "negative_prompt": o.negative, "cfg_scale": o.cfg, "steps": o.steps, "sampler": "euler", "batch_size": 1, "seed": o.seed,
        "force_offload": True, "image": ["2", 0]}},
 "6": {"class_type": "CreateVideo", "inputs": {"images": ["2", 0], "audio": ["5", 0], "fps": o.fps}},
 "7": {"class_type": "SaveVideo", "inputs": {"video": ["6", 0], "filename_prefix": o.prefix, "format": "auto", "codec": "auto"}},
}
def call(path, body=None):
    r = urllib.request.Request(U + path, data=json.dumps(body).encode() if body is not None else None, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(r, timeout=60) as x: return json.loads(x.read())
t0 = time.time()
try: pid = call("/prompt", {"prompt": wf})["prompt_id"]
except urllib.error.HTTPError as e:
    print(json.dumps({"prefix": o.prefix, "error": e.read().decode()[:1500]})); raise SystemExit(1)
res = {"prefix": o.prefix, "video": name, "prompt": o.prompt, "steps": o.steps, "cfg": o.cfg, "seed": o.seed, "model": o.model, "precision": o.precision}
while time.time() - t0 < o.timeout:
    h = call(f"/history/{pid}")
    if pid in h:
        st = h[pid].get("status", {}); res["status"] = st.get("status_str"); res["wall_s"] = round(time.time() - t0, 2)
        res["files"] = [i["filename"] for n in h[pid].get("outputs", {}).values() for v in n.values() if isinstance(v, list) for i in v if isinstance(i, dict) and "filename" in i]
        if res["status"] != "success": res["messages"] = json.dumps(st.get("messages"))[:1500]
        break
    time.sleep(0.5)
else: res["status"] = "timeout"
print(json.dumps(res)); raise SystemExit(0 if res.get("status") == "success" else 1)
