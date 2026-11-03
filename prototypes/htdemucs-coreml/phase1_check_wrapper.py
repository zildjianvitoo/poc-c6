"""Phase 1: the split pipeline (STFT outside + HTDemucsCore + iSTFT outside) must reproduce
the original htdemucs, both on one window and chunked over the whole 60 s clip."""
import numpy as np
import torch

from common import CLIP, OUT, SEGMENT_SAMPLES, log, read_stereo
from core import HTDemucsCore, combine, load_htdemucs, separate_chunked, spectrogram_input


def rel(a, b):
    return float(np.abs(a - b).mean() / (np.abs(b).mean() + 1e-12))


if __name__ == "__main__":
    model = load_htdemucs()
    core = HTDemucsCore(model).eval()
    mix = read_stereo(CLIP)

    window = torch.from_numpy(mix[:, :SEGMENT_SAMPLES])[None]
    with torch.no_grad():
        original = model(window)[0].numpy()
        spec = spectrogram_input(model, window)
        spec_out, wave_out = core(window, spec)
        split = combine(model, spec_out, wave_out).numpy()
    log(f"shapes: spec {tuple(spec.shape)} → spec_out {tuple(spec_out.shape)}, wave_out {tuple(wave_out.shape)}")
    log(f"one window, split vs original: rel diff {rel(split, original):.2e}, max abs {np.abs(split - original).max():.2e}")

    def run_core(m, s):
        with torch.no_grad():
            return core(m, s)

    stems = separate_chunked(model, mix, run_core)
    vocals = stems[model.sources.index("vocals")]
    ref = read_stereo(OUT / "htdemucs_torch_cpu_vocals.wav")
    log(f"60 s chunked, split vs apply_model vocals: rel diff {rel(vocals, ref):.2e}")
