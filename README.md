# Image and video generation on Tesla P100 16 GB (containers only)

New here and just want a picture? Start with `QUICKSTART.md`.

Everything GPU-side runs in a container built from these files. Models and outputs live on the GPU host under
`/data/imagegen/{models,out}` and are mounted in. Results are in `RESULTS.md`, web research in `RESEARCH.md`.

## Files
| File | What it is |
|---|---|
| `Dockerfile` | Base image: python 3.11, PyTorch 2.14 for CUDA 12.6 (the last series that supports Pascal), ComfyUI |
| `Dockerfile.p100`, `patch_int8.py` | Small image on top with the two P100 fixes (JIT switch, INT8 fallback) -> `p100-imagegen:p100` |
| `compose.yml` | Four ComfyUI instances, one per card, ports 8188-8191 (not auto-started) |
| `gen.py` | Command-line client: queues one job on a ComfyUI instance and waits (Z-Image, FLUX.2 klein, Qwen-Image 2.1, Krea 2, Wan video) |
| `setup.sh`, `dl2.sh` ... `dl5.sh`, `dl5.list` | Image build and model downloads (run inside the container) |
| `lib.sh`, `prompts.sh` | Benchmark helpers: container start, cool-down, temperature/fan/clock guard, the fixed prompt set |
| `suite.sh`, `ksweep.sh`, `sustained.sh`, `bench*.sh`, `vbench*.sh`, `tchain.sh` | The benchmark scripts behind each section of `RESULTS.md` |
| `mkindex.py` | Builds one browse page for everything in the output folder |
| `samples/` | A few of the generated pictures and clips (see below) |
| `opbench.py` | Per-operation fp32/fp16/bf16 timing |

## Quick use
```
docker compose -f compose.yml up -d comfy0
python3 gen.py --port 8188 --model klein --steps 4 --prompt "..." --prefix myimage      # ~25 s
python3 gen.py --port 8188 --model zimage --unet z_image_turbo_int8_convrot.safetensors --prompt "..."   # ~80 s, best text
```
The ComfyUI web page is on the same port. A model fills most of a card, so stop anything else that is using the cards (an LLM server, for example) first.

## Things that are specific to the P100
- Run with `TORCH_DISABLE_NATIVE_JIT=1` (set in the image).
- Leave precision at ComfyUI's default (fp32 maths). Forcing fp16 is slower.
- `int8_convrot` model files need the patch in `patch_int8.py`.
- Start ComfyUI with `--fast-disk` or one process takes 12 GB of the host's 15 GB of RAM.
- Model files sit on a spinning disk: a cold start takes 4-9 minutes.

## Stock ComfyUI templates that work with no edits
With the files fetched by `dl2.sh` to `dl5.sh` in place, these templates from ComfyUI's template browser open without a
"missing models" warning and run on one 16 GB card: Z-Image Turbo, Z-Image Turbo int8, FLUX.2 klein text to image,
Qwen-Image 2.1 text to image, Krea 2 Turbo int8 text to image, Wan 2.1 text to video, Wan 2.2 5B video. Times and
quality notes are in section 15 of `RESULTS.md`.

## Samples
`samples/images` holds the same five prompts (in `prompts.sh`, seed 7, 1024x1024) for six model settings:
`t_klein_dist` (FLUX.2 klein distilled, 4 steps), `t_klein_base` (20 steps), `t_zturbo_int8` (Z-Image Turbo 8-bit),
`qwen21_turbo` (Qwen-Image 2.1 Turbo), `t_qwen21_base` (Qwen-Image 2.1 full, 25 steps), `t_krea2_plain` (Krea 2 Turbo).
`samples/video` holds two 5-second Wan 2.1 clips made with a 4-step distilled file and one Wan 2.2 5B clip at 1280x704.
The files are straight out of ComfyUI, so each carries its prompt and settings in its metadata.

## License
The MIT license in this repository covers the scripts, notes and sample outputs here. ComfyUI and the model files are
downloaded at build or setup time, are not redistributed here, and keep their own licenses.

---

*The concept, hardware and direction for this project are mine. The automation, benchmark runs and write-up were
done with the assistance of Claude, Anthropic's AI model.*
