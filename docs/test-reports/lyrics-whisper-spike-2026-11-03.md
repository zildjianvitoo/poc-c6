# Spike Lirik Otomatis — Fase A (Mac) — 3 November 2026

**Tujuan:** setelah lagu diimpor, transkripsi lirik dari vokal hasil htdemucs (lagu utuh) dengan Whisper di perangkat. Lirik ini ditampilkan di layar pilih start dan durasi, dengan baris dan kata yang aktif disorot.

**Keputusan sebelumnya:** bahasa hanya `en` + `id`; lirik hanya dari ASR di perangkat (tanpa database online); sorotan per baris + per kata; model awal whisper-small 216 MB.

**Kesimpulan:**
- Lagu Inggris: akurat.
- Lagu Indonesia: small 216 MB **kurang akurat** (WER 42%). **large-v3-turbo 547 MB** jauh lebih baik (WER 27%).
- Deteksi bahasa otomatis Whisper **salah** untuk lagu Indonesia, jadi pilihan bahasanya wajib dibatasi ke `en`/`id`.

## Cara uji
- WhisperKit CLI 1.1.1 (`brew install whisperkit-cli`, MIT): model dan runtime CoreML yang sama dengan yang dipakai app nanti.
- Input: vokal htdemucs dari lagu utuh (`HTDemucsStemSeparationRepository`).
- Penilaian: `prototypes/lyrics-whisper/evaluate.py`. WER dihitung terhadap lirik acuan. Isian vokal (oh/uh) diabaikan, "biar pun" dan "biarpun" dianggap sama, dan segmen yang mulai setelah lagu selesai dibuang.
- Lagu dan liriknya ada di `local-songs/` dan tidak di-commit.

## Hasil
| Lagu | Model | Ukuran | Bahasa | WER | Waktu (Mac M5, warm) | Memori |
|---|---|---|---|---|---|---|
| *A Whole New World* (Inggris, 74 s) | small 216 MB, otomatis | 217 MB | `en` ✅ | — (tanpa lirik acuan; dibaca manual: hampir semua baris benar) | 9,6 s | 340 MB |
| *Abadi* – Dendi Nata (Indonesia, 276 s) | small 216 MB, otomatis | 217 MB | **`nn` (Norwegia) ❌** | 102% | 17,7 s | 420 MB |
| *Abadi* | small 216 MB, `id` dipaksa | 217 MB | `id` | 42% | 13,4 s | 440 MB |
| *Abadi* | small 486 MB (tanpa kuantisasi), `id` | 486 MB | `id` | 54% | 11,4 s | 380 MB |
| *Abadi* | **large-v3-turbo 547 MB**, `id` | 550 MB | `id` | **27%** | 18,5 s | 420 MB |

**Timestamp per kata:** 90–98% rentang waktu tiap kata jatuh di bagian vokal yang benar-benar bersuara, jadi sorotan kata bisa mengikuti lagu.

**Download dan kompilasi pertama:** 5–8 menit per model di Mac. Di iPhone ini terjadi sekali saja.

## Temuan untuk implementasi
1. **Bahasa:** jangan pakai deteksi otomatis apa adanya. Pakai hasil deteksi bahasa WhisperKit lalu ambil skor tertinggi di antara `en` dan `id` saja (cabang 2 dengan batasan, tanpa model klasifikasi tambahan).
2. **Teks halusinasi:** Whisper membuat segmen setelah lagu selesai, termasuk frasa klasik "terima kasih" di bagian hening, dan juga simbol `♪`. Filter yang diperlukan:
   - buang segmen yang mulai setelah durasi lagu,
   - buang kata yang rentang waktunya hampir tanpa suara di vokal hasil htdemucs,
   - buang simbol `♪`.
3. **Kesalahan khas bahasa Indonesia** (large): kata mirip bunyi (sepi→sopi, menanti→meranti), dua kata digabung atau dipecah, dan satu baris terlewat. Lirik perlu diberi label "dibuat otomatis".
4. **Memori htdemucs untuk lagu utuh:** awalnya puncak memori 7,2 GB untuk lagu 4,6 menit karena buffer CoreML per potongan tertahan sampai loop selesai. Sudah diperbaiki dengan `autoreleasepool` per potongan: puncaknya 1,27 GB, dan pemisahan butuh 8,5 s di Mac.

## Belum diukur
- Waktu dan memori Whisper di iPhone. Perkiraan kasar: beberapa kali lebih lambat dari Mac, jadi untuk large-v3-turbo dan lagu 4,6 menit bisa sekitar 1 menit atau lebih.
- WER lagu Inggris (belum ada lirik acuan) dan lagu uji lain.
- Pembatasan bahasa `en`/`id` lewat API WhisperKit; di CLI hanya bisa memaksa satu bahasa.
