# htdemucs → CoreML spike

Conversion and Mac measurement scripts for running Meta's **htdemucs** (Demucs v4, MIT) as a
CoreML model, as a possible upgrade over Open-Unmix for on-device vocal separation (PRD §3,
Track B). Results: `docs/test-reports/htdemucs-coreml-spike-2026-11-03.md`.

Nothing here is part of the app. The `.mlpackage` files and stems are written to
`~/htdemucs-spike/` (override with `HTDEMUCS_WORK`), never into the repo.

## How the model is split
`torch.stft`/`istft` use complex tensors that coremltools cannot convert, so only the network
is converted (`core.py`):

| Part | Where it runs | Shape (one 7.8 s window, 343 980 samples) |
|---|---|---|
| STFT (nfft 4096, hop 1024, normalized, demucs padding, last bin dropped), complex as channels | outside (Swift later) | mix `(1, 2, 343980)` → spec `(1, 4, 2048, 336)` |
| `HTDemucsCore`: encoders, cross-transformer, decoders, input normalisation | **CoreML** | → `spec_out (1, 16, 2048, 336)`, `wave_out (1, 8, 343980)` |
| iSTFT of `spec_out` + `wave_out` per source | outside (Swift later) | → 4 sources × stereo |
| Chunking: 7.8 s windows, 25 % overlap, triangular weights (`apply_model`) | outside (Swift later) | |

Sources are `drums, bass, other, vocals`; instrumental = drums + bass + other.

## Run
Uses the Open-Unmix spike venv (`~/umx-spike/venv`: torch 2.7, coremltools 9.0, demucs 4.1.0).
Put a stereo 44.1 kHz test clip at `~/htdemucs-spike/out/clip60.wav` (never commit songs).

```bash
P=~/umx-spike/venv/bin/python
$P phase0_reference.py htdemucs cpu      # PyTorch reference stems (also: mps, umx, center)
$P phase1_check_wrapper.py               # split pipeline == original htdemucs
$P phase2_convert.py mixed               # fp16 | mixed | fp32 | int8
$P phase3_measure.py mixed CPU_AND_GPU   # 60 s: time, peak memory, SNR vs PyTorch
$P leakage.py center umx_coreml htdemucs_torch_cpu htdemucs_mixed_CPU_AND_GPU
```

## Pitfalls found
- `nn.MultiheadAttention`'s eval fast path traces to `_native_multi_head_attention`, which
  coremltools cannot convert: call `torch.backends.mha.set_fastpath_enabled(False)` before tracing.
- Pure float16 is wrong (relative error 40–100 %): GroupNorm is lowered to
  `reduce_mean/sub/square/sqrt/real_div`, and `square` overflows float16. The `mixed` variant keeps
  that chain (plus softmax/attention/layer norm) in float32.
- `freq_emb(...).expand_as(x)` gets folded into a 16 MB constant; a broadcast add avoids it.
- With float16 compute precision coremltools also makes the model's inputs/outputs float16;
  `phase2_convert.py` declares them float32 (the app's Swift code expects float32).
- Compute units matter: see the report for which ones are accurate.
- The app's Swift port (`DemucsSpectrogram`, `HTDemucsStemSeparationRepository`) matches
  `core.py` + CoreML at 67 dB SNR on the test clip.
