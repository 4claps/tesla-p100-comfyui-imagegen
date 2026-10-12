#!/usr/bin/env python3
"""Queue one Z-Image Turbo text-to-image job on a ComfyUI server and wait for it. Prints one JSON line.
  gen.py --port 8188 --prompt "..." --w 1024 --h 1024 --steps 8 --seed 1 --prefix name [--dtype default]
         [--sampler res_multistep] [--scheduler simple] [--shift 3.0] [--unet file] [--clip file] [--batch 1]"""
import argparse, json, time, urllib.request
a = argparse.ArgumentParser()
a.add_argument("--host", default="127.0.0.1"); a.add_argument("--port", type=int, default=8188)
a.add_argument("--prompt", required=True); a.add_argument("--w", type=int, default=1024); a.add_argument("--h", type=int, default=1024)
a.add_argument("--steps", type=int, default=8); a.add_argument("--seed", type=int, default=1); a.add_argument("--prefix", default="zimg")
a.add_argument("--dtype", default="default"); a.add_argument("--sampler", default="res_multistep"); a.add_argument("--scheduler", default="simple")
a.add_argument("--shift", type=float, default=3.0); a.add_argument("--batch", type=int, default=1)
a.add_argument("--unet", default="z_image_turbo_bf16.safetensors"); a.add_argument("--clip", default="qwen_3_4b.safetensors")
a.add_argument("--timeout", type=int, default=3600); a.add_argument("--frames", type=int, default=33)
a.add_argument("--negative", default="blurry, low quality, static, subtitles, watermark, distorted, extra limbs")
a.add_argument("--model", default="zimage", choices=["zimage", "klein", "qwen21", "krea2", "wan21", "wan22"])
a.add_argument("--enhance", action="store_true", help="run the template's prompt rewriter first (qwen21, krea2)"); a.add_argument("--thinking", action="store_true")
a.add_argument("--pe", default="qwen3.5_9b_qwen_image_2.1_pe_t2i.int8_convrot.safetensors"); a.add_argument("--sysprompts", default="/data/imagegen/sysprompts.json"); a.add_argument("--vae", default=None); a.add_argument("--cfg", type=float, default=1.0)
o = a.parse_args()
if o.model == "klein":  # FLUX.2 klein 4B distilled defaults, from the official ComfyUI template
    if o.unet == "z_image_turbo_bf16.safetensors": o.unet = "flux-2-klein-4b.safetensors"
    if o.sampler == "res_multistep": o.sampler = "euler"
a2 = {"qwen21": ("qwen_image_2.1_turbo_int8_convrot.safetensors", "qwen3vl_8b_int8_convrot.safetensors", "qwen_image_2.1_vae_bf16.safetensors", "euler"),
      "krea2": ("krea2_turbo_int8_convrot.safetensors", "qwen3vl_4b_fp8_scaled.safetensors", "qwen_image_vae.safetensors", "euler"),
      "wan21": ("wan2.1_t2v_1.3B_fp16.safetensors", "umt5_xxl_fp8_e4m3fn_scaled.safetensors", "wan_2.1_vae.safetensors", "uni_pc"),
      "wan22": ("wan2.2_ti2v_5B_fp16.safetensors", "umt5_xxl_fp8_e4m3fn_scaled.safetensors", "wan2.2_vae.safetensors", "uni_pc")}
if o.model in a2:
    if o.unet == "z_image_turbo_bf16.safetensors": o.unet = a2[o.model][0]
    if o.clip == "qwen_3_4b.safetensors": o.clip = a2[o.model][1]
    o.vae = o.vae or a2[o.model][2]
    if o.sampler == "res_multistep": o.sampler = a2[o.model][3]
