# Image and video generation on Tesla P100 16 GB:

TLDR

1. Image and video generation was set up in containers on the P100s, three image models and two video models were benchmarked and tuned overnight.
2. Best result: FLUX.2 klein makes a good 1024x1024 image in about 25 seconds per card, about 540 an hour on four cards; a 5-second video clip takes about 5 minutes on one card.
3. Surprises: 16-bit maths is slower than 32-bit here; 8-bit model files crash on these cards without a one-line patch; each ComfyUI process ate 12 of the host's 15 GB of RAM until a launch switch fixed it; raising the power cap gives 12% for one image and then the card hits 79-80 C.
4. Measured: every time, temperature and memory figure below. Judged by my eye on one seed per prompt: quality. Extrapolated: the four-card hourly figure (three cards measured for 13 minutes, the fourth assumed equal).
5. Decision: which model should be the default? Recommended: FLUX.2 klein for speed and layout, Z-Image Turbo (8-bit file) when the image must contain correct text.

Open issue to know about: video at the normal 150 W cap tripped the "clock under 1000 MHz" stop rule, so the video numbers were taken on one card at 175 W, where it sits at 79 C. Details in sections 13 and 14.

Update, afternoon of 2026-10-12: the stock ComfyUI templates for Z-Image Turbo (two), FLUX.2 klein, Qwen-Image 2.1
and Krea 2 Turbo now open with no missing-model warning and each runs on one card; section 15 has times and quality.

Sections: 1 first image, 2 precision, 3 steps/size/sampler, 4 power cap, 5 quality set, 6 8-bit Z-Image, 7 FLUX.2 klein, 8 RAM and four cards, 9 klein sweep, 10 Qwen-Image 2.1, 11 side by side, 12 sustained run, 13-14 video, 15 stock templates.

Setup: container `p100-imagegen:latest` (python 3.11, torch 2.14.1+cu126, ComfyUI 0.39.0 commit e8665ca8), started with
`TORCH_DISABLE_NATIVE_JIT=1` (without it PyTorch tries to compile a kernel and fails: no C compiler in the image).
Card power cap 150 W unless stated, fans held at full, 1 Hz nvidia-smi log, guard on 80 C / fan3 2000 RPM / SM clock
under 1000 MHz for 5 s while busy.

## 1. First image (Z-Image Turbo, bf16 file, 1024x1024, 8 steps, res_multistep/simple, shift 3)
Worked first time once the JIT switch was set. Cold start 320 s (154 s reading the 12 GB model from the spinning data
disk at about 80 MB/s), then 68 s of sampling at 8.5 s per step.

## 2. Arithmetic precision, one card, 1024x1024, 8 steps (warm, same prompt)
| Launch flags | What ComfyUI did | s/step | Image time (s) |
|---|---|---:|---:|
| none (default) | bf16 weights, fp32 maths | 8.67, 8.79 | 71.3, 72.1 |
| `--bf16-unet` | same | 8.68, 8.79 | 71.2, 72.1 |
| `--fp16-unet` | fp16 weights, fp32 maths | (warm-up only, 8.45) | — |
| `--force-fp16 --fp16-unet` | fp16 weights, fp16 maths | 9.65, 9.82 | 78.9, 80.4 |

16-bit maths is 11% slower. ComfyUI's own code lists the P100 under "fp32 is faster on Linux"; confirmed.
Per-operation timing on card 1 (ms, fp32 / fp16 / bf16): linear 3840->3840 21.1 / 19.3 / 21.5; linear 3840->15360
88.4 / 78.1 / 90.0; attention (sdpa, 30 heads, 4096 tokens) 49.7 / 54.5 / 70.7; conv3x3 5.8 / 6.6 / 21.2.
The second round of this benchmark was stopped by hand as redundant.

A first attempt at this benchmark was stopped by my own guard on a single 949 MHz sample at the end of a job. The 1 Hz
log shows no busy sample under 1139 MHz. The guard now uses the llama harness rule (5 consecutive seconds).

## 3. Steps, resolution, sampler (one card, 150 W, default precision, seed 1)
| Setting | s/step | Image time (s) |
|---|---:|---:|
| 4 steps | 8.65 | 36.3 |
| 6 steps | 8.73 | 54.1 |
| 8 steps (baseline, 3 runs) | 8.8 | 72.6 |
| 10 steps | 8.81 | 89.8 |
| 768x768 | 4.72 | 38.8 |
| 1344x768 | 8.62 | 81.4 |
| 1280x1280 | 15.47 | 126.7 |
| 1536x1536 | 25.42 | 207.6 |
| euler/simple | 8.85 | 72.7 |
| euler/beta | 8.88 | 72.9 |
| dpmpp_2m/simple | — | 73.0 |
| euler_ancestral/simple | 8.92 | 73.2 |

