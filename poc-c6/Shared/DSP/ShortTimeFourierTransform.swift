//
//  ShortTimeFourierTransform.swift
//  poc-c6
//
//  STFT / inverse STFT matching torch.stft: periodic Hann window, `center = true` with reflect
//  padding, one-sided spectrum, overlap-add inverse normalised by the summed squared window.
//  DemucsSpectrogram builds the htdemucs STFT on top of it.
//  Per-sample work is done with vDSP so Debug builds (no Swift optimisation) stay fast.
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
        let half = fftSize / 2
        // Zeros after the reflect padding keep the last frame's read in bounds.
        let padded = Self.reflectPad(signal, pad) + [Float](repeating: 0, count: fftSize)
        let frames = frameCount(sampleCount: signal.count)
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return [] }
        defer { vDSP_destroy_fftsetup(setup) }
        var result: [Spectrum] = []
        result.reserveCapacity(frames)
        var frame = [Float](repeating: 0, count: fftSize)
        var evens = [Float](repeating: 0, count: half)
        var odds = [Float](repeating: 0, count: half)
        var scale: Float = 0.5  // vDSP's forward real FFT is scaled by 2.
        padded.withUnsafeBufferPointer { source in
            for index in 0..<frames {
                vDSP_vmul(source.baseAddress! + index * hop, 1, window, 1, &frame, 1, vDSP_Length(fftSize))
                var spectrum = Spectrum(real: [Float](repeating: 0, count: bins), imaginary: [Float](repeating: 0, count: bins))
                evens.withUnsafeMutableBufferPointer { re in
                    odds.withUnsafeMutableBufferPointer { im in
                        var split = DSPSplitComplex(realp: re.baseAddress!, imagp: im.baseAddress!)
                        // Pack even/odd samples, transform, unpack.
                        frame.withUnsafeBytes {
                            vDSP_ctoz($0.bindMemory(to: DSPComplex.self).baseAddress!, 2, &split, 1, vDSP_Length(half))
                        }
                        vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(kFFTDirection_Forward))
                        spectrum.real[bins - 1] = im[0] * scale     // Nyquist
                        im[0] = 0                                   // DC has no imaginary part
                        vDSP_vsmul(re.baseAddress!, 1, &scale, &spectrum.real, 1, vDSP_Length(half))
                        vDSP_vsmul(im.baseAddress!, 1, &scale, &spectrum.imaginary, 1, vDSP_Length(half))
                    }
                }
                result.append(spectrum)
            }
        }
        return result
    }

    /// Overlap-add inverse; returns exactly `length` samples.
    func inverse(_ spectra: [Spectrum], length: Int) -> [Float] {
        let pad = fftSize / 2
        let half = fftSize / 2
        let total = (spectra.count - 1) * hop + fftSize
        var output = [Float](repeating: 0, count: total)
        var weights = [Float](repeating: 0, count: total)
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return [] }
        defer { vDSP_destroy_fftsetup(setup) }
        var re = [Float](repeating: 0, count: half)
        var im = [Float](repeating: 0, count: half)
        var frame = [Float](repeating: 0, count: fftSize)
        var two: Float = 2
        // Undo vDSP's inverse scaling (2 × N) together with the synthesis window.
        let scaledWindow = vDSP.multiply(1 / Float(2 * fftSize), window)
        let squaredWindow = vDSP.square(window)
        output.withUnsafeMutableBufferPointer { out in
            weights.withUnsafeMutableBufferPointer { weight in
                for (index, spectrum) in spectra.enumerated() {
                    vDSP_vsmul(spectrum.real, 1, &two, &re, 1, vDSP_Length(half))
                    vDSP_vsmul(spectrum.imaginary, 1, &two, &im, 1, vDSP_Length(half))
                    im[0] = spectrum.real[bins - 1] * 2  // vDSP packs Nyquist into the DC imaginary slot
                    re.withUnsafeMutableBufferPointer { rp in
                        im.withUnsafeMutableBufferPointer { ip in
                            var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                            vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(kFFTDirection_Inverse))
                            frame.withUnsafeMutableBytes {
                                vDSP_ztoc(&split, 1, $0.bindMemory(to: DSPComplex.self).baseAddress!, 2, vDSP_Length(half))
                            }
                        }
                    }
                    let start = index * hop
                    vDSP_vma(frame, 1, scaledWindow, 1, out.baseAddress! + start, 1, out.baseAddress! + start, 1, vDSP_Length(fftSize))
                    vDSP_vadd(squaredWindow, 1, weight.baseAddress! + start, 1, weight.baseAddress! + start, 1, vDSP_Length(fftSize))
                }
            }
        }
        let count = max(0, min(length, total - pad))
        var result = [Float](repeating: 0, count: length)
        guard count > 0 else { return result }
        // output / weight, but 0 where the window doesn't cover a sample (weight ≤ 1e-8).
        var floor: Float = 1e-8
        var safeWeights = [Float](repeating: 0, count: count)
        var coveredWeights = [Float](repeating: 0, count: count)
        weights.withUnsafeBufferPointer {
            vDSP_vthr($0.baseAddress! + pad, 1, &floor, &safeWeights, 1, vDSP_Length(count))     // max(w, 1e-8)
            vDSP_vthres($0.baseAddress! + pad, 1, &floor, &coveredWeights, 1, vDSP_Length(count)) // w, or 0 below 1e-8
        }
        var covered = [Float](repeating: 0, count: count)
        vDSP_vdiv(safeWeights, 1, coveredWeights, 1, &covered, 1, vDSP_Length(count))  // 1 or 0
        output.withUnsafeBufferPointer { out in
            result.withUnsafeMutableBufferPointer {
                vDSP_vdiv(safeWeights, 1, out.baseAddress! + pad, 1, $0.baseAddress!, 1, vDSP_Length(count))
                vDSP_vmul($0.baseAddress!, 1, covered, 1, $0.baseAddress!, 1, vDSP_Length(count))
            }
        }
        return result
    }

    private static func reflectPad(_ signal: [Float], _ pad: Int) -> [Float] {
        guard signal.count > pad else {
            return [Float](repeating: 0, count: pad) + signal + [Float](repeating: 0, count: pad)
        }
        let head = signal[1...pad].reversed()
        let tail = signal[(signal.count - 1 - pad)..<(signal.count - 1)].reversed()
        return Array(head) + signal + Array(tail)
    }
}
