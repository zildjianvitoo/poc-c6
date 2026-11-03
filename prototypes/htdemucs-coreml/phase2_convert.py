"""Phase 2: trace HTDemucsCore and convert it to a CoreML ML Program.

  python phase2_convert.py fp16     all ops in float16
  python phase2_convert.py mixed    float16, but normalisation (GroupNorm/LayerNorm chains),
                                    softmax and attention stay float32
  python phase2_convert.py fp32
  python phase2_convert.py int8     "mixed" with weights linearly quantized to int8 (per channel)

Writes $HTDEMUCS_WORK/HTDemucs_<variant>.mlpackage and checks it on one window against PyTorch.
"""
import sys
import time

import coremltools as ct
import numpy as np
import torch

from common import CLIP, SEGMENT_SAMPLES, WORK, log, read_stereo
from core import HTDemucsCore, load_htdemucs, spectrogram_input

# Ops kept in float32 for the "mixed" variant. GroupNorm is lowered to
# reduce_mean/sub/square/sqrt/real_div, and `square` of large activations overflows float16.
FP32_OPS = {"reduce_mean", "sub", "square", "sqrt", "real_div", "layer_norm", "softmax",
            "scaled_dot_product_attention"}


def precision(variant):
    if variant == "fp16":
        return ct.precision.FLOAT16
    if variant == "fp32":
        return ct.precision.FLOAT32
    return ct.transform.FP16ComputePrecision(op_selector=lambda op: op.op_type not in FP32_OPS)


def rel(a, b):
    return float(np.abs(a - b).mean() / (np.abs(b).mean() + 1e-12))


if __name__ == "__main__":
    variant = sys.argv[1] if len(sys.argv) > 1 else "fp16"
    # coremltools has no converter for `_native_multi_head_attention` (MHA's eval fast path).
    torch.backends.mha.set_fastpath_enabled(False)
    model = load_htdemucs()
    core = HTDemucsCore(model).eval()
    mix = torch.from_numpy(read_stereo(CLIP)[:, SEGMENT_SAMPLES:2 * SEGMENT_SAMPLES])[None]
    spec = spectrogram_input(model, mix)
    with torch.no_grad():
        ref_spec, ref_wave = (t.numpy() for t in core(mix, spec))
        traced = torch.jit.trace(core, (mix, spec))
    log("traced")

    t0 = time.perf_counter()
    ml = ct.convert(
        traced,
        inputs=[ct.TensorType(name="mix", shape=mix.shape), ct.TensorType(name="spec", shape=spec.shape)],
        outputs=[ct.TensorType(name="spec_out"), ct.TensorType(name="wave_out")],
        convert_to="mlprogram",
        compute_precision=precision("mixed" if variant == "int8" else variant),
        minimum_deployment_target=ct.target.iOS18,
    )
    if variant == "int8":
        from coremltools.optimize.coreml import OpLinearQuantizerConfig, OptimizationConfig, linear_quantize_weights
        config = OptimizationConfig(global_config=OpLinearQuantizerConfig(mode="linear_symmetric", granularity="per_channel"))
        ml = linear_quantize_weights(ml, config=config)
    ml.short_description = ("htdemucs (Meta, MIT) network without STFT/iSTFT. Input: 7.8 s stereo "
                            "44.1 kHz window + its complex-as-channels STFT. Sources: drums, bass, other, vocals.")
    path = WORK / f"HTDemucs_{variant}.mlpackage"
    ml.save(str(path))
    log(f"converted in {time.perf_counter() - t0:.0f} s → {path}")

    out = ml.predict({"mix": mix.numpy(), "spec": spec.numpy()})
    for name, ref in (("spec_out", ref_spec), ("wave_out", ref_wave)):
        y = out[name]
        log(f"{name}: shape {y.shape}, NaN {int(np.isnan(y).sum())}, inf {int(np.isinf(y).sum())}, "
            f"rel diff vs PyTorch {rel(y, ref):.2e}")
