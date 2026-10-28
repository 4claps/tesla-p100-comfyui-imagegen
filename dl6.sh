#!/bin/bash
# Audio experiments (2026-10-16): HunyuanVideo-Foley (video-to-audio) and LTX-2.5 distilled GGUF (video + audio in one pass).
# Same pattern as dl5.sh: written as .part and renamed when complete. Public, ungated repos only; safetensors/GGUF files only.
M=/data/imagegen/models; L=/data/imagegen/dl6.log
get() { local d=$1 n=$2 u=$3 rc=1 k=0; [ -e $M/$d/$n ] && { echo "[$(date +%T)] have $n" >> $L; return; }
  while [ $rc -ne 0 ] && [ $k -lt 40 ]; do k=$((k+1))
    docker run --rm --name dl6 -u 1000:1000 -v $M:/m p100-imagegen:latest sh -c "mkdir -p /m/$d && curl -sfL --retry 8 -C - -o /m/$d/$n.part $u && mv /m/$d/$n.part /m/$d/$n"; rc=$?
    echo "[$(date +%T)] $n attempt $k rc=$rc" >> $L; [ $rc -ne 0 ] && sleep 15; done; }
while read d n u; do get $d $n $u; done < /data/imagegen/dl6.list
echo "[$(date +%T)] DL6 DONE" >> $L