o.vae = o.vae or ("flux2-vae.safetensors" if o.model == "klein" else "ae.safetensors")
U = f"http://{o.host}:{o.port}"
wf = {
 "1": {"class_type": "UNETLoader", "inputs": {"unet_name": o.unet, "weight_dtype": o.dtype}},
 "2": {"class_type": "CLIPLoader", "inputs": {"clip_name": o.clip, "type": "lumina2", "device": "default"}},
 "3": {"class_type": "VAELoader", "inputs": {"vae_name": o.vae}},
 "4": {"class_type": "CLIPTextEncode", "inputs": {"clip": ["2", 0], "text": o.prompt}},
 "5": {"class_type": "ConditioningZeroOut", "inputs": {"conditioning": ["4", 0]}},
 "6": {"class_type": "EmptySD3LatentImage", "inputs": {"width": o.w, "height": o.h, "batch_size": o.batch}},
 "7": {"class_type": "ModelSamplingAuraFlow", "inputs": {"model": ["1", 0], "shift": o.shift}},
 "8": {"class_type": "KSampler", "inputs": {"model": ["7", 0], "positive": ["4", 0], "negative": ["5", 0], "latent_image": ["6", 0],
        "seed": o.seed, "steps": o.steps, "cfg": o.cfg, "sampler_name": o.sampler, "scheduler": o.scheduler, "denoise": 1.0}},
 "9": {"class_type": "VAEDecode", "inputs": {"samples": ["8", 0], "vae": ["3", 0]}},
 "10": {"class_type": "SaveImage", "inputs": {"images": ["9", 0], "filename_prefix": o.prefix}},
}
if o.model == "klein":
    wf = {
     "1": {"class_type": "UNETLoader", "inputs": {"unet_name": o.unet, "weight_dtype": o.dtype}},
     "2": {"class_type": "CLIPLoader", "inputs": {"clip_name": o.clip, "type": "flux2", "device": "default"}},
     "3": {"class_type": "VAELoader", "inputs": {"vae_name": o.vae}},
     "4": {"class_type": "CLIPTextEncode", "inputs": {"clip": ["2", 0], "text": o.prompt}},
     "5": {"class_type": "ConditioningZeroOut", "inputs": {"conditioning": ["4", 0]}},
     "6": {"class_type": "EmptyFlux2LatentImage", "inputs": {"width": o.w, "height": o.h, "batch_size": o.batch}},
     "7": {"class_type": "CFGGuider", "inputs": {"model": ["1", 0], "positive": ["4", 0], "negative": ["5", 0], "cfg": o.cfg}},
     "11": {"class_type": "KSamplerSelect", "inputs": {"sampler_name": o.sampler}},
     "12": {"class_type": "Flux2Scheduler", "inputs": {"steps": o.steps, "width": o.w, "height": o.h}},
     "13": {"class_type": "RandomNoise", "inputs": {"noise_seed": o.seed}},
     "8": {"class_type": "SamplerCustomAdvanced", "inputs": {"noise": ["13", 0], "guider": ["7", 0], "sampler": ["11", 0], "sigmas": ["12", 0], "latent_image": ["6", 0]}},
     "9": {"class_type": "VAEDecode", "inputs": {"samples": ["8", 0], "vae": ["3", 0]}},
     "10": {"class_type": "SaveImage", "inputs": {"images": ["9", 0], "filename_prefix": o.prefix}},
    }
    if o.cfg > 1:  # base (non-distilled) klein: the template uses an empty negative prompt instead of a zeroed one
        wf["5"] = {"class_type": "CLIPTextEncode", "inputs": {"clip": ["2", 0], "text": ""}}
