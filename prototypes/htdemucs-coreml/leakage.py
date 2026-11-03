"""Melody leakage per method: share of voiced vocal-melody frames whose instrumental stem still
carries the same note (±50 cents, CREPE tiny, confidence ≥ 0.5).

  python leakage.py <method> [<method> ...]     e.g. center htdemucs_torch_cpu htdemucs_int8tr_CPU_AND_GPU

The melody comes from the htdemucs PyTorch vocal stem (the best estimate available) and, as a
cross-check, from each method's own vocal stem.
"""
import sys

from common import OUT, crepe_track, log, melody_leakage, read_stereo

REFERENCE = "htdemucs_torch_cpu"

if __name__ == "__main__":
    cache = {}

    def track(name):
        if name not in cache:
            cache[name] = crepe_track(read_stereo(OUT / f"{name}.wav"))
        return cache[name]

    reference = track(f"{REFERENCE}_vocals")
    log(f"melody frames (htdemucs vocals): {int((reference == reference).sum())}")
    for method in sys.argv[1:]:
        instrumental = track(f"{method}_instrumental")
        own = track(f"{method}_vocals")
        log(f"{method:28s} leakage vs htdemucs melody {melody_leakage(reference, instrumental):6.1%}"
            f"   vs own melody {melody_leakage(own, instrumental):6.1%}")
