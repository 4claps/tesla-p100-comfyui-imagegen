#!/bin/bash
# FLUX.2 klein 4B sweep on one card: steps, resolution, batch. Usage: ksweep.sh GPU
GPU=$1; NAME=ksweep; R=/data/imagegen/suite_$NAME; mkdir -p $R; rm -f $R/DONE $R/STOP; . /data/imagegen/lib.sh; . /data/imagegen/prompts.sh
C=comfy$GPU; PORT=$((8188+GPU)); trap 'docker rm -f $C >/dev/null 2>&1; touch $R/DONE' EXIT; guard &
G() { local tag=$1; shift; g $tag $C $PORT $GPU --model klein --prefix ks_$tag "$@"; }
log "== klein sweep gpu $GPU"; start_comfy $C $GPU $PORT --fast-disk || exit 1; cooldown || exit 1
G warmup --seed 99 --steps 4 --prompt "$P_KEEPER"
for n in 4 6 8; do G poster_s$n --seed 7 --steps $n --prompt "${PT[2]}"; done
for n in 6 8; do G keeper_s$n --seed 1 --steps $n --prompt "$P_KEEPER"; done
for s in 11 12 13; do G poster_seed$s --seed $s --steps 4 --prompt "${PT[2]}"; done
G r768 --seed 1 --steps 4 --w 768 --h 768 --prompt "$P_KEEPER"
G r1344x768 --seed 1 --steps 4 --w 1344 --h 768 --prompt "$P_KEEPER"
G r1280 --seed 1 --steps 4 --w 1280 --h 1280 --prompt "$P_KEEPER"
G r1536 --seed 1 --steps 4 --w 1536 --h 1536 --prompt "$P_KEEPER"
G r2048 --seed 1 --steps 4 --w 2048 --h 2048 --prompt "$P_KEEPER"
G batch4 --seed 5 --steps 4 --batch 4 --prompt "$P_KEEPER"
log "SWEEP DONE"
