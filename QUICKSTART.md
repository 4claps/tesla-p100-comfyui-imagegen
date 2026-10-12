# Quick start: your first image on a Tesla P100

This is the shortest route from nothing to a picture. You type a few commands once, then everything else happens in
a web page. Expect about an hour, most of it waiting for downloads.

## What you need
- A Linux computer with a Tesla P100 16 GB in it and the NVIDIA driver working (typing `nvidia-smi` shows the card).
- Docker and the NVIDIA Container Toolkit installed (this lets Docker use the graphics card).
- About 30 GB of free disk space.
- Nothing else using the graphics card while you do this.

## Step 1: get the files
```
git clone https://github.com/4claps/tesla-p100-comfyui-imagegen.git
cd tesla-p100-comfyui-imagegen
```

## Step 2: build the program (15 to 30 minutes, about 14 GB)
```
docker build -t p100-imagegen:latest .
docker build -t p100-imagegen:p100 -f Dockerfile.p100 .
```
The first line builds ComfyUI, the program that makes the pictures. The second adds two small fixes these cards need.

## Step 3: download one model (three files, about 12 GB)
```
mkdir -p models/diffusion_models models/text_encoders models/vae out
B=https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files
curl -L -C - -o models/diffusion_models/z_image_turbo_int8_convrot.safetensors $B/diffusion_models/z_image_turbo_int8_convrot.safetensors
curl -L -C - -o models/text_encoders/qwen_3_4b_fp8_mixed.safetensors $B/text_encoders/qwen_3_4b_fp8_mixed.safetensors
curl -L -C - -o models/vae/ae.safetensors $B/vae/ae.safetensors
```
If a download stops part way, run the same line again and it carries on from where it stopped.

## Step 4: start it
```
docker run -d --name comfy --gpus device=0 -p 8188:8188 \
  -v "$PWD/models":/opt/ComfyUI/models -v "$PWD/out":/opt/ComfyUI/output \
  p100-imagegen:p100 python main.py --listen 0.0.0.0 --port 8188 --fast-disk
```

## Step 5: make a picture
1. Open a web browser and go to `http://localhost:8188` (if the P100 is in another computer, use that computer's
   address in place of `localhost`).
2. Click **Templates** on the left and choose **Z-Image-Turbo Int8: Text to Image**.
3. Replace the example text with a description of the picture you want.
4. Click **Run**.

The first picture takes a few minutes because the model has to load. After that, each one takes about 80 seconds.
Your pictures are saved in the `out` folder.

## When you are done
```
docker stop comfy       # stop it
docker start comfy      # start it again another day
```

## If something goes wrong
- **The page will not open:** wait a minute and try again. `docker logs comfy` shows what the program is doing.
- **"Missing models" appears:** you picked a different template. Each template needs its own files; this guide
  only downloads the ones for *Z-Image-Turbo Int8*. The README lists the others.
- **"could not select device driver" when starting:** the NVIDIA Container Toolkit is not installed or Docker was
  not restarted after installing it.
- **Out of memory:** something else is using the card. `nvidia-smi` shows what.

## Good to know
- The web page has no password. Anyone who can reach that computer on your network can use it while it is running.
- This was tested with ComfyUI 0.39.0. Step 2 always fetches the newest ComfyUI; if a later version changes, the
  fixes in `Dockerfile.p100` may need updating.
- Want it faster? FLUX.2 klein makes a picture in about 25 seconds. The README and `RESULTS.md` explain how.

---

*The concept, hardware and direction for this project are mine. The automation, benchmark runs and write-up were
done with the assistance of Claude, Anthropic's AI model.*
