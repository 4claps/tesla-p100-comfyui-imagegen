#!/bin/bash
# Bench 5: quality set on one card (Z-Image Turbo, 150 W). Five prompts x 8/6/4 steps, seed 7. The first image of each
# prompt also pays for swapping the text encoder back in, so its wall time is the "new prompt" cost.
R=/data/imagegen/bench5; mkdir -p $R; rm -f $R/DONE $R/STOP; . /data/imagegen/lib.sh; . /data/imagegen/prompts.sh
trap 'docker rm -f comfy0 >/dev/null 2>&1; touch $R/DONE' EXIT
guard &
log "== bench5"; start_comfy comfy0 0 8188 || exit 1; cooldown || exit 1
g warmup comfy0 8188 0 --prefix b5_warm --seed 99 --prompt "$P_KEEPER"
for i in 0 1 2 3 4; do for n in 8 6 4; do g "${PN[$i]}.s$n" comfy0 8188 0 --prefix b5_${PN[$i]}_s$n --seed 7 --steps $n --prompt "${PT[$i]}"; done; done
log "ram: $(free -m | awk 'NR==2{print "used "$3" MiB, free "$4", cache "$6}')"
log "BENCH5 DONE"
