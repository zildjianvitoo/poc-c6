# Spike Track B — Pemisahan Vokal CoreML (IK-14) — 1 November 2026

**Keputusan: GO.** Open-Unmix (umxhq, vokal) versi CoreML menjadi cara pemisahan default untuk lagu impor; center-channel tetap ada sebagai cadangan otomatis.

## Model
| | |
|---|---|
| Model | Open-Unmix `umxhq` target vokal (sigsep), 8,9 juta parameter, 3 lapis Bi-LSTM |
| Lisensi | Kode & bobot MIT (`Licenses/OpenUnmix-LICENSE.txt`). Bobot dilatih di MUSDB18-HQ — cek syarat dataset sebelum dipakai komersial |
| Sumber bobot | Zenodo resmi (record 3370489, `vocals-b62c91ce.pth`, hash SHA-256 cocok) |
| Konversi | PyTorch 2.7 → coremltools 9.0, ML Program fp16, input tetap `(1, 2, 2049, 256)` ≈ 5,9 s per panggilan |
| Ukuran | **17,8 MB** (`poc-c6/Resources/OpenUnmixVocals.mlpackage`); app Debug total 23 MB |
| Akurasi konversi | CoreML vs PyTorch: selisih rata-rata relatif **0,1%** |

## Cara kerja di app (`CoreMLStemSeparationRepository`)
Audio dipotong sesuai trim dan di-resample ke 44,1 kHz stereo → STFT 4096/1024 per kanal (`ShortTimeFourierTransform`, rekonstruksi error 2,4×10⁻⁷) → model memperkirakan magnitudo vokal per potongan 256 frame dengan tumpang tindih 32 frame (sambungan di-crossfade) → soft mask → iSTFT → vokal; **instrumental = mix − vokal**. Guide nada diambil dari vokal hasil pemisahan.

## Hasil (lagu asli *A Whole New World*, 60 s pertama, Mac M5)
| Ukuran | Center-channel | **CoreML** |
|---|---|---|
| Melodi vokal yang masih terdengar di musik latar (frame bernada sama dengan vokal) | 65% | **12%** |
| Waktu proses 60 s | 0,3 s | **0,87 s** (Swift + CoreML) |
| Penyanyi bersuara bersih lolos (guide dari stem ini, ±80¢) | 92% | **91%** |
| Penyanyi meleset 2 semitone lolos | 0% | 0% |
| Memori puncak proses (Mac) | — | 427 MB |

Implementasi Swift vs referensi PyTorch (instrumental 60 s): korelasi **0,994**, SNR 19 dB (selisih karena fp16 + pemotongan per chunk).

## Belum diukur / risiko
- **Kecepatan & memori di iPhone fisik** belum diukur (target PRD < 30 s untuk 60 s; di Mac 0,87 s). Memori 427 MB di Mac bisa dikurangi (spektrum disimpan seluruhnya); dipantau saat tes di iPhone.
- Kualitas dinilai dengan ukuran objektif (kebocoran melodi), **belum didengar manusia** — perlu dicek manual lewat tombol *Background* di layar Ready.
- Model `umxhq` dilatih di MUSDB18-HQ; versi lebih baik (`umxl`) berlisensi non-komersial, sengaja tidak dipakai.

## Perubahan kode
- `CoreMLStemSeparationRepository`, `ShortTimeFourierTransform`, `SelectingStemSeparationRepository` (CoreML → cadangan center-channel), model di `Resources/`.
- `PoCConfiguration.useCoreMLSeparation` default **true** (bisa dimatikan di Debug Settings).
- `scripts/check-prep.sh` menjalankan 11 cek CoreML (panjang sample-exact, tanpa NaN, cache, trim tidak valid, fallback).
- Perbaikan bug: pembacaan file audio mono sekarang berulang sampai habis (sebelumnya ±8 ms terakhir terpotong).
