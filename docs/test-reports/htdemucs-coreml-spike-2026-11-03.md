# Spike htdemucs → CoreML (Fase 0–4 di Mac, Fase 5 awal di iPhone 17) — 3 November 2026

**Kesimpulan: konversi BERHASIL dan sudah terpasang di app (Fase 4, varian int8tr 58 MB). Di iPhone 17 memori aman (puncak ~1 GB) dan 30 s diproses dalam ~3,6–3,9 s, baik di build Release maupun Debug (§7).** htdemucs versi CoreML menghasilkan stem yang praktis sama dengan PyTorch. Kebocoran melodi vokal ke musik latar turun dari **4,9% (Open-Unmix sekarang) menjadi 0,7%**. Di Mac M5 waktunya 1,6–2,0 detik untuk 60 detik audio. Syaratnya: model harus dijalankan dengan **`.cpuAndGPU`**. Neural Engine dan `.all` tidak boleh dipakai (lihat §4).

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
| int8out (int8, bobot kecil termasuk layer output tetap fp16) | 43 MB | CPU+GPU | 1,93 s | 1.475 MB | 36,4 dB | 0,7% |
| pal8 (palettization 8-bit k-means) | 43 MB | CPU+GPU | 1,62 s | 1.377 MB | 31,0 dB | 0,7% |
| **int8tr** (int8 hanya di cross-transformer) | **58 MB** | **CPU+GPU** | **1,84 s** | 1.395 MB | **59,1 dB** | **0,7%** |
| int8tr | 58 MB | CPU saja | 4,74 s | 1.623 MB | 36,6 dB (instrumental 28,8 dB) | 0,7% |
| fp32 | 169 MB | CPU+GPU | 3,50 s | 1.452 MB | 127 dB | 0,7% |
| fp32 | 169 MB | CPU+NE (jalan di CPU) | 6,43 s | 1.703 MB | 106 dB | 0,7% |

\* Memori puncak satu proses Python. Sekitar 545 MB di antaranya sudah terpakai sebelum model dimuat (torch + bobot PyTorch untuk STFT). Bagian yang benar-benar dipakai CoreML kira-kira 800–900 MB, tapi angka ini **bukan perkiraan untuk iPhone**.

**Pembanding di metrik yang sama:**
| Metode | Kebocoran melodi | Waktu 60 s (Mac) |
|---|---|---|
| Center-channel (cadangan) | 62,9% | ~0 s |
| Open-Unmix CoreML (app sekarang) | 4,9% | 0,45 s |
| htdemucs CoreML mixed/int8 | **0,7%** | 1,6–2,0 s |

Varian int8tr di app dikonversi ulang dengan I/O Float32 (SNR 59,5 dB, 1,88 s). Hasilnya praktis sama.

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
- **Tes dengar (Zildjian, 3 Nov):** kualitas pemisahan mixed dan int8 sama, tapi **int8 menambah hiss sepanjang lagu**. Hiss ini cocok dengan SNR int8 yang hanya ~34 dB. Kuantisasi 8-bit di seluruh model (int8, int8out, pal8) memberi SNR 31–36 dB, jadi hiss-nya kemungkinan muncul juga di ketiganya.
- **Lanjut ke Fase 4 dengan varian int8tr (58 MB, `.cpuAndGPU`).** Cross-transformer memegang 75% parameter dan bekerja di resolusi rendah, di tengah jaringan. Hanya bagian ini yang dibuat int8, sedangkan layer encoder dan decoder yang menyentuh audio langsung tetap fp16. Hasilnya SNR 59 dB, mendekati mixed (64,6 dB). Hiss-nya **perlu dikonfirmasi dengan didengar** (`local-songs/htdemucs-listen/5-*`). Kalau masih terdengar, pakai mixed (85 MB).
- **Tes dengar (Zildjian, 3 Nov):** int8tr dipilih.
- Open-Unmix tetap ada sebagai cadangan pertama, center-channel sebagai cadangan kedua.

## 6. Integrasi di app (Fase 4)
| | |
|---|---|
| Model | `poc-c6/Resources/HTDemucs.mlpackage` (int8tr, I/O Float32), lisensi `Licenses/Demucs-LICENSE.txt`. App Debug untuk Simulator: 24 → 86 MB |
| Kode | `DemucsSpectrogram` (STFT/iSTFT ala demucs, di atas `ShortTimeFourierTransform`), `HTDemucsStemSeparationRepository` (chunking 7,8 s, overlap 25%, bobot segitiga, vokal = `vocals`, instrumental = drums + bass + other) |
| Urutan | `SelectingStemSeparationRepository`: htdemucs → Open-Unmix → center-channel, semuanya di bawah flag `useCoreMLSeparation` yang sudah ada. Tidak ada flag baru (flag baru berarti mengubah kontrak `PoCConfiguration`) |
| `SeparatedStems.method` | Tetap `.coreML` (tanpa mengubah kontrak), jadi layar Ready tidak membedakan htdemucs dari Open-Unmix |

**Verifikasi di Mac (harness sementara yang mengompilasi file Swift app):**
| Ukuran | Hasil |
|---|---|
| Swift vs Python CoreML (model sama) | SNR vokal 67,1 dB, instrumental 61,1 dB, jadi implementasinya cocok |
| Swift vs PyTorch htdemucs | vokal 59,4 dB, instrumental 53,7 dB (sama dengan Python CoreML) |
| Waktu 60 s (Swift, `-O`, GPU M5) | 2,3 s |
| Ujung ke ujung `separateStems` (mp3, trim 30 s) lewat rantai Selecting | jalan, metode `.coreML` |
| **Peak memory footprint** satu proses (model dimuat sekali) | **≈ 2,0 GB** (RSS 0,94 GB; selisihnya kemungkinan memori GPU) |
| `xcodebuild` Simulator, `scripts/check-prep.sh` | lulus, termasuk 17 cek htdemucs baru (`HTDemucsSeparationChecks`): bentuk dan round trip `DemucsSpectrogram`, panjang sample-exact, vokal + instrumental ≈ mix, cache, trim tidak valid, urutan cadangan htdemucs → Open-Unmix → center-channel |

