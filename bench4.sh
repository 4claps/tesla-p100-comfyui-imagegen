#!/bin/bash
# Bench 4: power cap on card 0 only (150, 200, 250 W, interleaved, twice), a new seed for every image so nothing
# is served from ComfyUI's cache. The cap is restored to 150 W by a trap and verified.
R=/data/imagegen/bench4; mkdir -p $R; rm -f $R/DONE $R/STOP; . /data/imagegen/lib.sh
restore() { sudo -n nvidia-smi -i 0 -pl 150 >/dev/null; log "power limits now: $(nvidia-smi --query-gpu=power.limit --format=csv,noheader | tr '\n' ' ')"; docker rm -f comfy0 >/dev/null 2>&1; touch $R/DONE; }
trap restore EXIT
guard &
S=100; G() { local tag=$1; shift; S=$((S+1)); g $tag comfy0 8188 0 --prefix b4_$tag --seed $S --prompt "$P_KEEPER" "$@"; }
log "== bench4"; start_comfy comfy0 0 8188 || exit 1; cooldown || exit 1
G warmup
for round in 1 2; do for pl in 150 200 250; do stopped && break; cooldown || exit 1
    sudo -n nvidia-smi -i 0 -pl $pl >/dev/null; log "cap card 0 = $(nvidia-smi -i 0 --query-gpu=power.limit --format=csv,noheader)"
    G pl${pl}_r${round}_a; G pl${pl}_r${round}_b; G pl${pl}_r${round}_c
    f=$(ls -t $W/telemetry-*.csv | head -1); log "last 150 s on card 0: $(tail -n 600 $f | awk -F', ' '$2==0 && $4+0>90 {n++; p+=$6; c+=$7; if($3>t)t=$3} END{printf "busy samples %d, mean %.0f W, mean clock %.0f MHz, max %d C", n, p/n, c/n, t}')"
done; done
log "BENCH4 DONE"
