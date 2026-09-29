"""空庭 · SE 合成 v2 —— 冰块落杯
修正 v1 的两处物理错误：玻璃衰减过快、缺低频与噪底。
"""
import numpy as np, os
import soundfile as sf
from scipy import signal as sgn

SR = 48000
OUT = r"E:\hollow-court\audio"
os.makedirs(OUT, exist_ok=True)

# ── 玻璃杯的圆环模态（比例约 1 : 1.7 : 2.3 : 3.0 : 3.7）
#    v1 的衰减率（17~48）太狠，0.35s 就断尽；真玻璃该响 1s 以上。
GLASS = [(1174, 5.5), (1961, 3.8), (2733, 6.2), (3512, 9.0), (4301, 13.0)]
# ── 杯体与台面的低频「闷响」，v1 完全没有
BODY = [(163, 11.0), (248, 15.0)]


def modal_stack(modes, dur, vel, pitch=1.0, seed=0):
    n = int(dur * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for f, d in modes:
        ph = np.random.default_rng(seed + int(f)).uniform(0, 6.283)
        out += np.exp(-d * t) * np.sin(2 * np.pi * f * pitch * t + ph)
    return out / (np.max(np.abs(out)) + 1e-9) * vel


def click(dur, vel, lp=11000, hp=400, seed=1):
    """碰撞瞬态：极短噪声 → 带通"""
    n = int(dur * SR)
    x = np.random.default_rng(seed).normal(0, 1, n) * np.exp(-320 * np.arange(n) / SR)
    b, a = sgn.butter(2, [hp / (SR / 2), lp / (SR / 2)], "band")
    y = sgn.lfilter(b, a, x)
    return y / (np.max(np.abs(y)) + 1e-9) * vel


def noise_floor(dur, level, seed=5):
    """极轻的摩擦噪底，避免「太干净」"""
    n = int(dur * SR)
    x = np.random.default_rng(seed).normal(0, 1, n)
    b, a = sgn.butter(2, 6000 / (SR / 2), "low")
    x = sgn.lfilter(b, a, x)
    env = np.exp(-9.0 * np.arange(n) / SR)
    return x * env / (np.max(np.abs(x * env)) + 1e-9) * level


def ice_drop(pitch=1.0, seed=1):
    dur = 2.8
    out = np.zeros(int(dur * SR))

    # ① 触底：玻璃响 + 脆击 + 低频闷响
    r1 = modal_stack(GLASS, dur, 1.00, pitch, seed)
    out[:len(r1)] += r1
    b1 = modal_stack(BODY, dur, 0.42, pitch, seed + 31)
    out[:len(b1)] += b1
    c1 = click(0.014, 0.46, seed=seed)
    out[:len(c1)] += c1

    # ② 75ms 后弹起碰壁：更轻、音高略高
    off = int(0.075 * SR)
    r2 = modal_stack(GLASS, dur - 0.075, 0.30, pitch * 1.07, seed + 9)
    out[off:off + len(r2)] += r2
    c2 = click(0.011, 0.18, seed=seed + 3)
    out[off:off + len(c2)] += c2

    # ③ 152ms 后第二次轻碰
    off2 = int(0.152 * SR)
    r3 = modal_stack(GLASS, dur - 0.152, 0.12, pitch * 1.12, seed + 17)
    out[off2:off2 + len(r3)] += r3
    c3 = click(0.009, 0.08, seed=seed + 11)
    out[off2:off2 + len(c3)] += c3

    # ④ 噪底
    out += noise_floor(dur, 0.010, seed + 41)

    # 轻微软削顶，避免刺耳
    out = np.tanh(out * 1.15) / 1.15
    return out


sig = ice_drop()
sig = sig / (np.max(np.abs(sig)) + 1e-9) * 0.85
wav = os.path.join(OUT, "se-ice-drop-v2.wav")
sf.write(wav, sig, SR)
print(f"wrote {wav}  ({os.path.getsize(wav):,} bytes)")

# ── 频谱：两张图，一张看瞬态，一张看余响 ──
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

fig, ax = plt.subplots(3, 1, figsize=(13, 10), dpi=105,
                       gridspec_kw={"height_ratios": [1, 1.35, 1.35]})

ax[0].plot(np.arange(len(sig)) / SR, sig, lw=0.55, color="#C1440E")
ax[0].set_xlim(0, len(sig) / SR)
ax[0].set_ylabel("amplitude")
ax[0].set_title("se-ice-drop v2  —  waveform, transient view, decay view")
ax[0].grid(alpha=0.15)

# 瞬态视角
f1, t1, S1 = sgn.spectrogram(sig, SR, nperseg=256, noverlap=192)
d1 = 10 * np.log10(S1 + 1e-12)
p1 = ax[1].pcolormesh(t1, f1, d1, shading="gouraud", cmap="magma",
                      vmin=d1.max() - 80, vmax=d1.max())
ax[1].set_yscale("log"); ax[1].set_ylim(80, 20000)
ax[1].set_ylabel("Hz"); ax[1].set_title("transient view (nperseg=256)", fontsize=9)
fig.colorbar(p1, ax=ax[1], label="dB")

# 余响视角
f2, t2, S2 = sgn.spectrogram(sig, SR, nperseg=4096, noverlap=3584)
d2 = 10 * np.log10(S2 + 1e-12)
p2 = ax[2].pcolormesh(t2, f2, d2, shading="gouraud", cmap="magma",
                      vmin=d2.max() - 80, vmax=d2.max())
ax[2].set_yscale("log"); ax[2].set_ylim(80, 20000)
ax[2].set_ylabel("Hz"); ax[2].set_xlabel("seconds")
ax[2].set_title("decay view (nperseg=4096)", fontsize=9)
fig.colorbar(p2, ax=ax[2], label="dB")

plt.tight_layout()
png = os.path.join(OUT, "se-ice-drop-v2-spectrum.png")
plt.savefig(png)
print(f"wrote {png}")

# 余响时长：能量跌到峰值 -40dB 的时刻
env = np.abs(sgn.hilbert(sig))
env_db = 20 * np.log10(env / env.max() + 1e-12)
below = np.where(env_db < -40)[0]
rt = below[0] / SR if len(below) else len(sig) / SR
print(f"peak     : {float(np.max(np.abs(sig))):.4f}")
print(f"duration : {len(sig)/SR:.3f} s")
print(f"rms dBFS : {20*np.log10(np.sqrt(np.mean(sig**2))):.2f}")
print(f"-40dB decay time : {rt:.3f} s   (v1 约 0.35s，真玻璃应 >1s)")
