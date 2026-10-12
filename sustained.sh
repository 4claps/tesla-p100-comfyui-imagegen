#!/bin/bash
# Sustained run on one card: N new-prompt images back to back (klein, 4 steps). Usage: sustained.sh GPU N
GPU=$1; N=$2; NAME=sus_$GPU; R=/data/imagegen/suite_$NAME; mkdir -p $R; rm -f $R/DONE $R/STOP; . /data/imagegen/lib.sh; . /data/imagegen/prompts.sh
C=comfy$GPU; PORT=$((8188+GPU)); trap 'docker rm -f $C >/dev/null 2>&1; touch $R/DONE' EXIT; guard &
log "== sustained klein gpu $GPU n $N"; start_comfy $C $GPU $PORT --fast-disk || exit 1; cooldown || exit 1
g warmup $C $PORT $GPU --model klein --steps 4 --prefix sus${GPU}_warm --seed 99 --prompt "$P_KEEPER"
g warmup2 $C $PORT $GPU --model klein --steps 4 --prefix sus${GPU}_warm2 --seed 98 --prompt "${PT[4]}"
t0=$(date +%s); log "timed block start"
for i in $(seq 1 $N); do g img$i $C $PORT $GPU --model klein --steps 4 --prefix sus${GPU}_$i --seed $((1000+i)) --prompt "${PT[$((i%5))]}, variation $i" || break; done
t1=$(date +%s); log "timed block: $N images in $((t1-t0)) s = $(python3 -c "print(round(($t1-$t0)/$N,2))") s/image; card now $(nvidia-smi -i $GPU --query-gpu=temperature.gpu,power.draw,clocks.sm --format=csv,noheader)"
log "SUSTAINED DONE"
