"""Phase 0: reference stems for the 60 s test clip.

  python phase0_reference.py htdemucs cpu|mps   PyTorch htdemucs (shifts=0, overlap 0.25)
  python phase0_reference.py umx                Open-Unmix CoreML exactly as the app runs it
  python phase0_reference.py center             center-channel fallback (approximation)

Each mode runs in its own process so the reported peak memory belongs to that method only.
Stems go to $HTDEMUCS_WORK/out/<method>_{vocals,instrumental}.wav.
"""
import sys
import time

import numpy as np

from common import OUT, CLIP, UMX_MODEL, log, peak_rss_mb, read_stereo, write_stereo


def run_htdemucs(device):
    import torch
    from demucs.apply import apply_model
    from demucs.pretrained import get_model

    model = get_model("htdemucs").models[0].eval().to(device)
    mix = torch.from_numpy(read_stereo(CLIP))[None].to(device)
    with torch.no_grad():
        apply_model(model, mix[..., :44_100 * 8], shifts=0, split=True, overlap=0.25, device=device)  # warm-up
        if device == "mps":
            torch.mps.synchronize()
        t0 = time.perf_counter()
        out = apply_model(model, mix, shifts=0, split=True, overlap=0.25, device=device)[0]
        if device == "mps":
            torch.mps.synchronize()
        elapsed = time.perf_counter() - t0
    out = out.cpu().numpy()
    vocals = out[model.sources.index("vocals")]
    others = sum(out[i] for i, s in enumerate(model.sources) if s != "vocals")
    tag = f"htdemucs_torch_{device}"
    write_stereo(OUT / f"{tag}_vocals.wav", vocals)
    write_stereo(OUT / f"{tag}_instrumental.wav", others)
    log(f"{tag}: {elapsed:.2f} s for 60 s, peak RSS {peak_rss_mb():.0f} MB, sources {model.sources}")


def run_umx():
    """Mirror of CoreMLStemSeparationRepository.separate (chunk 256, overlap 32, soft mask)."""
    import coremltools as ct
    import torch

    mix = read_stereo(CLIP)
    model = ct.models.MLModel(str(UMX_MODEL), compute_units=ct.ComputeUnit.ALL)
    t0 = time.perf_counter()
    window = torch.hann_window(4096)
    spec = torch.stft(torch.from_numpy(mix), 4096, 1024, window=window, center=True,
                      pad_mode="reflect", return_complex=True).numpy()  # (2, 2049, frames)
    mag = np.abs(spec)
    frames = mag.shape[-1]
    chunk, overlap = 256, 32
    mask = np.zeros_like(mag)
    weight = np.zeros(frames, dtype=np.float32)
    start = 0
    while start < frames:
        x = np.zeros((1, 2, 2049, chunk), dtype=np.float32)
        n = min(chunk, frames - start)
        x[0, :, :, :n] = mag[:, :, start:start + n]
        est = model.predict({"spectrogram": x})["vocals"][0]
        t = np.arange(n)
        fade_in = np.ones(n) if start == 0 else np.minimum(1, (t + 1) / (overlap + 1))
        fade_out = np.ones(n) if start + chunk >= frames else np.minimum(1, (chunk - t) / (overlap + 1))
        w = np.minimum(fade_in, fade_out).astype(np.float32)
        weight[start:start + n] += w
        m = mag[:, :, start:start + n]
        ratio = np.where(m > 1e-8, np.clip(est[:, :, :n] / np.maximum(m, 1e-8), 0, 1), 0)
        mask[:, :, start:start + n] += w * ratio
        if start + chunk >= frames:
            break
        start += chunk - overlap
    mask /= np.maximum(weight, 1e-8)
    vocals = torch.istft(torch.from_numpy(spec * mask), 4096, 1024, window=window, center=True,
                         length=mix.shape[1]).numpy()
    elapsed = time.perf_counter() - t0
    write_stereo(OUT / "umx_coreml_vocals.wav", vocals)
    write_stereo(OUT / "umx_coreml_instrumental.wav", mix - vocals)
    log(f"umx_coreml: {elapsed:.2f} s for 60 s, peak RSS {peak_rss_mb():.0f} MB")


def run_center():
    mix = read_stereo(CLIP)
    mid = mix.mean(axis=0)
    side = (mix[0] - mix[1]) / 2
    write_stereo(OUT / "center_vocals.wav", np.stack([mid, mid]))
    write_stereo(OUT / "center_instrumental.wav", np.stack([side, side]))
    log("center: written")


if __name__ == "__main__":
    mode = sys.argv[1]
    if mode == "htdemucs":
        run_htdemucs(sys.argv[2] if len(sys.argv) > 2 else "cpu")
    elif mode == "umx":
        run_umx()
    elif mode == "center":
        run_center()
    else:
        raise SystemExit(__doc__)
