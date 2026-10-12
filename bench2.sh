#!/bin/bash
# Bench 2: one launch setting on card 0: cool-down, discarded warm-up, then two timed images (seeds 1 and 2).
# Usage: bench2.sh NAME [comfy flags...]
R=/data/imagegen/bench2; mkdir -p $R; rm -f $R/DONE $R/STOP; . /data/imagegen/lib.sh
v=$1; shift; guard &
log "== $v: flags [$*]"; start_comfy comfy0 0 8188 "$@" && cooldown && {
g "$v.warmup" comfy0 8188 0 --prefix b2_${v}_warm --seed 99 --prompt "$P_KEEPER"
docker logs comfy0 2>&1 | grep -E "model weight dtype|text encoder model load|VAE load" | cut -c14-160 | tee -a $R/driver.log
for s in 1 2; do g "$v.seed$s" comfy0 8188 0 --prefix b2_${v}_s$s --seed $s --prompt "$P_KEEPER"; done; }
[ "$KEEP" = 1 ] || docker rm -f comfy0 >/dev/null; log "BENCH2 $v DONE"; touch $R/DONE
