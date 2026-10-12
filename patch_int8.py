# Local patch applied inside the container: ComfyUI assumes every NVIDIA card can do INT8 matrix multiplies through
# cuBLASLt. Pascal cards cannot (CUBLAS_STATUS_NOT_SUPPORTED), so report "no" there and let ComfyUI convert those
# weights to float instead.
p = "/opt/ComfyUI/comfy/model_management.py"; s = open(p).read()
k = "def supports_int8_compute(device=None):\n"
if "local patch" not in s:
    s = s.replace(k, k + "    if is_nvidia() and torch.cuda.get_device_properties(device if device is not None else get_torch_device()).major < 7:\n        return False  # local patch: no INT8 GEMM in cuBLASLt on Pascal\n")
    open(p, "w").write(s); print("patched")
else: print("already patched")
