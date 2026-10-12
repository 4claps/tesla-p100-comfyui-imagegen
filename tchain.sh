#!/bin/bash
# Template check (2026-10-12): run each shipped ComfyUI template's own settings on card 1 with the fixed prompt set,
# as the files it needs finish downloading. Card 0 is in use by a person and is not touched.
W=/data/imagegen; M=$W/models; export TGPU=1; L=$W/tchain.log
nvidia-smi --query-gpu=timestamp,index,temperature.gpu,utilization.gpu,memory.used,power.draw,clocks.sm --format=csv,noheader -l 1 > $W/telemetry-$(date +%m%d-%H%M).csv & TP=$!
# Fans: full speed for the tests (the guard stops on fan3 under 2000 RPM, and automatic control idles at ~1300),
# automatic control put back on exit.
sudo -n systemctl stop gpu-fan-control.service; sudo -n systemctl start fans-full.service; sleep 20
trap 'kill $TP 2>/dev/null; sudo -n systemctl stop fans-full.service; sudo -n systemctl start gpu-fan-control.service; echo "[$(date +%T)] TCHAIN END" >> $L' EXIT
need() { for f in "$@"; do until [ -e $M/$f ]; do sleep 30; done; done; }
run() { echo "[$(date +%T)] start $1" >> $L; bash $W/suite.sh "$@" > $W/tchain_$1.out 2>&1; echo "[$(date +%T)] end $1 rc=$? $(cat $W/suite_$1/STOP 2>/dev/null)" >> $L; [ ! -e $W/suite_$1/STOP ] || exit 1; }
T="--timeout 3600"
run t_klein_dist 1 "--model klein --steps 4 --cfg 1 $T" --fast-disk
run t_zturbo_int8 1 "--model zimage --unet z_image_turbo_int8_convrot.safetensors --clip qwen_3_4b_fp8_mixed.safetensors --steps 8 $T" --fast-disk
run t_zturbo_bf16 1 "--model zimage --steps 8 $T" --fast-disk
need diffusion_models/flux-2-klein-base-4b.safetensors
run t_klein_base 1 "--model klein --unet flux-2-klein-base-4b.safetensors --steps 20 --cfg 5 $T" --fast-disk
need diffusion_models/qwen_image_2.1_int8_convrot.safetensors
run t_qwen21_base 1 "--model qwen21 --unet qwen_image_2.1_int8_convrot.safetensors --steps 25 --cfg 1 $T" --fast-disk
need text_encoders/qwen3.5_9b_qwen_image_2.1_pe_t2i.int8_convrot.safetensors
NOREP=1 PROMPTS="2 3" run t_qwen21_pe 1 "--model qwen21 --unet qwen_image_2.1_int8_convrot.safetensors --steps 25 --cfg 1 --enhance $T" --fast-disk
need vae/qwen_image_vae.safetensors text_encoders/qwen3vl_4b_fp8_scaled.safetensors diffusion_models/krea2_turbo_int8_convrot.safetensors
run t_krea2_pe 1 "--model krea2 --steps 8 --cfg 1 --scheduler simple --enhance $T" --fast-disk
NOREP=1 run t_krea2_plain 1 "--model krea2 --steps 8 --cfg 1 --scheduler simple $T" --fast-disk
echo "[$(date +%T)] TCHAIN DONE" >> $L
