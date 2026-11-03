"""Phase 0: reference stems for the 60 s test clip.

  python phase0_reference.py htdemucs cpu|mps   PyTorch htdemucs (shifts=0, overlap 0.25)
  python phase0_reference.py center             center-channel fallback (approximation)

(The Open-Unmix baseline in the report came from a `umx` mode that was removed together with
Open-Unmix itself; see git history before 2026-11-03 cleanup.)

Each mode runs in its own process so the reported peak memory belongs to that method only.
Stems go to $HTDEMUCS_WORK/out/<method>_{vocals,instrumental}.wav.
"""
import sys
import time

import numpy as np

from common import OUT, CLIP, log, peak_rss_mb, read_stereo, write_stereo


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
    elif mode == "center":
        run_center()
    else:
        raise SystemExit(__doc__)
