"""htdemucs split into three parts so the network can be converted to CoreML:

  spectrogram_input(mix)        STFT outside the model (complex as channels)  → Swift side later
  HTDemucsCore(mix, spec)       the network: encoders, cross-transformer, decoders (converted)
  combine(model, spec_out, t)   iSTFT of the frequency branch + time branch    → Swift side later

`separate_chunked` mirrors demucs.apply.apply_model(shifts=0, split=True, overlap=0.25), with the
network call pluggable so the same code drives PyTorch and CoreML.
"""
import math

import numpy as np
import torch
from einops import rearrange
from torch import nn
from torch.nn import functional as F

from common import SEGMENT_SAMPLES

FRAMES = math.ceil(SEGMENT_SAMPLES / 1024)  # 336
BINS = 2048


def load_htdemucs():
    from demucs.pretrained import get_model
    return get_model("htdemucs").models[0].eval()


class HTDemucsCore(nn.Module):
    """HTDemucs.forward between `_magnitude` and `_mask`, for one fixed 343 980-sample window.

    Inputs:  mix (1, 2, 343980) waveform, spec (1, 4, 2048, 336) complex-as-channels STFT.
    Outputs: spec_out (1, 16, 2048, 336) per-source complex-as-channels STFT,
             wave_out (1, 8, 343980) per-source time-branch waveform.
    """

    def __init__(self, model):
        super().__init__()
        self.m = model

    def forward(self, mix, spec):
        m = self.m
        x = spec
        B, C, Fq, T = x.shape
        mean = x.mean(dim=(1, 2, 3), keepdim=True)
        std = x.std(dim=(1, 2, 3), keepdim=True)
        x = (x - mean) / (1e-5 + std)

        xt = mix
        meant = xt.mean(dim=(1, 2), keepdim=True)
        stdt = xt.std(dim=(1, 2), keepdim=True)
        xt = (xt - meant) / (1e-5 + stdt)

        saved, saved_t, lengths, lengths_t = [], [], [], []
        for idx, encode in enumerate(m.encoder):
            lengths.append(x.shape[-1])
            inject = None
            if idx < len(m.tencoder):
                lengths_t.append(xt.shape[-1])
                tenc = m.tencoder[idx]
                xt = tenc(xt)
                if not tenc.empty:
                    saved_t.append(xt)
                else:
                    inject = xt
            x = encode(x, inject)
            if idx == 0 and m.freq_emb is not None:
                frs = torch.arange(x.shape[-2], device=x.device)
                # Broadcast instead of expand_as: the expanded tensor would be folded into a
                # 16 MB constant in the CoreML model.
                emb = m.freq_emb(frs).t()[None, :, :, None]
                x = x + m.freq_emb_scale * emb
            saved.append(x)

        if m.crosstransformer:
            if m.bottom_channels:
                b, c, f, t = x.shape
                x = rearrange(x, "b c f t-> b c (f t)")
                x = m.channel_upsampler(x)
                x = rearrange(x, "b c (f t)-> b c f t", f=f)
                xt = m.channel_upsampler_t(xt)
            x, xt = m.crosstransformer(x, xt)
            if m.bottom_channels:
                x = rearrange(x, "b c f t-> b c (f t)")
                x = m.channel_downsampler(x)
                x = rearrange(x, "b c (f t)-> b c f t", f=f)
                xt = m.channel_downsampler_t(xt)

        for idx, decode in enumerate(m.decoder):
            skip = saved.pop(-1)
            x, pre = decode(x, skip, lengths.pop(-1))
            offset = m.depth - len(m.tdecoder)
            if idx >= offset:
                tdec = m.tdecoder[idx - offset]
                length_t = lengths_t.pop(-1)
                if tdec.empty:
                    pre = pre[:, :, 0]
                    xt, _ = tdec(pre, None, length_t)
                else:
                    skip = saved_t.pop(-1)
                    xt, _ = tdec(xt, skip, length_t)

        S = len(m.sources)
        x = x.view(B, S * C, Fq, T) * std + mean
        xt = xt.view(B, S * 2, -1) * stdt + meant
        return x, xt


def spectrogram_input(model, mix):
    """(1, 2, L) waveform → (1, 4, 2048, 336) complex-as-channels, as HTDemucs._spec/_magnitude."""
    with torch.no_grad():
        return model._magnitude(model._spec(mix))


def combine(model, spec_out, wave_out):
    """Per-source waveforms (S, 2, L) from the two branch outputs, as the end of HTDemucs.forward."""
    S = len(model.sources)
    B, _, Fq, T = spec_out.shape
    with torch.no_grad():
        z = model._mask(None, spec_out.view(B, S, 4, Fq, T))
        x = model._ispec(z, SEGMENT_SAMPLES)
    return (x + wave_out.view(B, S, 2, -1))[0]


def separate_chunked(model, mix, run_core):
    """mix (2, L) numpy → (S, 2, L) numpy. `run_core(mix_t, spec_t) -> (spec_out, wave_out)`."""
    length = mix.shape[-1]
    segment = SEGMENT_SAMPLES
    stride = int(0.75 * segment)
    weight = np.concatenate([np.arange(1, segment // 2 + 1),
                             np.arange(segment - segment // 2, 0, -1)]).astype(np.float32)
    weight /= weight.max()
    S = len(model.sources)
    out = np.zeros((S, 2, length), dtype=np.float32)
    total = np.zeros(length, dtype=np.float32)
    for offset in range(0, length, stride):
        n = min(segment, length - offset)
        # TensorChunk.padded: centre the short last chunk, take real context where it exists.
        start = offset - (segment - n) // 2
        lo, hi = max(0, start), min(length, start + segment)
        window = np.pad(mix[:, lo:hi], ((0, 0), (lo - start, start + segment - hi)))
        mix_t = torch.from_numpy(window)[None]
        spec_out, wave_out = run_core(mix_t, spectrogram_input(model, mix_t))
        y = combine(model, torch.as_tensor(spec_out), torch.as_tensor(wave_out)).numpy()
        trim = (segment - n) // 2  # demucs center_trim back to the chunk length
        y = y[..., trim:trim + n]
        out[..., offset:offset + n] += weight[:n] * y
        total[offset:offset + n] += weight[:n]
    return out / total
