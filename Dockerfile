# Image generation on Tesla P100 (Pascal): ComfyUI + PyTorch built for CUDA 12.6 (the last wheel series that
# still lists Pascal). Models and outputs are mounted from the host; nothing else is installed on the host.
FROM python:3.11-slim
RUN apt-get update && apt-get install -y --no-install-recommends git curl ca-certificates libgl1 libglib2.0-0 && rm -rf /var/lib/apt/lists/*
RUN pip install --no-cache-dir torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu126
RUN git clone --depth 1 https://github.com/comfyanonymous/ComfyUI.git /opt/ComfyUI \
 && git -C /opt/ComfyUI log -1 --format='%H %cs' > /opt/ComfyUI/COMMIT \
 && pip install --no-cache-dir -r /opt/ComfyUI/requirements.txt
WORKDIR /opt/ComfyUI
EXPOSE 8188
CMD ["python", "main.py", "--listen", "0.0.0.0", "--port", "8188"]