if o.model == "qwen21":  # Qwen-Image 2.1, wiring from the official template (prompt rewriting switched off)
    wf = {
     "1": {"class_type": "UNETLoader", "inputs": {"unet_name": o.unet, "weight_dtype": o.dtype}},
     "2": {"class_type": "CLIPLoader", "inputs": {"clip_name": o.clip, "type": "qwen_image", "device": "default"}},
     "3": {"class_type": "VAELoader", "inputs": {"vae_name": o.vae}},
     "4": {"class_type": "TextEncodeQwenImage21", "inputs": {"clip": ["2", 0], "prompt": o.prompt, "negative_prompt": "", "resolution": 1024}},
     "6": {"class_type": "EmptyLatentImage", "inputs": {"width": o.w, "height": o.h, "batch_size": o.batch}},
     "7": {"class_type": "QwenImage21Cache", "inputs": {"model": ["1", 0], "device": "auto", "dtype": "default"}},
     "8": {"class_type": "KSampler", "inputs": {"model": ["7", 0], "positive": ["4", 0], "negative": ["4", 1], "latent_image": ["6", 0],
            "seed": o.seed, "steps": o.steps, "cfg": o.cfg, "sampler_name": o.sampler, "scheduler": o.scheduler, "denoise": 1.0}},
     "9": {"class_type": "VAEDecode", "inputs": {"samples": ["8", 0], "vae": ["3", 0]}},
     "10": {"class_type": "SaveImage", "inputs": {"images": ["9", 0], "filename_prefix": o.prefix}},
    }
    if o.enhance:  # the template's prompt rewriter: a second language model writes a longer prompt first
        wf["40"] = {"class_type": "CLIPLoader", "inputs": {"clip_name": o.pe, "type": "stable_diffusion", "device": "default"}}
        wf["41"] = {"class_type": "TextGenerate", "inputs": {"clip": ["40", 0], "prompt": o.prompt, "system_prompt": json.load(open(o.sysprompts))["qwen21"],
            "max_length": 4096, "sampling_mode": "on", "sampling_mode.temperature": 1.0, "sampling_mode.top_k": 20, "sampling_mode.top_p": 0.95, "sampling_mode.min_p": 0.0,
            "sampling_mode.repetition_penalty": 1.0, "sampling_mode.seed": o.seed, "sampling_mode.presence_penalty": 1.5, "thinking": o.thinking, "use_default_template": True, "mtp": "auto"}}
        wf["42"] = {"class_type": "PreviewAny", "inputs": {"source": ["41", 0]}}
        wf["4"]["inputs"]["prompt"] = ["41", 0]
if o.model == "krea2":  # Krea 2 Turbo, wiring from the official int8 template (style LoRA off, as shipped)
    wf = {
     "1": {"class_type": "UNETLoader", "inputs": {"unet_name": o.unet, "weight_dtype": o.dtype}},
     "2": {"class_type": "CLIPLoader", "inputs": {"clip_name": o.clip, "type": "krea2", "device": "default"}},
     "3": {"class_type": "VAELoader", "inputs": {"vae_name": o.vae}},
     "4": {"class_type": "CLIPTextEncode", "inputs": {"clip": ["2", 0], "text": o.prompt}},
     "5": {"class_type": "ConditioningZeroOut", "inputs": {"conditioning": ["4", 0]}},
     "6": {"class_type": "EmptyLatentImage", "inputs": {"width": o.w, "height": o.h, "batch_size": o.batch}},
     "8": {"class_type": "KSampler", "inputs": {"model": ["1", 0], "positive": ["4", 0], "negative": ["5", 0], "latent_image": ["6", 0],
            "seed": o.seed, "steps": o.steps, "cfg": o.cfg, "sampler_name": o.sampler, "scheduler": o.scheduler, "denoise": 1.0}},
     "9": {"class_type": "VAEDecode", "inputs": {"samples": ["8", 0], "vae": ["3", 0]}},
     "10": {"class_type": "SaveImage", "inputs": {"images": ["9", 0], "filename_prefix": o.prefix}},
    }
    if o.enhance:  # on by default in the template; the rewriter is the text encoder itself, so no extra model
        wf["41"] = {"class_type": "TextGenerate", "inputs": {"clip": ["2", 0], "prompt": json.load(open(o.sysprompts))["krea2"] + o.prompt,
            "max_length": 512, "sampling_mode": "on", "sampling_mode.temperature": 0.7, "sampling_mode.top_k": 64, "sampling_mode.top_p": 0.95, "sampling_mode.min_p": 0.05,
            "sampling_mode.repetition_penalty": 1.05, "sampling_mode.seed": 0, "sampling_mode.presence_penalty": 0.0, "thinking": o.thinking, "use_default_template": True}}
        wf["42"] = {"class_type": "PreviewAny", "inputs": {"source": ["41", 0]}}
        wf["4"]["inputs"]["text"] = ["41", 0]
