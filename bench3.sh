#!/bin/bash
# Bench 3: one card, default precision, one model load. Steps, resolution, sampler, then the power cap.
# The power cap on card 0 is raised for the last block only and restored to 150 W by a trap, then verified.
R=/data/imagegen/bench3; mkdir -p $R; rm -f $R/DONE $R/STOP; . /data/imagegen/lib.sh
restore() { sudo -n nvidia-smi -i 0 -pl 150 >/dev/null; log "power limits now: $(nvidia-smi --query-gpu=power.limit --format=csv,noheader | tr '\n' ' ')"; docker rm -f comfy0 >/dev/null 2>&1; touch $R/DONE; }
trap restore EXIT
guard &
G() { local tag=$1; shift; g $tag comfy0 8188 0 --prefix b3_$tag --seed 1 --prompt "$P_KEEPER" "$@"; }
log "== bench3"; start_comfy comfy0 0 8188 || exit 1; cooldown || exit 1
G warmup
G base_a
for n in 4 6 10; do G steps$n --steps $n; done
G base_b
G r768 --w 768 --h 768; G r1280 --w 1280 --h 1280; G r1344x768 --w 1344 --h 768; G r1536 --w 1536 --h 1536
G base_c
G euler_simple --sampler euler --scheduler simple; G euler_beta --sampler euler --scheduler beta; G dpmpp2m_simple --sampler dpmpp_2m --scheduler simple; G eulera_simple --sampler euler_ancestral --scheduler simple
cooldown || exit 1
for pl in 200 150 250 150; do stopped && break
    sudo -n nvidia-smi -i 0 -pl $pl >/dev/null; log "cap card 0 = $(nvidia-smi -i 0 --query-gpu=power.limit --format=csv,noheader)"
    G pl${pl}_1; G pl${pl}_2; log "after pl$pl: $(nvidia-smi -i 0 --query-gpu=temperature.gpu,power.draw,clocks.sm --format=csv,noheader)"; done
log "BENCH3 DONE"
