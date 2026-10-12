#!/bin/bash
# Bench 1: which arithmetic precision is fastest for Z-Image Turbo on one P100, and does it change the picture.
# Three launch settings, two rounds, interleaved. Per start: cool-down, one discarded warm-up image, then timed images.
R=/data/imagegen/bench1; mkdir -p $R; rm -f $R/DONE $R/STOP; . /data/imagegen/lib.sh
guard &
run_variant() { local v=$1 round=$2; shift 2; stopped && return
    log "== $v round $round: flags [$*]"; start_comfy comfy0 0 8188 "$@" || return
    cooldown || return
    g "$v.r$round.warmup" comfy0 8188 0 --prefix b1_${v}_warm --seed 99 --prompt "$P_KEEPER"
    docker logs comfy0 2>&1 | grep -E "model weight dtype|text encoder model load" | cut -c1-160 | tee -a $R/driver.log
    for s in $SEEDS; do g "$v.r$round.seed$s" comfy0 8188 0 --prefix b1_${v}_s$s --seed $s --prompt "$P_KEEPER"; done
    docker rm -f comfy0 >/dev/null; }
for round in 1 2; do
    [ $round = 1 ] && SEEDS="1 2" || SEEDS="1 3"
    run_variant fp32cast $round
    run_variant bf16 $round --bf16-unet
    run_variant fp16 $round --fp16-unet
done
log "BENCH1 DONE"; touch $R/DONE
