#!/bin/bash
# Video bench: Wan 2.1 text-to-video 1.3B on one card. Usage: vbench.sh GPU CAP_WATTS NAME
# At the 150 W cap this workload holds the SM clock at 950-1000 MHz (guard stop on 2026-10-12 04:19), so the cap on
# this one card is raised for the run and restored to 150 W by a trap, then verified.
GPU=$1; CAP=${2:-150}; NAME=${3:-wan21}; R=/data/imagegen/suite_$NAME; mkdir -p $R; rm -f $R/DONE $R/STOP; . /data/imagegen/lib.sh
C=comfy$GPU; PORT=$((8188+GPU))
restore() { sudo -n nvidia-smi -i $GPU -pl 150 >/dev/null; log "power limits now: $(nvidia-smi --query-gpu=power.limit --format=csv,noheader | tr '\n' ' ')"; docker rm -f $C >/dev/null 2>&1; touch $R/DONE; }
trap restore EXIT; guard &
PV1='a fox moving quickly in a beautiful winter scenery nature trees mountains daytime tracking camera'
PV2='A lighthouse keeper in a yellow raincoat walks along wet rocks at dusk holding a glowing brass lantern, waves crash behind him, cinematic, steady camera'
G() { local tag=$1; shift; g $tag $C $PORT $GPU --model wan21 --prefix ${NAME}_$tag --timeout 5400 --shift 8 --w 832 --h 480 "$@"
      f=$(ls -t $W/telemetry-*.csv | head -1); log "   last 120 s card $GPU: $(tail -n 480 $f | awk -F', ' -v g=$GPU '$2==g && $4+0>90 {n++; p+=$6; c+=$7; if($3>t)t=$3; if(m==""||$7+0<m)m=$7+0} END{if(n) printf "mean %.0f W, mean clock %.0f MHz, min clock %d MHz, max %d C", p/n, c/n, m, t}')"; }
SF="--unet wan21_1.3B_self_forcing_fp8.safetensors --sampler lcm --cfg 1 --steps 4"
log "== wan 2.1 1.3B gpu $GPU cap $CAP W"; start_comfy $C $GPU $PORT --fast-disk || exit 1; cooldown || exit 1
sudo -n nvidia-smi -i $GPU -pl $CAP >/dev/null; log "cap card $GPU = $(nvidia-smi -i $GPU --query-gpu=power.limit --format=csv,noheader)"
G warmup --seed 99 --steps 4 --cfg 6 --frames 17 --prompt "$PV1"
G f33_s30 --seed 1 --steps 30 --cfg 6 --frames 33 --prompt "$PV1"
G sf_warm --seed 99 --frames 17 --prompt "$PV1" $SF
G sf_f33 --seed 1 --frames 33 --prompt "$PV1" $SF
G sf_f81 --seed 1 --frames 81 --prompt "$PV1" $SF
G sf_f81_keeper --seed 1 --frames 81 --prompt "$PV2" $SF
G f81_s20 --seed 1 --steps 20 --cfg 6 --frames 81 --prompt "$PV1"
log "VBENCH DONE"
