//
//  ShortTimeFourierTransform.swift
//  poc-c6
//
//  STFT / inverse STFT matching torch.stft as used by Open-Unmix: periodic Hann window,
//  `center = true` with reflect padding, one-sided spectrum, overlap-add inverse normalised by
//  the summed squared window. Used by the CoreML vocal separation (Track B spike).
//

import Accelerate
import Foundation

nonisolated struct ShortTimeFourierTransform: Sendable {
    /// One frame's one-sided spectrum (`bins` = fftSize / 2 + 1).
    struct Spectrum: Sendable {
        var real: [Float]
        var imaginary: [Float]
    }

    let fftSize: Int
    let hop: Int
    var bins: Int { fftSize / 2 + 1 }
    private let window: [Float]
    private let log2n: vDSP_Length

    init(fftSize: Int = 4096, hop: Int = 1024) {
        precondition(fftSize.nonzeroBitCount == 1, "fftSize must be a power of two")
        self.fftSize = fftSize
        self.hop = hop
        log2n = vDSP_Length(log2(Double(fftSize)))
        // Periodic Hann (torch.hann_window default).
        window = (0..<fftSize).map { 0.5 - 0.5 * cos(2 * .pi * Float($0) / Float(fftSize)) }
    }

    /// Number of frames for `sampleCount` samples with centre padding.
    func frameCount(sampleCount: Int) -> Int { sampleCount / hop + 1 }

    func forward(_ signal: [Float]) -> [Spectrum] {
        let pad = fftSize / 2
        let padded = Self.reflectPad(signal, pad)
        let frames = frameCount(sampleCount: signal.count)
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return [] }
        defer { vDSP_destroy_fftsetup(setup) }
        var result: [Spectrum] = []
        result.reserveCapacity(frames)
        var frame = [Float](repeating: 0, count: fftSize)
        var evens = [Float](repeating: 0, count: fftSize / 2)
        var odds = [Float](repeating: 0, count: fftSize / 2)
        for index in 0..<frames {
            let start = index * hop
            for i in 0..<fftSize { frame[i] = (start + i < padded.count ? padded[start + i] : 0) * window[i] }
            // vDSP real FFT: pack even/odd samples, transform, unpack (values are scaled by 2).
            for i in 0..<fftSize / 2 { evens[i] = frame[2 * i]; odds[i] = frame[2 * i + 1] }
            var spectrum = Spectrum(real: [Float](repeating: 0, count: bins), imaginary: [Float](repeating: 0, count: bins))
            evens.withUnsafeMutableBufferPointer { re in
                odds.withUnsafeMutableBufferPointer { im in
                    var split = DSPSplitComplex(realp: re.baseAddress!, imagp: im.baseAddress!)
                    vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(kFFTDirection_Forward))
                    spectrum.real[0] = re[0] / 2                     // DC
                    spectrum.real[bins - 1] = im[0] / 2              // Nyquist
                    for k in 1..<(fftSize / 2) {
                        spectrum.real[k] = re[k] / 2
                        spectrum.imaginary[k] = im[k] / 2
                    }
                }
            }
            result.append(spectrum)
        }
        return result
    }

    /// Overlap-add inverse; returns exactly `length` samples.
    func inverse(_ spectra: [Spectrum], length: Int) -> [Float] {
        let pad = fftSize / 2
        let total = (spectra.count - 1) * hop + fftSize
        var output = [Float](repeating: 0, count: total)
        var weights = [Float](repeating: 0, count: total)
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return [] }
        defer { vDSP_destroy_fftsetup(setup) }
        var re = [Float](repeating: 0, count: fftSize / 2)
        var im = [Float](repeating: 0, count: fftSize / 2)
        for (index, spectrum) in spectra.enumerated() {
            re[0] = spectrum.real[0] * 2
            im[0] = spectrum.real[bins - 1] * 2
            for k in 1..<(fftSize / 2) {
                re[k] = spectrum.real[k] * 2
                im[k] = spectrum.imaginary[k] * 2
            }
            re.withUnsafeMutableBufferPointer { rp in
                im.withUnsafeMutableBufferPointer { ip in
                    var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                    vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(kFFTDirection_Inverse))
                }
            }
            // Unpack even/odd and undo vDSP's inverse scaling (2 × N).
            let scale = 1 / Float(2 * fftSize)
            let start = index * hop
            for i in 0..<fftSize / 2 {
                let even = re[i] * scale, odd = im[i] * scale
                output[start + 2 * i] += even * window[2 * i]
                output[start + 2 * i + 1] += odd * window[2 * i + 1]
                weights[start + 2 * i] += window[2 * i] * window[2 * i]
                weights[start + 2 * i + 1] += window[2 * i + 1] * window[2 * i + 1]
            }
        }
        var result = [Float](repeating: 0, count: length)
        for i in 0..<length where i + pad < total {
            let weight = weights[i + pad]
            result[i] = weight > 1e-8 ? output[i + pad] / weight : 0
        }
        return result
    }

    private static func reflectPad(_ signal: [Float], _ pad: Int) -> [Float] {
        guard signal.count > pad else {
            return [Float](repeating: 0, count: pad) + signal + [Float](repeating: 0, count: pad)
        }
        let head = (1...pad).map { signal[$0] }.reversed()
        let tail = (1...pad).map { signal[signal.count - 1 - $0] }
        return Array(head) + signal + tail
    }
}
