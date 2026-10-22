# stable-diffusion.cpp on Tesla P100, against ComfyUI

Measured 2026-10-22 on the same machine as `RESULTS.md`: Tesla P100 16 GB cards at 150 W, fans at full speed during runs, 1024x1024,
the same five prompts (seed 7) and repeat prompt (seeds 1 and 2) as `prompts.sh`/`lib.sh`. sd.cpp is master `a77d362`
built for sm_60 with CUDA 12.9 (`sdcpp/Dockerfile`). Each setting ran as one `sd-server`, driven by `sdcpp/sdbench.py`;
times are wall seconds per image measured by the client, one run per setting, after one warm-up image.

## Results

| Model, setting | Cards | Repeat prompt | New prompt | Per step |
|---|---|---:|---:|---:|
| **FLUX.2 klein 4B, 4 steps** | | | | |
| ComfyUI (from `RESULTS.md`) | 1 | 23.2 s | ~24-25 s | 4.2 s |
| sd.cpp, weights as stored (bf16) | 1 | 25.4 s | 27.2-27.5 s | 5.69 s |
| sd.cpp, `--type f16` | 1 | 19.1 s | 20.6 s | 4.03 s |
| sd.cpp, `--type q8_0` | 1 | 19.2 s | 19.7 s | 4.05 s |
| sd.cpp, f16, `--flash-attn off` | 1 | 20.5 s | 22.3 s | 4.40 s |
| sd.cpp, f16, text encoder on a second card | 1 + 1 | 19.1 s | 19.5 s | 4.02 s |
| sd.cpp, f16, tensor parallel (patched) | 2 + 1 | 12.1 s | 12.5 s | 2.26 s |
| sd.cpp, f16, tensor parallel (patched) | 4 | **8.7 s** | **9.1-9.2 s** | 1.42 s |
| **Z-Image Turbo, 8 steps** | | | | |
| ComfyUI, bf16 file (from `RESULTS.md`) | 1 | 72 s | 119 s | 8.8 s |
| ComfyUI, int8 file, patched | 1 | 76-80 s | 78-85 s | 9.1 s |
| sd.cpp, f16 + two projections in f32 (patched) | 1 + 1 | 62.5 s | 62.5-63.2 s | 7.4 s |
| sd.cpp, same, tensor parallel | 2 + 1 | 34.7 s | 35.0-35.5 s | 4.0 s |
| sd.cpp, same, tensor parallel | 4 | **24.9 s** | **25.1-25.4 s** | 2.8 s |

"1 + 1" and "2 + 1": the text encoder runs on a separate card. In the 4-card rows it shares a card with the model.
Per step for sd.cpp Z-Image is the sampling time from the server log divided by 8. The rest of each image is the
VAE decode, about 2.7 s.

Image quality: the f16, q8_0 and tensor-parallel images show the same scene, with the same text spelled the same way, as
the single-card ones and as ComfyUI. Tensor-parallel images are not bit-identical to single-card ones: summing partial
results across cards changes the rounding, giving 24-40 dB PSNR against the one-card image of the same seed. That is
the kind of difference two different GPUs give.

## What did not work

- **Z-Image in plain f16 makes a blank white image.** On Pascal, cuBLAS runs f16 matmuls with f16 output, and the
  attention output and FFN `w2` projections overflow. sd.cpp already forces f32 for those two on ROCm and Vulkan, not
  on CUDA. The patch adds `SD_ZIMAGE_OUT_PREC_F32=1` to force them on. Forcing every matmul to f32
  (`GGML_CUDA_CUBLAS_COMPUTE_TYPE=f32`) also works but costs 80 s per image.
- **The int8 convrot files** (`z_image_turbo_int8_convrot`) run part of the model on the CPU on these cards: the first
  image did not finish within 30 minutes. Use the bf16 file with `--type f16`.
- **sd.cpp's own `--split-mode row`** is accepted but falls back to a layer split: the bundled ggml no longer has the
  CUDA split buffer it needs. The layer split runs the cards one after the other, and with Z-Image it crashed with an
  illegal memory access (Xid 31, a software fault) on the first new prompt.
- **Z-Image on one card, text encoder on the same card**: the model is re-staged for every image (43 s for the first step).
  Put the text encoder (`--backend "all=cuda0,te=cuda1"`) on another card.

## The tensor-parallel patch

The patches in `sdcpp/patches/` add a `tp` backend: `--backend "all=cuda0,diffusion=tp,te=cuda2"` with
`SD_TP_DEVICES=CUDA0,CUDA1` (or four cards). It runs the diffusion model on ggml's meta backend, the same tensor
parallelism llama.cpp uses for `-sm tensor`: the fused qkv and the MLP input are split by output rows, the attention
output and MLP output by input columns, and the cards exchange partial sums over NCCL twice per block. FLUX.2 (double
and single blocks) and Z-Image blocks are covered; other models' tensors stay mirrored, which runs but gains nothing.

Changes:

- `ggml_extend_backend.cpp`: the `tp` backend token and the per-tensor split rules.
- `model_manager.cpp`: weights on the meta backend are allocated per card (otherwise every card reserves the whole model).
- `z_image.hpp`: `SD_ZIMAGE_OUT_PREC_F32`.
- ggml `ggml-backend-meta.cpp`: split rules for the fork's `ROPE_APPLY` op and for a concat along the split axis (FLUX.2
  single blocks), plus an error message naming the op when no split rule fits.

Run flags that matter: `--auto-fit off` (the auto-fit planner does not know `tp`), and with four cards
`NCCL_P2P_LEVEL=SYS` (without it NCCL fails with "unhandled system error" on this PCIe layout). Keep the text encoder
off the card that runs the VAE decode: the 1024x1024 decode needs a 6.6 GB buffer and pushed the encoder out on every
new prompt (17-28 s per image instead of 9).

```
docker build -t sdcpp-p100 sdcpp/
docker run -d --gpus all --network host -e NCCL_P2P_LEVEL=SYS -e SD_TP_DEVICES=CUDA0,CUDA1,CUDA2,CUDA3 \
  -e SD_ZIMAGE_OUT_PREC_F32=1 -v /data/imagegen/models:/m:ro sdcpp-p100 --listen-port 7860 \
  --diffusion-model /m/diffusion_models/z_image_turbo_bf16.safetensors --vae /m/vae/ae.safetensors \
  --llm /m/text_encoders/qwen_3_4b.safetensors --type f16 --auto-fit off --backend "all=cuda0,diffusion=tp,te=cuda1"
python3 sdcpp/sdbench.py --port 7860 --tag test --steps 8
```

## Which to use

- **One picture as fast as possible:** sd.cpp tensor parallel on four cards. klein in about 9 s, Z-Image in about 25 s.
- **Many pictures:** one sd.cpp per card. Not measured as a batch. From the one-card times, four klein servers would
  make about 4 x 3600 / 19.5 = 740 images an hour, against about 390 from one four-card tensor-parallel server.
  Four ComfyUI instances measured about 540-550 an hour (`RESULTS.md`).
- The first image after a server starts takes 1.5-4 minutes: the model files are read from a spinning disk.

Not tested: Qwen-Image 2.1, the step caches (`--cache-mode`), video models, and long runs of the patched build.
