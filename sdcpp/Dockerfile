# stable-diffusion.cpp for Tesla P100 (sm_60) with the tensor-parallel patches in patches/ (see SDCPP.md).
# Build:  docker build -t sdcpp-p100 sdcpp/
# The GPU host here has an AVX-only CPU (no AVX2, FMA or F16C). ggml turns those on by default when
# GGML_NATIVE is off, and sd-server then dies with SIGILL (exit 132). Drop the -DGGML_...=OFF flags on a newer CPU.
FROM nvidia/cuda:12.9.1-devel-ubuntu22.04
RUN apt-get update && apt-get install -y --no-install-recommends build-essential cmake git ca-certificates && rm -rf /var/lib/apt/lists/*
RUN git clone https://github.com/leejet/stable-diffusion.cpp /sd.cpp && cd /sd.cpp \
 && git checkout a77d3623180b2bc1886f3dd04c0aa04156a987ef && git submodule update --init --recursive
COPY patches/ /patches/
RUN cd /sd.cpp && git apply /patches/sdcpp-tp-meta.diff && cd ggml && git apply /patches/ggml-meta-rope-apply-concat.diff
RUN cd /sd.cpp && cmake . -B build -DSD_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=60 -DCMAKE_BUILD_TYPE=Release \
      -DGGML_NATIVE=OFF -DGGML_AVX=ON -DGGML_AVX2=OFF -DGGML_FMA=OFF -DGGML_F16C=OFF -DGGML_BMI2=OFF -DGGML_AVX512=OFF \
      -DSD_SERVER_BUILD_FRONTEND=OFF \
 && cmake --build build --config Release -j4 --target sd-server sd-cli
ENTRYPOINT ["/sd.cpp/build/bin/sd-server"]
