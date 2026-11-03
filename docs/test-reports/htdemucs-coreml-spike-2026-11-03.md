# Spike htdemucs → CoreML (Fase 0–3, Mac) — 3 November 2026

**Kesimpulan: konversi BERHASIL dan layak lanjut ke integrasi Swift (Fase 4).** htdemucs versi CoreML menghasilkan stem yang praktis sama dengan PyTorch. Kebocoran melodi vokal ke musik latar turun dari **4,9% (Open-Unmix sekarang) menjadi 0,7%**. Di Mac M5 waktunya 1,6–2,0 detik untuk 60 detik audio. Syaratnya: model harus dijalankan dengan **`.cpuAndGPU`**. Neural Engine dan `.all` tidak boleh dipakai (lihat §4).

Angka di iPhone belum ada. Semua angka di sini dari Mac M5 (RAM 24 GB). Script ada di `prototypes/htdemucs-coreml/`.

## 1. Model
| | |
|---|---|
| Model | `htdemucs` (Demucs v4, Meta), 1 model (bukan `ft`), 41.984.456 parameter, 4 sumber: drums, bass, other, vocals |
| Lisensi | Kode & bobot MIT. Bobot dilatih di MUSDB18-HQ + 800 lagu internal Meta. Catatan dataset sama seperti Open-Unmix: aman untuk PoC/akademik, cek ulang sebelum komersial |
| Konversi | PyTorch 2.7 → coremltools 9.0, ML Program, target iOS 18, input tetap (1 jendela 7,8 s = 343.980 sampel) |
| Yang dikonversi | Hanya jaringan (`HTDemucsCore`). STFT/iSTFT, chunking 25% overlap, dan penjumlahan cabang frekuensi + waktu dikerjakan di luar model (nanti di Swift). Lihat `prototypes/htdemucs-coreml/README.md` |
| Instrumental | drums + bass + other (keluaran asli htdemucs), bukan mix − vokal |

Fase 1: bungkus model tanpa STFT identik bit-per-bit dengan htdemucs asli pada satu jendela (selisih 0).

## 2. Varian dan hasil (lagu *A Whole New World*, 60 detik pertama)
| Varian | Ukuran | Compute units | Waktu model 60 s | Memori puncak proses* | SNR vokal vs PyTorch | Kebocoran melodi |
|---|---|---|---|---|---|---|
| PyTorch CPU (referensi) | 168 MB | CPU | 14,1 s | 1.924 MB | — | **0,7%** |
| PyTorch MPS | 168 MB | GPU | 4,8 s | 850 MB | — | 0,7% |
| fp16 murni | 100 MB | semua | — | — | **rusak** (selisih 40–100%) | — |
| **mixed** (fp16, normalisasi fp32) | **85 MB** | **CPU+GPU** | **1,56 s** | 1.361 MB | **64,6 dB** | **0,7%** |
| mixed | 85 MB | CPU+NE | 28,4 s | **7.888 MB** | 52,3 dB | 0,7% |
| **int8** (bobot int8 per channel, hitung seperti mixed) | **43 MB** | **CPU+GPU** | **1,96 s** | 1.475 MB | 34,4 dB | **0,7%** |
| int8 | 43 MB | CPU+NE | 28,7 s | 7.757 MB | 34,3 dB | 0,7% |
| fp32 | 169 MB | CPU+GPU | 3,50 s | 1.452 MB | 127 dB | 0,7% |
| fp32 | 169 MB | CPU+NE (jalan di CPU) | 6,43 s | 1.703 MB | 106 dB | 0,7% |

\* Memori puncak satu proses Python. Sekitar 545 MB di antaranya sudah terpakai sebelum model dimuat (torch + bobot PyTorch untuk STFT). Bagian yang benar-benar dipakai CoreML kira-kira 800–900 MB, tapi angka ini **bukan perkiraan untuk iPhone**.

