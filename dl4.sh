#!/bin/bash
# Fourth batch (video): Wan 2.2 text+image-to-video 5B and its VAE. Waits for the third batch.
W=/data/imagegen; HF=https://huggingface.co; mkdir -p $W/models/{diffusion_models,text_encoders,vae}
log() { echo "[$(date +%T)] $*" >> $W/dl4.log; }
dl() { [ -s "$W/models/$2" ] && { log "have $2"; return; }; log "download $2"
       docker run --rm -u 1000:1000 -v $W/models:/m p100-imagegen:latest sh -c "curl -sL --retry 8 -C - -o /m/$2.part $1 && mv /m/$2.part /m/$2"; log "done $2 rc=$? $(du -h $W/models/$2 2>/dev/null | cut -f1)"; }
until grep -q "DL3 DONE" $W/dl3.log 2>/dev/null; do sleep 30; done
V=$HF/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files
dl $V/vae/wan2.2_vae.safetensors vae/wan2.2_vae.safetensors
dl $V/diffusion_models/wan2.2_ti2v_5B_fp16.safetensors diffusion_models/wan2.2_ti2v_5B_fp16.safetensors
log "DL4 DONE; data disk free: $(df -h /data | awk 'NR==2{print $4}')"
