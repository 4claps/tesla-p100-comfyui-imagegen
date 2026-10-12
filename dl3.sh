#!/bin/bash
# Third batch (video): Wan 2.1 text-to-video 1.3B. Waits for the second batch so the slow link is not split further.
W=/data/imagegen; HF=https://huggingface.co; mkdir -p $W/models/{diffusion_models,text_encoders,vae}
log() { echo "[$(date +%T)] $*" >> $W/dl3.log; }
dl() { [ -s "$W/models/$2" ] && { log "have $2"; return; }; log "download $2"
       docker run --rm -u 1000:1000 -v $W/models:/m p100-imagegen:latest sh -c "curl -sL --retry 8 -C - -o /m/$2.part $1 && mv /m/$2.part /m/$2"; log "done $2 rc=$? $(du -h $W/models/$2 2>/dev/null | cut -f1)"; }
until grep -q "DL2 DONE" $W/dl2.log 2>/dev/null; do sleep 30; done
V=$HF/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files
dl $V/vae/wan_2.1_vae.safetensors vae/wan_2.1_vae.safetensors
dl $V/diffusion_models/wan2.1_t2v_1.3B_fp16.safetensors diffusion_models/wan2.1_t2v_1.3B_fp16.safetensors
dl $V/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors
log "DL3 DONE; data disk free: $(df -h /data | awk 'NR==2{print $4}')"