**Pembanding di metrik yang sama:**
| Metode | Kebocoran melodi | Waktu 60 s (Mac) |
|---|---|---|
| Center-channel (cadangan) | 62,9% | ~0 s |
| Open-Unmix CoreML (app sekarang) | 4,9% | 0,45 s |
| htdemucs CoreML mixed/int8 | **0,7%** | 1,6–2,0 s |

Metrik kebocoran: CREPE tiny (model app, keyakinan ≥ 0,5) menghitung persentase frame melodi vokal yang nadanya masih ada di stem instrumental (±50 cent). Melodi diambil dari vokal htdemucs PyTorch. Dicek juga dengan melodi dari vokal masing-masing metode, dan hasilnya sama. Angkanya berbeda dari laporan spike Open-Unmix (65% / 12%) karena definisi frame-nya berbeda. Yang bisa dibandingkan hanya angka di dalam satu tabel ini.

## 3. Masalah yang ditemukan saat konversi
1. **`_native_multi_head_attention` tidak didukung coremltools.** Solusinya `torch.backends.mha.set_fastpath_enabled(False)` sebelum trace.
2. **fp16 murni menghasilkan output salah, tanpa NaN.** GroupNorm dipecah menjadi `reduce_mean/sub/square/sqrt/real_div`, dan `square` dari aktivasi besar meluap di fp16. Varian **mixed** membiarkan rantai itu (plus softmax, attention, layer norm) tetap fp32. Bobot dan operasi lain tetap fp16.
3. **`freq_emb.expand_as(x)` dilipat menjadi konstanta 16 MB.** Diganti dengan broadcast, sehingga model turun dari 100 MB ke 85 MB.

## 4. Compute units: wajib `.cpuAndGPU`
- **Neural Engine tidak cocok.** Operasi fp32 tidak bisa jalan di ANE, jadi model terpecah-pecah antara ANE dan CPU. Akibatnya 18× lebih lambat dan memori naik ke ~7,9 GB, yang pasti mematikan app di iPhone.
- **`.all` dan CPU saja memberi output fp16 yang salah** (pada satu jendela, selisih cabang waktu 16–57%). Penyebabnya tampaknya cara CPU menghitung `mul`/`add` fp16. Jadi app harus memakai `.cpuAndGPU`, bukan `.all` (default `MLModelConfiguration`).
- **Risiko iOS: GPU tidak boleh dipakai saat app di background.** Kalau pengguna keluar dari app saat Persiapan, inferensi akan gagal. Perlu ditangani di Fase 4, misalnya dengan pindah ke cadangan Open-Unmix atau center-channel lewat `SelectingStemSeparationRepository`, dengan pesan dari `UserFacingError`.

## 5. Rekomendasi
- **Lanjut ke Fase 4 dengan varian int8 (43 MB, `.cpuAndGPU`).** Kebocorannya sama dengan mixed (0,7%), ukurannya setengah, dan hanya 0,4 s lebih lambat di Mac. SNR 34 dB terhadap PyTorch kemungkinan tidak terdengar di bawah musik, tapi **perlu dicek telinga** (bandingkan `htdemucs_int8_*` dan `htdemucs_mixed_*` di `~/htdemucs-spike/out/`). Kalau terdengar beda, pakai mixed (85 MB).
- Model baru masuk `poc-c6/Resources/` saat integrasi Fase 4, bukan sekarang.
- Open-Unmix tetap ada sebagai cadangan pertama, center-channel sebagai cadangan kedua.

## 6. Belum diukur / risiko
- **Waktu dan memori di iPhone 15 Pro** (Fase 5). Di Mac M5 GPU-nya 1,6–2,0 s. GPU iPhone jauh lebih lemah, tapi target PRD (< 30 s untuk 60 s) kemungkinan masih jauh di atas. Memori puncak harus dicek lewat Xcode Debug Navigator.
- **Implementasi Swift** untuk STFT ala demucs (normalized, padding tambahan, bin terakhir dibuang), iSTFT, dan chunking. Semua bisa dicek terhadap `core.py` dengan selisih yang terukur.
- Kualitas belum didengar manusia. Ukuran kualitasnya baru objektif (kebocoran melodi dan SNR).
- Hanya satu lagu yang diuji.