if o.model in ("wan21", "wan22"):  # Wan 2.1 1.3B / Wan 2.2 5B text-to-video, wiring from the official templates
    wf = {
     "1": {"class_type": "UNETLoader", "inputs": {"unet_name": o.unet, "weight_dtype": o.dtype}},
     "2": {"class_type": "CLIPLoader", "inputs": {"clip_name": o.clip, "type": "wan", "device": "default"}},
     "3": {"class_type": "VAELoader", "inputs": {"vae_name": o.vae}},
     "4": {"class_type": "CLIPTextEncode", "inputs": {"clip": ["2", 0], "text": o.prompt}},
     "5": {"class_type": "CLIPTextEncode", "inputs": {"clip": ["2", 0], "text": o.negative}},
     "6": {"class_type": "EmptyHunyuanLatentVideo", "inputs": {"width": o.w, "height": o.h, "length": o.frames, "batch_size": o.batch}},
     "7": {"class_type": "ModelSamplingSD3", "inputs": {"model": ["1", 0], "shift": o.shift}},
     "8": {"class_type": "KSampler", "inputs": {"model": ["7", 0], "positive": ["4", 0], "negative": ["5", 0], "latent_image": ["6", 0],
            "seed": o.seed, "steps": o.steps, "cfg": o.cfg, "sampler_name": o.sampler, "scheduler": o.scheduler, "denoise": 1.0}},
     "9": {"class_type": "VAEDecode", "inputs": {"samples": ["8", 0], "vae": ["3", 0]}},
     "11": {"class_type": "CreateVideo", "inputs": {"images": ["9", 0], "fps": 24 if o.model == "wan22" else 16}},
     "10": {"class_type": "SaveVideo", "inputs": {"video": ["11", 0], "filename_prefix": o.prefix, "format": "auto", "codec": "auto"}},
    }
    if o.model == "wan22":
        wf["6"] = {"class_type": "Wan22ImageToVideoLatent", "inputs": {"vae": ["3", 0], "width": o.w, "height": o.h, "length": o.frames, "batch_size": o.batch}}
    for j, idx in enumerate(sorted({0, o.frames // 2, o.frames - 1})):  # also save three still frames for a quick look
        wf[str(20 + j)] = {"class_type": "ImageFromBatch", "inputs": {"image": ["9", 0], "batch_index": idx, "length": 1}}
        wf[str(30 + j)] = {"class_type": "SaveImage", "inputs": {"images": [str(20 + j), 0], "filename_prefix": f"{o.prefix}_f{idx:03d}"}}
def call(path, body=None):
    req = urllib.request.Request(U + path, data=json.dumps(body).encode() if body is not None else None, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=60) as r: return json.loads(r.read())
t0 = time.time()
try:
    pid = call("/prompt", {"prompt": wf})["prompt_id"]
except urllib.error.HTTPError as e:
    print(json.dumps({"prefix": o.prefix, "error": e.read().decode()[:1500]})); raise SystemExit(1)
res = {"enhance": o.enhance, "prefix": o.prefix, "w": o.w, "h": o.h, "steps": o.steps, "seed": o.seed, "sampler": o.sampler, "scheduler": o.scheduler, "dtype": o.dtype, "batch": o.batch, "unet": o.unet, "clip": o.clip, "model": o.model, "frames": o.frames if o.model in ("wan21", "wan22") else 1, "cfg": o.cfg}
while time.time() - t0 < o.timeout:
    h = call(f"/history/{pid}")
    if pid in h:
        st = h[pid].get("status", {}); res["status"] = st.get("status_str"); res["wall_s"] = round(time.time() - t0, 2)
        ts = {m[0]: m[1].get("timestamp") for m in st.get("messages", []) if isinstance(m, list) and len(m) == 2 and isinstance(m[1], dict)}
        if "execution_start" in ts and "execution_success" in ts: res["exec_s"] = round((ts["execution_success"] - ts["execution_start"]) / 1e3, 2)
        res["files"] = [i["filename"] for n in h[pid].get("outputs", {}).values() for v in n.values() if isinstance(v, list) for i in v if isinstance(i, dict) and "filename" in i]
        if res["status"] != "success": res["messages"] = json.dumps(st.get("messages"))[:1500]
        break
    time.sleep(0.5)
else:
    res["status"] = "timeout"
print(json.dumps(res)); raise SystemExit(0 if res.get("status") == "success" else 1)
