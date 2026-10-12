#!/bin/bash
# Second batch of model downloads, inside the container, into /data/imagegen/models. Two streams in parallel.
W=/data/imagegen; HF=https://huggingface.co
log() { echo "[$(date +%T)] $*" >> $W/dl2.log; }
dl() { [ -s "$W/models/$2" ] && { log "have $2"; return; }; log "download $2"; local rc=1 n=0
       while [ $rc -ne 0 ] && [ $n -lt 30 ]; do n=$((n+1))
         docker run --rm -u 1000:1000 -v $W/models:/m p100-imagegen:latest sh -c "curl -sL --retry 8 -C - -o /m/$2.part $1 && mv /m/$2.part /m/$2"; rc=$?
         [ $rc -ne 0 ] && { log "retry $n for $2 after rc=$rc"; sleep 10; }; done
       log "done $2 rc=$rc $(du -h $W/models/$2 2>/dev/null | cut -f1)"; }
K=$HF/Comfy-Org/vae-text-encorder-for-flux-klein-4b/resolve/main/split_files; Z=$HF/Comfy-Org/z_image_turbo/resolve/main/split_files; Q=$HF/Comfy-Org/Qwen-Image-2.1/resolve/main
( dl $K/vae/flux2-vae.safetensors vae/flux2-vae.safetensors
  dl $K/diffusion_models/flux-2-klein-4b.safetensors diffusion_models/flux-2-klein-4b.safetensors
  dl $Q/vae/qwen_image_2.1_vae_bf16.safetensors vae/qwen_image_2.1_vae_bf16.safetensors
  dl $Q/text_encoders/qwen3vl_8b_int8_convrot.safetensors text_encoders/qwen3vl_8b_int8_convrot.safetensors
  dl $Z/text_encoders/qwen_3_4b_fp8_mixed.safetensors text_encoders/qwen_3_4b_fp8_mixed.safetensors; log "STREAM A DONE" ) &
( dl $Z/diffusion_models/z_image_turbo_int8_convrot.safetensors diffusion_models/z_image_turbo_int8_convrot.safetensors
  dl $K/text_encoders/qwen_3_4b_fp4_flux2.safetensors text_encoders/qwen_3_4b_fp4_flux2.safetensors
  dl $Q/diffusion_models/qwen_image_2.1_turbo_int8_convrot.safetensors diffusion_models/qwen_image_2.1_turbo_int8_convrot.safetensors; log "STREAM B DONE" ) &
wait; log "DL2 DONE; data disk free: $(df -h /data | awk 'NR==2{print $4}')"
