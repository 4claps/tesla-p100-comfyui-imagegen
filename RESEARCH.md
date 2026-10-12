# Research notes: getting the most out of Tesla P100 (and the Tesla line)

Collected 2026-10-12 from the web. Nothing here is measured by me unless it says so; section 3 of RESULTS.md and
MEASURE-RESULTS.md hold the measurements.

## What makes the P100 different from its siblings
- P100 (GP100, compute capability 6.0) has full-rate 16-bit float and no fast 8-bit integer dot product (`dp4a`).
  The P40 and the GTX 10 series (6.1) are the reverse: fast `dp4a`, 16-bit float at about 1/64 of 32-bit rate. Advice
  written for "Pascal" or "P40" is often wrong for the P100 and the other way round.
  A P40 report measured fp16 diffusion 14x slower than fp32 (63.8 against 4.7 s/step).
- HBM2 memory, 732 GB/s per card. Only one power state (P0): the idle-power tools used on P40s (nvidia-pstate, P8)
  do not apply to P100 or V100.
- Driver branch 580 is the last one for Maxwell/Pascal/Volta; it is a long-term branch supported to mid-2028.
  CUDA 13 cannot compile for these cards, so everything must be built with CUDA 12.x (PyTorch: the cu126 wheels).

## Image generation
- ComfyUI's own code lists "p100" among cards where 32-bit maths is used on Linux ("fp32 is faster"). Measured here:
  true (16-bit is 11% slower end to end; big matrix multiplies gain only ~10%, attention loses ~9%).
- A diffusion model does not split across cards the way llama.cpp splits an LLM; four cards means four images at once
  or one card for the text encoder (ComfyUI-MultiGPU, a third-party extension that patches memory management).
- Step-skipping caches (TeaCache, CacheDiT) claim 1.4-2x on diffusion transformers incl. Z-Image Turbo and FLUX.2
  klein; both are third-party node packs. Unmeasured here.
- Community GGUF builds of Z-Image Turbo go down to 3.6 GB; a GTX 1080 Ti is reported at 6-9 s per 1024 image with Q3
  (unverified, and that card is the opposite fp16/int8 case from the P100).
- stable-diffusion.cpp (ggml) supports Z-Image and FLUX.2 klein on CUDA and can put the text encoder, VAE and model on
  different cards natively. A possible alternative runtime; unmeasured.

## LLM leads found on the way (for the llama.cpp side of this project)
- github.com/gavinbrow/p100-llm-benchmarks: 2x P100, 545 runs, 29 models. Claims: Nemotron-3.5-Lightning-30B-A3B at
  110 tok/s with its MTP head (50 tok/s at 128k context); Qwen3.6-35B-A3B "faster and lower in perplexity than every
  dense 27B setup tested"; keep the KV cache at f16 (q8_0 cost 21-42% at 72k context); F16 weights rather than BF16;
  `-ub 2048` cuts prefill time by about a quarter; Q3_K files ran 15% slower than Q4_0 (no dp4a); peak 123 W per card.
- github.com/laurentiuluca/llama.cpp (and identical copies): a fork of Kmic-68 `p100-optimizations`, 2x P100.
  Claims Qwen3.8-27B plain decode 32.6 t/s, about 54 t/s with MTP, prefill 493 t/s short and 153 t/s at 260k.
- github.com/Joe11221/p100-llama-cpp (parent qr0n/p100-llama-cpp): 11 patches. Claims an fp16 matrix-vector path that
  replaces the quantized one (2.03x on an 8B Q4_K_M, one card), f16 KV +24% on a 75k request, and a warning that
  `GGML_CUDA_P2P` caused a 10.7x prefill regression on dual-socket boxes (we measured it as a gain on this
  single-socket box, so this does not transfer).

