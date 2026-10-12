#!/bin/bash
# Image-generation setup on the GPU host, containers only. Builds the image p100-imagegen:latest and downloads the
# Z-Image Turbo files into /data/imagegen/models from inside that image. CPU and network only: no GPU use.
# Nothing is installed on the host itself.
set -u
W=/data/imagegen; mkdir -p $W/models/{diffusion_models,text_encoders,vae,loras} $W/out $W/in; cd $W
log() { echo "[$(date +%T)] $*" | tee -a $W/setup.log; }
log "build image"; docker build -t p100-imagegen:latest $W/build >> setup.log 2>&1; log "build rc=$? size=$(docker images --format '{{.Size}}' p100-imagegen:latest)"
log "versions: $(docker run --rm p100-imagegen:latest sh -c 'cat COMMIT; pip list 2>/dev/null | grep -i -E "^(torch|torchvision|numpy|transformers|safetensors) " | tr "\n" " "')"
B=https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files
dl() { [ -s "$W/models/$2" ] && { log "have $2"; return; }; log "download $2"
       docker run --rm -u 1000:1000 -v $W/models:/m p100-imagegen:latest sh -c "curl -sL --retry 5 -C - -o /m/$2.part $1 && mv /m/$2.part /m/$2"; log "done $2 rc=$? $(du -h $W/models/$2 2>/dev/null | cut -f1)"; }
dl $B/vae/ae.safetensors vae/ae.safetensors
dl $B/text_encoders/qwen_3_4b.safetensors text_encoders/qwen_3_4b.safetensors
dl $B/diffusion_models/z_image_turbo_bf16.safetensors diffusion_models/z_image_turbo_bf16.safetensors
log "SETUP DONE; root disk free: $(df -h / | awk 'NR==2{print $4}')"