Percobaan yang tidak menolong: attention, softmax, dan layer norm di fp16 (hanya rantai GroupNorm yang fp32). Footprint tetap 2,0 GB dan waktunya justru 3,2 s, jadi tidak dipakai.

## 7. Tes di iPhone 17 (Fase 5 awal, 3 Nov)
Build Debug, dijalankan lewat `devicectl` dengan log `[Separation]` dari `LoggingStemSeparationRepository`. Ini lagu impor pertama setelah app dibuka.

| | htdemucs, trim 30 s |
|---|---|
| Waktu `separateStems` | **20,4 s** |
| Memory footprint | 47 → 597 MB, **puncak 1.012 MB** |
| Sisa memori sebelum batas iOS (sebelum mulai) | 3.329 MB |
| App mati karena memori? | Tidak (app ditutup manual setelahnya) |

- **Memori aman.** Puncaknya sekitar 1 GB, dengan sisa sekitar 2,3 GB dari batas iOS. Angka ini lebih rendah dari Mac (2,0 GB).
- **Waktu belum memenuhi target kalau dihitung linear.** 20,4 s untuk 30 s berarti kira-kira 40 s untuk 60 s, sedangkan target PRD di bawah 30 s. Angka ini **belum dipisah** antara tiga hal:
  1. pemuatan dan kompilasi model GPU pertama kali,
  2. DSP Swift (STFT/iSTFT dan loop array) yang di build **Debug** jalan tanpa optimasi compiler (di Mac dengan `-O`: total 2,3 s untuk 60 s),
  3. inferensi model.
  
  Ketiganya perlu diukur terpisah sebelum memutuskan optimasi.

**Rincian waktu (log `htdemucs timing`):**
| Tahap | Mac M5, `-O` (60 s) | Mac M5, `-Onone` (60 s) | **iPhone 17, Release (30 s, 6 potongan)** |
|---|---|---|---|
| Muat model | — | — | 0,95 s |
| Baca audio + tulis stem | — | — | 0,07 s |
| STFT + isi input | 0,10 s | 8,85 s | 0,05 s |
| Model (GPU) | 2,21 s | 2,17 s | **2,36 s** (0,39 s per potongan) |
| iSTFT + penggabungan | 0,28 s | 18,88 s | 0,14 s |
| **Total** | 2,6 s | 30,9 s | **≈ 3,6 s** |

**Kesimpulan waktu:** model di iPhone sudah cepat. Untuk 60 s (11 potongan) perkiraannya sekitar 4,5 s untuk model + 1 s muat model, jauh di bawah target 30 s. Angka 20,4 s di build Debug hampir seluruhnya berasal dari kode Swift STFT/iSTFT yang tidak dioptimasi compiler: di Mac kode ini ~70× lebih lambat dengan `-Onone`. Jadi Neural Engine atau MLX tidak diperlukan untuk mengejar target waktu.

**Perbaikan untuk build Debug (vDSP):** loop per sampel di `ShortTimeFourierTransform`, `DemucsSpectrogram`, dan `HTDemucsStemSeparationRepository.separate` diganti dengan vDSP: perkalian jendela, pack/unpack FFT, overlap-add, transpose input dan output model, penjumlahan sumber, dan pembobotan potongan. Hasilnya identik dengan versi lama (SNR 149 dB, sisa pembulatan float); kecocokan dengan Python CoreML tetap 67 dB.

| Mac M5, 60 s | Sebelum vDSP | Sesudah vDSP |
|---|---|---|
| `-Onone` (Debug): STFT + input / iSTFT + penggabungan | 8,85 s / 18,88 s | 0,08 s / 0,34 s |
| `-Onone` (Debug): total | 30,9 s | **2,3 s** |
| `-O` (Release): total | 2,6 s | 2,15 s |

**iPhone 17, build Debug sesudah vDSP (trim 30 s):** total **3,94 s** (sebelumnya 20,36 s). Rinciannya: muat model 0,97 s, baca audio 0,08 s, STFT + input 0,05 s, model 2,40 s, iSTFT + penggabungan 0,21 s, tulis stem 0,22 s. Memori puncak 1.051 MB, dengan sisa 3.328 MB sebelum batas iOS. Build Debug sekarang setara dengan Release (≈ 3,6 s).

- Belum diukur: lagu 60 s di iPhone (perkiraan ~6 s), perbandingan dengan Open-Unmix, dan app di background saat Persiapan. Loop mask Open-Unmix (`CoreMLStemSeparationRepository.separate`) belum diubah ke vDSP, jadi Open-Unmix di Debug masih lebih lambat.

## 8. Belum diukur / risiko
- Build Debug sempat lambat (~20 s untuk 30 s) karena STFT/iSTFT Swift tidak dioptimasi. Sudah diperbaiki dengan vDSP: di iPhone 17 sekarang 3,9 s (§7).
- Memori di iPhone 17 (8 GB) aman. iPhone dengan RAM 6 GB ke bawah belum dicoba.
- **Kalau Core ML menjalankan model di CPU** (Simulator, dan mungkin saat app di background), hasilnya tetap dipakai tapi lebih berisik: SNR 29–37 dB, level yang sama dengan hiss int8. Kebocoran tetap 0,7%. Cek di iPhone: keluar dari app saat Persiapan, lalu dengarkan hasilnya.
- Hanya satu lagu yang diuji.
