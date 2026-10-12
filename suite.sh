#!/bin/bash
# Standard suite for one model setting on one card: cool-down, discarded warm-up, two repeat-prompt images (pure
# sampling time), then the five-prompt quality set (each a new prompt, so it includes the text-encoder cost).
# NOREP=1 skips the two repeat-prompt images; PROMPTS="2 3" runs only those prompts; TGPU=n watches only that card.
# Usage: suite.sh NAME GPU "gen.py args" [comfy flags...]     (port = 8188 + GPU, container = comfy<GPU>)
NAME=$1; GPU=$2; GA=$3; shift 3
R=/data/imagegen/suite_$NAME; mkdir -p $R; rm -f $R/DONE $R/STOP; . /data/imagegen/lib.sh; . /data/imagegen/prompts.sh
C=comfy$GPU; PORT=$((8188+GPU))
trap '[ "$KEEP" = 1 ] || docker rm -f $C >/dev/null 2>&1; touch $R/DONE' EXIT
guard &
log "== suite $NAME gpu $GPU: gen [$GA] comfy [$*]"; start_comfy $C $GPU $PORT "$@" || exit 1
[ "$NOCOOL" = 1 ] || cooldown || exit 1
g warmup $C $PORT $GPU --prefix ${NAME}_warm --seed 99 --prompt "$P_KEEPER" $GA
docker logs $C 2>&1 | grep -E "model weight dtype|text encoder model load|loaded completely|loaded partially|Staged" | cut -c14-170 | tail -6 | tee -a $R/driver.log
[ "$NOREP" = 1 ] || for s in 1 2; do g keeper.seed$s $C $PORT $GPU --prefix ${NAME}_keeper_s$s --seed $s --prompt "$P_KEEPER" $GA; done
for i in ${PROMPTS:-0 1 2 3 4}; do g ${PN[$i]} $C $PORT $GPU --prefix ${NAME}_${PN[$i]} --seed 7 --prompt "${PT[$i]}" $GA; done
p=$(docker inspect -f '{{.State.Pid}}' $C); log "ram: $(grep -E 'RssAnon|RssFile' /proc/$p/status | tr -s '\t \n' ' ') | host $(free -m | awk 'NR==2{print "used "$3" free "$4" cache "$6}')"
f=$(ls -t $W/telemetry-*.csv | head -1); log "peak VRAM on card $GPU this log: $(awk -F', ' -v g=$GPU '$2==g {m=$5+0; if(m>x)x=m} END{print x}' $f) MiB (whole telemetry file)"
log "SUITE $NAME DONE"
