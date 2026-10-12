# Per-operation timing on one card: fp32 against fp16 and bf16, for the operations a diffusion transformer spends
# its time in. Shapes follow Z-Image at 1024x1024: 4096 image tokens, width 3840, 30 heads.
import torch, time, torch.nn.functional as F
d = "cuda"; N, D, H = 4096, 3840, 30
def t(fn, n=10):
    fn(); torch.cuda.synchronize(); s = time.time()
    for _ in range(n): fn()
    torch.cuda.synchronize(); return (time.time() - s) / n * 1000
print(torch.__version__, torch.cuda.get_device_name(0), "cudnn.benchmark", torch.backends.cudnn.benchmark)
print(f"{'op':28s} {'fp32 ms':>9s} {'fp16 ms':>9s} {'bf16 ms':>9s}")
rows = {}
for dt in (torch.float32, torch.float16, torch.bfloat16):
    with torch.no_grad():
        x = torch.randn(1, N, D, device=d, dtype=dt); lin = torch.nn.Linear(D, D, device=d, dtype=dt)
        lin4 = torch.nn.Linear(D, D * 4, device=d, dtype=dt)
        q = torch.randn(1, H, N, D // H, device=d, dtype=dt); ln = torch.nn.LayerNorm(D, device=d, dtype=dt)
        img = torch.randn(1, 128, 512, 512, device=d, dtype=dt); conv = torch.nn.Conv2d(128, 128, 3, padding=1, device=d, dtype=dt)
        gn = torch.nn.GroupNorm(32, 128, device=d, dtype=dt)
        ops = {"linear 3840->3840": lambda: lin(x), "linear 3840->15360": lambda: lin4(x),
               "attention (sdpa) 30 heads": lambda: F.scaled_dot_product_attention(q, q, q),
               "attention manual (bmm)": lambda: torch.softmax(q @ q.transpose(-1, -2) / 11.3, -1) @ q,
               "layernorm": lambda: ln(x), "rms norm (manual)": lambda: x * torch.rsqrt(x.pow(2).mean(-1, keepdim=True) + 1e-6),
               "silu": lambda: F.silu(x), "gelu": lambda: F.gelu(x), "mul+add": lambda: x * 1.01 + x,
               "conv3x3 128ch 512px (vae)": lambda: conv(img), "groupnorm (vae)": lambda: gn(img)}
        for k, f in ops.items():
            try: rows.setdefault(k, []).append(t(f))
            except Exception as e: rows.setdefault(k, []).append(float("nan")); print("ERR", k, dt, str(e)[:80])
        del x, lin, lin4, q, ln, img, conv, gn; torch.cuda.empty_cache()
for k, v in rows.items(): print(f"{k:28s} {v[0]:9.2f} {v[1]:9.2f} {v[2]:9.2f}   fp16/fp32 x{v[0]/v[1]:.2f}")
