"""Phase 3: separate the whole 60 s clip with a converted model and measure it.

  python phase3_measure.py <variant> <compute units>   e.g. mixed CPU_AND_GPU

Reports model load time, model-only and total time for 60 s, peak memory, and the vocal stem's
SNR against PyTorch htdemucs. Stems go to $HTDEMUCS_WORK/out/htdemucs_<variant>_<units>_*.wav
for leakage.py. Run each combination in its own process so peak memory is per run.
"""
import sys
import time

import coremltools as ct
import numpy as np
import torch

from common import CLIP, OUT, SEGMENT_SAMPLES, WORK, log, peak_rss_mb, read_stereo, write_stereo
from core import load_htdemucs, separate_chunked, spectrogram_input


def snr_db(estimate, reference):
    return float(10 * np.log10(np.sum(reference ** 2) / np.sum((estimate - reference) ** 2)))


if __name__ == "__main__":
    variant, units = sys.argv[1], sys.argv[2]
    model = load_htdemucs()  # only for STFT/iSTFT helpers and source names
    mix = read_stereo(CLIP)
    base = peak_rss_mb()

    t0 = time.perf_counter()
    ml = ct.models.MLModel(str(WORK / f"HTDemucs_{variant}.mlpackage"),
                           compute_units=getattr(ct.ComputeUnit, units))
    load = time.perf_counter() - t0

    model_time = [0.0]

    def run_core(mix_t, spec_t):
        t = time.perf_counter()
        out = ml.predict({"mix": mix_t.numpy(), "spec": spec_t.numpy()})
        model_time[0] += time.perf_counter() - t
        return out["spec_out"], out["wave_out"]

    warm_up = torch.from_numpy(mix[:, :SEGMENT_SAMPLES])[None]
    run_core(warm_up, spectrogram_input(model, warm_up))
    model_time[0] = 0.0
    t0 = time.perf_counter()
    stems = separate_chunked(model, mix, run_core)
    total = time.perf_counter() - t0

    vocals = stems[model.sources.index("vocals")]
    instrumental = sum(stems[i] for i, s in enumerate(model.sources) if s != "vocals")
    tag = f"htdemucs_{variant}_{units}"
    write_stereo(OUT / f"{tag}_vocals.wav", vocals)
    write_stereo(OUT / f"{tag}_instrumental.wav", instrumental)
    ref_vocals = read_stereo(OUT / "htdemucs_torch_cpu_vocals.wav")
    ref_inst = read_stereo(OUT / "htdemucs_torch_cpu_instrumental.wav")
    log(f"{tag}: load {load:.1f} s | 60 s: model {model_time[0]:.2f} s, total {total:.2f} s | "
        f"peak RSS {peak_rss_mb():.0f} MB (before model {base:.0f} MB) | "
        f"NaN {int(np.isnan(stems).sum())} | SNR vs PyTorch: vocals {snr_db(vocals, ref_vocals):.1f} dB, "
        f"instrumental {snr_db(instrumental, ref_inst):.1f} dB")