## What the night's measurements add (measured here, see RESULTS.md)
- fp16 against fp32 on the P100 in PyTorch 2.14/cu126: whole image 11% slower in fp16; linear layers ~10% faster,
  attention ~9% slower, bf16 slower still. The card's "full-rate fp16" does not show up through cuBLAS/PyTorch.
- No INT8 matrix multiply in cuBLASLt on Pascal: ComfyUI's `int8_convrot` files (Z-Image, Qwen-Image 2.1, Krea 2)
  fail until ComfyUI is told to convert them to float (one-line patch). Then they work at ~5% lower speed and half
  the memory. `nvfp4` and `fp8` files already fall back to float on their own.
- PyTorch 2.14 routes some operations to Triton kernels that need a C compiler at run time; set
  `TORCH_DISABLE_NATIVE_JIT=1` (or add gcc to the image, untested).
- Power: the image workload uses the whole 150 W cap. A higher cap buys 12% on a cool card and the card then heats
  to 79-80 C in three images. Video draws more per clock: at 150 W the SM clock sits at 950-1000 MHz.
- A 15 GB host needs ComfyUI's `--fast-disk`; without it one process holds a full copy of the model in RAM.
- The lightx2v `Self-Forcing-FP8` video file is not readable by ComfyUI (scale values ignored, noise out).

## LLM leads worth a test on this box (not started; sizes from Hugging Face)
- `unsloth/Qwen3.6-35B-A3B-GGUF` (mixture of experts, about 3B active per token): UD-Q4_K_XL 22.4 GB, UD-Q5_K_XL
  26.6 GB, UD-Q6_K_XL 31.8 GB, MXFP4_MOE 21.7 GB; there is also `unsloth/Qwen3.6-35B-A3B-MTP-GGUF`. The two-P100
  benchmark above calls it faster and lower in perplexity than every dense 27B setup it tried. Unknown: whether the
  Kmic-68 fork's tensor split and MTP paths work with it, and how it does on the agent battery.
- Nemotron-3.5-Lightning-30B-A3B (110 tok/s claimed on two P100s with its MTP head; did not load with `-sm tensor`
  in upstream b10970).
- That benchmark's advice to prefer Q4_0/Q8_0/MXFP4/F16 files (cheapest to unpack without dp4a) was measured on
  upstream llama.cpp; the Kmic-68 fork changes that path, so it needs its own check before acting on it.
- Their "keep KV at f16" finding: checked here on four cards at 262k context on 2026-10-12: +2.9% short generation,
  -2.5% prompt speed, +2.9 GB per card. Not worth it on this fork.

## Sources
- https://dev.to/sevan_safarian_555dc84374/on-a-tesla-p40-loading-a-diffusion-model-in-fp16-made-it-14x-slower-than-fp32-3fa7
- https://www.phoronix.com/news/NVIDIA-580-Linux-Driver-Last-HW
- https://developer.nvidia.com/blog/navigating-gpu-architecture-support-a-guide-for-nvidia-cuda-developers/
- https://github.com/ggml-org/llama.cpp/discussions/8084
- https://github.com/gavinbrow/p100-llm-benchmarks
- https://github.com/laurentiuluca/llama.cpp
- https://github.com/Joe11221/p100-llama-cpp
- https://gitee.com/ITG/ComfyUI-MultiGPU
- https://www.sourcepulse.org/projects/26290438 (ComfyUI-CacheDiT)
- https://github.com/leejet/stable-diffusion.cpp
- https://docs.comfy.org/tutorials/flux/flux-2-klein
- https://huggingface.co/unsloth/Qwen3.6-35B-A3B-GGUF
- https://huggingface.co/anonymous1436778242134213535654/Wan2.1-T2V-1.3B-Distill-Comfy
- https://huggingface.co/Comfy-Org/Qwen-Image-2.1
- https://willitrunai.com/blog/video-generation-gpu-guide-2026

---

*The concept, hardware and direction for this project are mine. The automation, benchmark runs and write-up were
done with the assistance of Claude, Anthropic's AI model.*
