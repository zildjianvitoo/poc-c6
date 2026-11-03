//
//  DemucsSpectrogram.swift
//  poc-c6
//
//  The STFT / inverse STFT that htdemucs computes around its network (HTDemucs._spec/_ispec):
//  nfft 4096, hop 1024, `normalized = true`, extra reflect padding so frames = ⌈length / hop⌉,
//  the Nyquist bin dropped. Reference: prototypes/htdemucs-coreml/core.py.
//

import Accelerate
import Foundation

nonisolated struct DemucsSpectrogram: Sendable {
    /// Bins the model sees (the Nyquist bin of the 4096-point FFT is dropped).
    static let bins = 2048
    static let hop = 1024

    private let stft = ShortTimeFourierTransform(fftSize: 4096, hop: hop)
    /// torch.stft(normalized: true) scales by 1 / √nfft.
    private let scale = 1 / Float(4096).squareRoot()
    /// Extra padding demucs adds on both sides before the centred STFT.
    private let pad = hop / 2 * 3

    func frameCount(sampleCount: Int) -> Int { (sampleCount + Self.hop - 1) / Self.hop }

    /// `frameCount(sampleCount:)` frames of `bins + 1` values (the last bin is 0).
    func forward(_ signal: [Float]) -> [ShortTimeFourierTransform.Spectrum] {
        let frames = frameCount(sampleCount: signal.count)
        let padded = Self.reflectPad(signal, left: pad, right: pad + frames * Self.hop - signal.count)
        // The centred STFT of the padded signal has frames + 4 frames; demucs keeps the middle ones.
        return stft.forward(padded)[2..<(2 + frames)].map { spectrum in
            var s = ShortTimeFourierTransform.Spectrum(real: vDSP.multiply(scale, spectrum.real),
                                                       imaginary: vDSP.multiply(scale, spectrum.imaginary))
            s.real[Self.bins] = 0
            s.imaginary[Self.bins] = 0
            return s
        }
    }

    /// Inverse of `forward`; `spectra` holds `frameCount(sampleCount: length)` frames.
    func inverse(_ spectra: [ShortTimeFourierTransform.Spectrum], length: Int) -> [Float] {
        let bins = stft.bins
        let empty = ShortTimeFourierTransform.Spectrum(real: [Float](repeating: 0, count: bins),
                                                       imaginary: [Float](repeating: 0, count: bins))
        let unscaled = spectra.map { spectrum in
            var s = ShortTimeFourierTransform.Spectrum(real: vDSP.multiply(1 / scale, spectrum.real),
                                                       imaginary: vDSP.multiply(1 / scale, spectrum.imaginary))
            s.real[Self.bins] = 0
            s.imaginary[Self.bins] = 0
            return s
        }
        let full = [empty, empty] + unscaled + [empty, empty]
        let paddedLength = Self.hop * frameCount(sampleCount: length) + 2 * pad
        let signal = stft.inverse(full, length: paddedLength)
        return Array(signal[pad..<(pad + length)])
    }

    /// numpy/torch "reflect" padding (the edge sample is not repeated).
    private static func reflectPad(_ signal: [Float], left: Int, right: Int) -> [Float] {
        let n = signal.count
        guard n > max(left, right) else {
            return [Float](repeating: 0, count: left) + signal + [Float](repeating: 0, count: right)
        }
        let head = signal[1...left].reversed()
        let tail = signal[(n - 1 - right)..<(n - 1)].reversed()
        return Array(head) + signal + Array(tail)
    }
}
