#!/bin/bash
# Shared helpers for the image-generation benchmarks on the GPU host. Everything GPU-side runs in the
# p100-imagegen container; this script only starts containers, calls gen.py and watches temperatures and fans.
W=/data/imagegen; IMG=${IMG:-p100-imagegen:p100}
P_KEEPER='A weathered lighthouse keeper in a yellow raincoat holding a brass lantern, standing on wet rocks at dusk, crashing waves behind him, a hand-painted wooden sign beside him reads "HOUSTON LIGHT", cinematic photograph, shallow depth of field, detailed skin and fabric texture'
log() { echo "[$(date +%T)] $*" | tee -a $R/driver.log; }
stopped() { [ -e $R/STOP ]; }
temps() { nvidia-smi ${TGPU:+-i $TGPU} --query-gpu=temperature.gpu --format=csv,noheader | sort -n | tail -1; }
# Guard, same rule as the llama harness watchdog: over 80 C, fan3 under 2000 RPM, or a busy card (>50%) with its
# SM clock under 1000 MHz for 5 consecutive seconds -> stop all comfy containers. With TGPU set, only that card is
# watched and only its container (comfy$TGPU) is stopped, so someone else's session on another card is left alone.
guard() { local low=0; while [ ! -e $R/DONE ] && [ ! -e $R/STOP ]; do
    t=$(temps); f=$(sensors 2>/dev/null | awk '/^fan3:/{print $2}')
    c=$(nvidia-smi ${TGPU:+-i $TGPU} --query-gpu=index,utilization.gpu,clocks.sm --format=csv,noheader,nounits | awk -F', ' '$2>50 && $3<1000{print "GPU"$1":"$3"MHz"}' | head -1)
    [ -n "$c" ] && { low=$((low+1)); echo "[$(date +%T)] low clock sample $low: $c" >> $R/guard.log; } || low=0
    why=""; [ "${t:-0}" -gt 80 ] && why="temp $t C"; [ "${f:-9999}" -lt 2000 ] && why="fan3 $f RPM"; [ $low -ge 5 ] && why="SM clock under 1000 MHz while busy for 5 s ($c)"
    if [ -n "$why" ]; then echo "$why" > $R/STOP; log "GUARD STOP: $why"; docker ps -q --filter name=comfy$TGPU | xargs -r docker stop -t 2 >/dev/null; fi
    sleep 1; done; }
cooldown() { local n=0; while [ "$(temps)" -gt 48 ]; do sleep 5; n=$((n+5)); [ $n -gt 900 ] && { echo "cooldown timeout" > $R/STOP; log "cooldown timeout at $(temps) C"; return 1; }; done; log "cool: max $(temps) C after ${n}s"; }
# start_comfy NAME GPU PORT [comfy flags...]
start_comfy() { local name=$1 gpu=$2 port=$3; shift 3; docker rm -f $name >/dev/null 2>&1
    docker run -d --name $name --gpus device=$gpu -e TORCH_DISABLE_NATIVE_JIT=1 $EXTRA_DOCKER -p 127.0.0.1:$port:8188 \
        -v $W/models:/opt/ComfyUI/models -v $W/out:/opt/ComfyUI/output $IMG python main.py --listen 0.0.0.0 --port 8188 "$@" >/dev/null
    for i in $(seq 1 60); do curl -s -m 2 -o /dev/null localhost:$port/system_stats && return 0; sleep 2; done; log "comfy $name did not come up"; return 1; }
# g TAG NAME PORT GPU [gen.py args...] : one image; appends a JSON line with tag, last s/it line and VRAM in use.
g() { local tag=$1 name=$2 port=$3 gpu=$4; shift 4; stopped && return 1
    local out; out=$(python3 $W/gen.py --port $port --timeout 600 "$@" 2>&1 | tail -1 | cut -c1-600)
    local it; it=$(docker logs --tail 400 $name 2>&1 | tr '\r' '\n' | grep -E 'it/s\]|s/it\]' | tail -1 | grep -o -E '[0-9]+/[0-9]+ \[[^]]*\]')
    local mem; mem=$(nvidia-smi -i $gpu --query-gpu=memory.used,temperature.gpu --format=csv,noheader)
    local f; f=$(echo "$out" | grep -o -E '"files": \["[^"]*' | cut -d'"' -f4); local sz=0; [ -n "$f" ] && sz=$(stat -c %s $W/out/$f 2>/dev/null)
    echo "{\"tag\": \"$tag\", \"it\": \"$it\", \"gpu\": \"$mem\", \"png_bytes\": ${sz:-0}, \"r\": $out}" >> $R/results.jsonl
    log "$tag | $it | $mem | png ${sz:-0} | $(echo "$out" | grep -o -E '"status": "[a-z]*", "wall_s": [0-9.]*(, "exec_s": [0-9.]*)?')"; }