Sampler choice does not change speed. Card reached 68-71 C at 150 W with fans at full.

## 4. Power cap on card 0 (1024x1024, 8 steps, three images back to back from 48 C, two rounds, new seed each)
| Cap | Image 1 (s) | Image 2 (s) | Image 3 (s) | Mean draw | Mean clock | Peak temp |
|---|---:|---:|---:|---:|---:|---:|
| 150 W | 70.4, 70.5 | 71.8, 71.9 | 72.4, 72.4 | 142 W | 1130 MHz | 70 C |
| 200 W | 62.9, 63.0 | 64.9, 64.9 | 67.6, 68.0 | 181-184 W | 1240 MHz | 79 C |
| 250 W | 61.8, 61.9 | 64.6, 64.7 | 68.7, 68.5 | 186-187 W | 1240 MHz | 80 C |

A higher cap is 12% faster on a cool card but the card heats to 79-80 C within three images and slows itself: by the
third image the gain is 5%. 250 W behaves like 200 W (the card never draws more than ~187 W here). The cooling, not
the cap, is the limit, and 80 C is this project's stop line.
The first power block (bench3) was void: I reused one seed and ComfyUI returned cached images.

## 5. Quality set, Z-Image Turbo bf16, one card, 150 W (five prompts, seed 7, 8 then 6 then 4 steps)
| Prompt | 8 steps, new prompt (s) | 6 steps (s) | 4 steps (s) |
|---|---:|---:|---:|
| portrait | 113.2 | 54.2 | 36.9 |
| landscape | 116.1 | 54.5 | 37.1 |
| poster (text) | 123.8 | 54.8 | 37.3 |
| objects (counts) | 125.4 | 54.6 | 37.1 |
| illustration | 118.6 | 54.7 | 37.2 |

- A new prompt costs 42-53 s on top of the 72 s of sampling: the 7.7 GB text encoder and the 11.7 GB image model do
  not fit on a 16 GB card together, so each new prompt swaps them. Mean new-prompt image: 119 s.
- Looked at by eye (poster at 8 and 4 steps, objects at 8, keeper at 4/6/8): text is spelled correctly at 4 and 8
  steps; 4 steps is slightly smoother in skin and texture but otherwise close. The objects prompt came out with four
  apples (asked three) and three lemons (asked two), and not from above.
- Host RAM after the run: 13.6 GB of 15.5 in use by the one ComfyUI process (12.4 GB of it the model held in RAM).

