#!/bin/bash
# Video bench 2, one card with the cap raised to CAP (restored to 150 W by a trap):
#   MODE=distill : Wan 2.1 1.3B 4-step distilled file (4 steps, cfg 1, euler/simple, shift 7, per its example workflow)
#   MODE=wan22   : Wan 2.2 TI2V 5B, official settings (20 steps, cfg 5, uni_pc/simple, shift 8) at reduced size/length
# Usage: vbench2.sh GPU CAP MODE
GPU=$1; CAP=$2; MODE=$3; NAME=v2_$MODE; R=/data/imagegen/suite_$NAME; mkdir -p $R; rm -f $R/DONE $R/STOP; . /data/imagegen/lib.sh
C=comfy$GPU; PORT=$((8188+GPU))
restore() { sudo -n nvidia-smi -i $GPU -pl 150 >/dev/null; log "power limits now: $(nvidia-smi --query-gpu=power.limit --format=csv,noheader | tr '\n' ' ')"; docker rm -f $C >/dev/null 2>&1; touch $R/DONE; }
trap restore EXIT; guard &
PV1='a fox moving quickly in a beautiful winter scenery nature trees mountains daytime tracking camera'
PV2='A lighthouse keeper in a yellow raincoat walks along wet rocks at dusk holding a glowing brass lantern, waves crash behind him, cinematic, steady camera'
G() { local tag=$1; shift; g $tag $C $PORT $GPU --prefix ${NAME}_$tag --timeout 7200 "$@"
      f=$(ls -t $W/telemetry-*.csv | head -1); log "   last 120 s card $GPU: $(tail -n 480 $f | awk -F', ' -v g=$GPU '$2==g && $4+0>90 {n++; p+=$6; c+=$7; if($3>t)t=$3; if(m==""||$7+0<m)m=$7+0} END{if(n) printf "mean %.0f W, mean clock %.0f MHz, min clock %d MHz, max %d C", p/n, c/n, m, t}')"; }
log "== $NAME gpu $GPU cap $CAP W"; start_comfy $C $GPU $PORT --fast-disk || exit 1; TGPU=$GPU cooldown || exit 1
sudo -n nvidia-smi -i $GPU -pl $CAP >/dev/null; log "cap card $GPU = $(nvidia-smi -i $GPU --query-gpu=power.limit --format=csv,noheader)"
if [ $MODE = distill ]; then
    D="--model wan21 --unet wan2.1-t2v-1.3b-4step-distill.safetensors --sampler euler --cfg 1 --steps 4 --shift 7 --w 832 --h 480"
    G warm --seed 99 --frames 17 --prompt "$PV1" $D
    G f33 --seed 1 --frames 33 --prompt "$PV1" $D
    G f81 --seed 1 --frames 81 --prompt "$PV1" $D
    G f81_keeper --seed 1 --frames 81 --prompt "$PV2" $D
    G f81_s8 --seed 1 --frames 81 --steps 8 --prompt "$PV1" $D
else
    V="--model wan22 --cfg 5 --shift 8"
    G warm --seed 99 --steps 2 --frames 17 --w 832 --h 480 --prompt "$PV1" $V
    G 480p_f49_s20 --seed 1 --steps 20 --frames 49 --w 832 --h 480 --prompt "$PV1" $V
    G 720p_f49_s20 --seed 1 --steps 20 --frames 49 --w 1280 --h 704 --prompt "$PV1" $V
fi
log "VBENCH2 DONE"
