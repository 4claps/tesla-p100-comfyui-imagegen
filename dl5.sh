#!/bin/bash
# Files the shipped ComfyUI templates ask for (FLUX.2 klein t2i, Qwen-Image 2.1 t2i, Krea 2 Turbo int8 t2i).
# Written as .part and renamed when complete so ComfyUI never sees a half file.
M=/data/imagegen/models; L=/data/imagegen/dl5.log
get() { local d=$1 n=$2 u=$3 rc=1 k=0; [ -e $M/$d/$n ] && { echo "[$(date +%T)] have $n" >> $L; return; }
  while [ $rc -ne 0 ] && [ $k -lt 40 ]; do k=$((k+1))
    docker run --rm --name dl5 -u 1000:1000 -v $M:/m p100-imagegen:latest sh -c "mkdir -p /m/$d && curl -sfL --retry 8 -C - -o /m/$d/$n.part $u && mv /m/$d/$n.part /m/$d/$n"; rc=$?
    echo "[$(date +%T)] $n attempt $k rc=$rc" >> $L; [ $rc -ne 0 ] && sleep 15; done; }
C=https://huggingface.co/Comfy-Org
while read d n u; do get $d $n $u; done < /data/imagegen/dl5.list
echo "[$(date +%T)] DL5 DONE" >> $L