## 6. Z-Image Turbo 8-bit file (`z_image_turbo_int8_convrot`, 5.9 GB) so both models stay on the card
- Fails on the P100 as shipped: `CUBLAS_STATUS_NOT_SUPPORTED` in `cublasLtMatmul` (no INT8 matrix multiply on
  Pascal; ComfyUI's `supports_int8_compute` does not check the card). All eight images of the first suite errored.
- With a one-line local patch (`patch_int8.py`, baked into image `p100-imagegen:p100` together with the JIT switch)
  ComfyUI converts those weights to float on the fly and it works: 9.1-9.3 s/step (5% slower than the bf16 file).
- Text encoder and image model now fit together (11.8 GB in use): new prompt 78.9, 82.9, 79.4 s; repeat prompt 79.3 s.
  Against the bf16 file: new prompt 119 s -> 80 s (-33%); repeat prompt 72 s -> 79 s (+10%). Host RAM held by the
  process drops from 12.4 to 8.3 GB.

## 7. FLUX.2 klein 4B (distilled, 4 steps, euler, cfg 1, official template settings), one card, 150 W
| Image | Time (s) |
|---|---:|
| repeat prompt (keeper, seeds 1 and 2) | 23.2, 23.3 |
| new prompt: portrait / landscape / poster / objects / illustration | 26.9 / 24.9 / 25.1 / 25.2 / 25.2 |

- About 25 s per new-prompt image against 119 s (Z-Image bf16) or 80 s (Z-Image 8-bit, patched): 3.2-4.7x faster.
  It uses the same text encoder file as Z-Image; 7.4 GB model + 7.7 GB encoder stay on the card together.
- By eye: photorealism is at least as good (portrait is excellent); it got the objects prompt exactly right (three
  apples left of the mug, two lemons right, napkin below, spoon on napkin, seen from above) where Z-Image miscounted;
  its text is worse (poster reads "VISIT THE NORTHRN LINE" with a stray "IN"; the small line is correct).
- Host RAM held: 12.1 GB (blocks running four at once on a 15 GB host; see section 8).

## 8. Host RAM and four cards at once
- By default each ComfyUI process copies the model into host RAM (12.1-12.4 GB). The host has 15 GB, so only one
  process could run. `--fast-disk` keeps weights disk-backed: 1.2 GB held, same image times (klein: 23.2 s repeat,
  24.6-25.3 s new prompt; one 75 s outlier on the first new prompt while it re-read from disk).
- Four cards, one FLUX.2 klein process each (`--fast-disk`), all running the suite at the same time:

| Card | Repeat prompt (s) | New prompt: portrait / landscape / poster / objects / illustration (s) | Peak temp |
|---|---:|---|---:|
| 0 | 23.5, 23.6 | 43.9 / 28.4 / 27.0 / 26.3 / 25.8 | 67 C |
| 1 | 23.5, 23.6 | 43.8 / 28.3 / 26.6 / 26.2 / 25.6 | 63 C |
| 2 | 23.1, 23.3 | 43.8 / 28.2 / 26.9 / 25.7 / 25.1 | 66 C |
| 3 | 23.6, 23.7 | 43.5 / 28.5 / 26.2 / 26.2 / 25.7 | 68 C |

  No slowdown from running four at once (single card alone: 23.2 s and 24.9-26.9 s). Steady state is about 26 s per
  image per card, so four images every 26 s: roughly 9 images a minute, 550 an hour. The first new prompt after a
  load is slow (44 s) on every card. Host RAM in use with all four loaded: under 8 GB.

## 9. FLUX.2 klein sweep (card 0, `--fast-disk`, 150 W; cards 1 and 2 busy with other tests at the same time)
| Setting | s/step | Image time (s) |
|---|---:|---:|
| 4 steps, 1024x1024 | 4.2 | 24.0-24.1 |
| 6 steps | 4.5 | 34.0 |
| 8 steps | 4.8 | 45.5-45.9 |
| 768x768, 4 steps | 3.0 | 17.6 |
| 1344x768 | 3.9 | 24.1 |
| 1280x1280 | 7.1 | 41.1 |
| 1536x1536 | 11.5 | 65.6 |
| 2048x2048 | 31.3 | 152.8 |
| batch of 4 at 1024x1024 | 14.2 | 195.5 (48.9 per image) |

- Batching is slower per image than one at a time (48.9 s against 24 s); use one image per request.
- Text: at 4 steps the poster title was wrong on seed 7 ("NORTHRN", stray "IN") and right on seed 12; at 8 steps
  seed 7 came out right. For text, use 8 steps (45 s) or Z-Image.
- Small text encoder (`qwen_3_4b_fp4_flux2`, 3.6 GB): new-prompt images 24.5-24.8 s (against 24.9-26.9), 11.7 GB in
  use instead of 12.5-13.4 GB. Objects prompt and poster not yet compared by eye.
- 8-bit Z-Image with `--fast-disk` (card 2): repeat prompt 75.7-75.8 s, new prompt 77.7-84.6 s (first one 117 s),
  1.15 GB of host RAM held. So the low-RAM setting works for Z-Image too.
- Loading three different models at once from the spinning disk took 8-9 minutes each (against 4 alone).

## 10. Qwen-Image 2.1 Turbo (8-bit file via the patch, 8 steps, euler/simple, cfg 1), one card, `--fast-disk`
| Image | Time (s) |
|---|---:|
| repeat prompt (keeper, seeds 1 and 2) | 91.6, 93.1 |
| new prompt: portrait / landscape / poster / objects / illustration | 160.1 / 160.4 / 142.1 / 96.3 / 96.9 |

- 9.2-9.4 s/step. The 8.9 GB text encoder and 7.2 GB image model together are just over what the card holds, so new
  prompts cost anywhere from 4 to 68 s extra.
- By eye: the poster is the best of the three models (both lines of text correct, most finished design). Objects:
  two apples instead of three, everything else placed correctly, but not seen from above.
- The slowest of the three: 4-6x slower than FLUX.2 klein per new-prompt image.
- Prompt rewriting by the bundled 9B language model (part of the official workflow) was left off and is untested.

## 11. Side by side (one P100, 1024x1024, 150 W, new prompt each time)
| Model | Steps | Time per image | Text | Counting/layout | Fits with its text encoder |
|---|---:|---:|---|---|---|
| FLUX.2 klein 4B | 4 | ~25 s | hit and miss at 4 steps, right at 8 (45 s) | right | yes |
| Z-Image Turbo, 8-bit file (patched) | 8 | ~80 s | right | wrong counts | yes |
| Z-Image Turbo, bf16 file | 8 | ~119 s (72 s repeat prompt) | right | wrong counts | no (swaps) |
| Qwen-Image 2.1 Turbo, 8-bit (patched) | 8 | 96-160 s | right, best design | one apple short | barely (swaps) |

Based on one seed per prompt and my own eye; not a scored evaluation.

## 12. Sustained run: FLUX.2 klein, 30 new-prompt images back to back on each of cards 1, 2 and 3 at once
| Card | 30 images in | Per image | Slowest image | Peak temp | Mean busy clock |
|---|---:|---:|---:|---:|---:|
| 1 | 802 s | 26.7 s | 45.9 s | 68 C | 1149 MHz |
| 2 | 791 s | 26.4 s | 40.5 s | 72 C | 1165 MHz |
| 3 | 811 s | 27.0 s | 46.0 s | 73 C | 1148 MHz |

All 90 images succeeded. About 135 images an hour per card at 150 W with no thermal trouble; with the fourth card
(busy loading the video model during this run) that is about 540 an hour, the fourth card's share being extrapolated.

## 13. Video: Wan 2.1 text-to-video 1.3B (832x480, official template: 30 steps, cfg 6, uni_pc/simple, shift 8)
- Loads and renders in the container: 7.7 GB text encoder (fp8 file) + 2.7 GB model + VAE, 11.9 GB in use while
  sampling. A 17-frame, 4-step test clip took 76 s of sampling (19 s/step) and shows a recognisable fox in snow.
- **Guard stop at 04:19:23 EDT** on the first real clip (33 frames, 30 steps), card 0, 150 W cap: SM clock at 961 MHz
  for 5 consecutive seconds while busy. Telemetry for 04:14-04:20: 17 of 141 busy samples at 950-999 MHz, mean 138 W,
  peak 66 C, no throttle flag other than the normal power-cap one. This workload simply runs the card slower per watt
  than image generation did (image runs held 1130-1190 MHz at the same cap). The 1000 MHz rule was not changed; the
  rerun raises the cap on that one card to 175 W (restored to 150 W by a trap).
- Rerun at 175 W on card 0:

| Clip | Steps / cfg | Frames | Time | Card |
|---|---|---:|---:|---|
| official settings | 30 / 6 | 33 (2.1 s at 16 fps) | 939 s (15.7 min), 30.6 s/step | 163 W, clock 1037-1127 MHz, 79 C |
| 4-step, cfg 1 (timing only, see below) | 4 / 1 | 33 | 79.5 s | 78 C |
| 4-step, cfg 1 (timing only) | 4 / 1 | 81 (5.1 s) | 300.9 s | 79 C |

- The official 30-step clip looks right (a middle frame shows a realistic fox walking through a snowy forest).
- The 4-step runs used `lightx2v/Self-Forcing-FP8`; ComfyUI ignored that file's per-layer scale values ("unet
  unexpected: ...weight_scale") and the output was pure noise. Their times are valid as the cost of 4 passes at cfg 1,
  nothing more. File deleted; a plain-format 4-step conversion is tested in section 14.
- At 175 W the card sat at 78-79 C for the whole run, one degree under the stop line.

## 14. Video, continued (one card each, cap raised to 175 W for the run and restored)
| Model and setting | Size, frames | Time | Card |
|---|---|---:|---|
| Wan 2.1 1.3B, 4-step distilled file (4 steps, cfg 1, euler/simple, shift 7) | 832x480, 33 (2.1 s) | 77.5 s | 164 W, 69 C |
| same | 832x480, 81 (5.1 s) | 297.7 s and 317.5 s (two prompts) | 164 W, clock 1037-1146 MHz, 79 C |
| Wan 2.2 TI2V 5B, official 20 steps, cfg 5, uni_pc | 832x480, 49 (2.0 s at 24 fps) | 522.6 s (8.7 min) | 168 W, 76 C |
| same | 1280x704, 49 (2.0 s) | 1447.4 s (24.1 min) | 171 W, clock 1025-1199 MHz, 75 C |

- 4-step file: `wan2.1-t2v-1.3b-4step-distill.safetensors`, a plain-format conversion of
  `lightx2v/Wan2.1-T2V-1.3B-Distill-Models` published by an anonymous account (data-only safetensors). Middle frames
  look coherent: a fox in snow (some smearing on a front leg), and a bearded man in a yellow raincoat with a lantern by
  the sea at dusk (it added an umbrella and a lighthouse nobody asked for). I looked at stills, not motion.
- A fifth 4-step run labelled "8 steps" actually ran 4 (argument order mistake); ignore it.
- One launch was lost to a cool-down timeout: my cool-down waited on all four cards while another card was busy. It
  now checks only its own card.
- Not tested: video on four cards at once (would mean 175 W on all four, about 80 C each), image-to-video, audio.

## 15. Stock ComfyUI templates, as shipped (2026-10-12, 10:48-15:36 EDT, card 1, `--fast-disk`, 150 W)
Aim: the templates in ComfyUI's own template browser should open and run with no edits. Seven more files were
downloaded (44 GB) so that five text-to-image templates have every file they name. Each template's own settings were
then run through `gen.py` (same nodes and values as the template; the browser's graph-to-API conversion itself was not
exercised) with the fixed five-prompt set, seed 7, 1024x1024. All ran on one card. Driver: `tchain.sh`.

| Template | Settings it ships with | Same prompt, new seed | New prompt | Peak card memory | Host RAM (process) |
|---|---|---:|---:|---:|---:|
| `image_flux2_klein_text_to_image`, distilled half | 4 steps, cfg 1, euler | 23.6 s | 42-69 s | 13.0 GB | 1.2 GB |
| same template, base half (active by default) | 20 steps, cfg 5, euler | 225 s | 277-292 s | 11.6 GB | 1.2 GB |
| `image_z_image_turbo` | 8 steps, bf16 file | 71-72 s | 197-235 s | 13.2 GB | 1.1 GB |
| `image_z_image_turbo_int8` | 8 steps, 8-bit file, fp8 text encoder | 76-77 s | 78 s | 11.9 GB | 1.2 GB |
| `image_qwen_image_2_1_t2i` | full model, 25 steps, cfg 1, rewriter off | 278 s | 282-330 s | 13.3 GB | 1.8 GB |
| same, prompt rewriter on | adds a 9B language model pass | - | 1013-1515 s | 12.9 GB | 2.9 GB |
| `image_krea2_turbo_t2i_int8` | 8 steps, cfg 1, rewriter on (default) | 159-160 s | 304-380 s | 12.2 GB | 7.0 GB |
| same, rewriter off | | - | 183-235 s | 12.2 GB | 7.1 GB |

Quality against the overnight runs (same prompts and seed):
- FLUX.2 klein distilled and Z-Image Turbo bf16: all five images are byte-for-byte identical to the overnight ones.
- Z-Image Turbo int8: same pictures, mean pixel difference 3-6 of 255 on the three I had a matching overnight image
  for. The template uses the `fp8_mixed` text encoder; overnight I used the full one.
- FLUX.2 klein base: text correct, portrait sharp, two apples where three were asked for (the distilled half got
  three). Not visibly better than the distilled half at ten times the time. One seed, judged by eye.
- Qwen-Image 2.1 full model: text correct, apples/lemons counted and placed correctly; the poster's train has a
  carriage detached from the engine. With the rewriter on: richer poster but garbled title lettering and four apples.
  The Turbo file from section 10 (not what the template points at) is three times faster and looked no worse.
- Krea 2 Turbo: text correct with and without the rewriter, three apples and two lemons in the right places, natural
  portrait. The best all-round set of the day by eye, at 3-5 minutes an image.

Things to know:
- New-prompt times for klein distilled and Z-Image Turbo bf16 are slower than overnight (25 s and 119 s then). The
  sampling speed is unchanged (same s/it); the extra time is in reloading the text encoder. Likely cause, not measured:
  the data disk was busy with downloads and a second ComfyUI session, and the page cache was shared with them.
- Krea 2 Turbo's 14.1 GB model does not fully fit beside its working memory: ComfyUI keeps about 12.2 GB on the card
  and about 7 GB in host RAM. One instance is fine on this 15 GB host; four at once would not fit.
- The Qwen rewriter (`refine_prompt`) and its 9.5 GB file exist only so the template opens cleanly; leave it off.
- Guard: no stops. Three single low-clock samples (873-898 MHz) at job ends, never five in a row. Peak 66 C.
- The first launch stopped at once on "fan3 1283 RPM": automatic fan control idles below the guard's 2000 RPM. The
  chain now switches the case fans to full for the run and back to automatic at the end.
- Not downloaded: FLUX.2 klein 9B (gated on Hugging Face), FLUX.2 dev, HiDream, Chroma, the edit and ControlNet
  templates. Templates outside this list still show "missing models".

---

*The concept, hardware and direction for this project are mine. The automation, benchmark runs and write-up were
done with the assistance of Claude, Anthropic's AI model.*
