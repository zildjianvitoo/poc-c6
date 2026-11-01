> **Alur terbaru:** buka app → tes/konfirmasi vocal range → lanjut impor lagu → analisis → guide disesuaikan otomatis → tinjau → siap latihan. Tab lama bukan lagi entry point. Range tersimpan dapat dipakai ulang atau dites ulang. Lima tes transposisi sintetis lolos; preview memakai AVAudioUnitTimePitch dengan pergeseran yang sama untuk guide dan semua track, tanpa mengubah tempo. Jika rentang melodi terlalu lebar, UI memberi tahu bahwa sebagian nada tetap di luar range. Akurasi tes range serta kualitas/timing audio transposisi masih perlu diperiksa pada iPhone fisik.

# Cover Pre — PoC iOS

Tambahan pada proyek KeyRehearsal, SwiftUI iOS 17+. Tab pertama **Siapkan** mengikuti storyboard: impor manual → review waveform → pilih 1–60 detik → analisis → review piano roll/frasa → panduan tersimpan. Fitur rehearsal lama tetap tersedia.

## Coba di iPhone fisik

1. Buka `KeyRehearsal.xcodeproj` di Xcode.
2. Target KeyRehearsal → Signing & Capabilities → pilih Team Apple ID milikmu; ubah bundle identifier jika diperlukan.
3. Sambungkan iPhone ke Mac, Trust, aktifkan Developer Mode bila diminta, pilih iPhone sebagai tujuan, lalu Run.
4. Buka tab **Siapkan**, tekan **Coba demo 12 detik**. Ini audio sinus sintetis dengan nada yang sudah diketahui, **bukan hasil analisis ML**. Preview, piano roll, edit frasa/lirik, dan simpan bisa dicoba tanpa server.
5. Untuk lagu asli, lanjutkan setup service. Gunakan **Pilih file audio** dari Files.

## Service analisis untuk lagu asli

Jalankan setup sekali dari folder `KeyRehearsal/Service`:

```sh
./setup.command
./start.command
```

Setup mengunduh Python 3.11, paket analisis, dan FFmpeg ke folder proyek. Tidak membutuhkan Homebrew, sehingga dapat dipakai pada macOS yang belum didukung Homebrew. Internet dan ruang disk beberapa GB diperlukan. Folder `.python`, `.setup-tools`, dan `.venv` adalah hasil instalasi lokal; jangan masukkan ke Git atau ZIP source. Setelah update requirements, jalankan setup lagi. Python bawaan macOS hanya dipakai untuk bootstrap pengelola instalasi.

Service mencetak alamat `http://nama-mac.local:8765` dan token acak. Di app, buka ikon jaringan kiri atas dan masukkan keduanya. iPhone dan Mac harus pada Wi-Fi yang sama; izinkan Local Network di iPhone dan koneksi masuk Python jika macOS menanyakan. Gunakan hostname `.local`, bukan `localhost` (yang menunjuk iPhone sendiri). Jika hostname yang dicetak berbeda, cek nama lokal Mac di System Settings → General → Sharing.

Audio asli dikirim ke Mac saat **Siapkan panduan** ditekan. Service memotong rentang pilihan menggunakan FFmpeg, memisahkan vokal/pengiring dengan Demucs, menjalankan Basic Pitch dan faster-whisper pada vokal yang sama, lalu menghasilkan note events, MIDI, kata bertimestamp, dan frasa berisi lirik otomatis. Model Demucs dan faster-whisper mengunduh bobot pada pemakaian pertama; koneksi internet diperlukan untuk instalasi dan unduhan model, bukan untuk mengirim audio ke layanan cloud.

API ini untuk satu user di jaringan lokal terpercaya: HTTP lokal, bearer token, satu job aktif, unggahan maksimum 100 MB. Bukan deployment publik. Jangan mengekspos port ke internet. App menyimpan token PoC dalam preferensi; gunakan token sekali pakai yang dibuat service, bukan password akun. Hentikan service setelah selesai. File Mac berada dalam `Service/jobs`; hapus folder pekerjaan yang tidak diperlukan setelah app berhasil mengunduh hasil. Batalkan di iPhone menghentikan penantian/unduhan, bukan komputasi yang sudah berjalan di Mac.

## Yang diimplementasikan

- Impor lokal M4A/WAV/MP3 yang didukung AVFoundation, validasi durasi 1 detik–30 menit.
- Waveform dari sampel audio asli, pilihan rentang maksimal 60 detik.
- Job async: upload, status, error, retry melalui tombol analisis, unduh stems.
- Piano roll memakai waktu AVAudioPlayer; preview referensi/vokal/pengiring.
- Segmentasi heuristik berdasarkan gap nada; batas yang melewati kata hasil ASR dilewati agar kata tidak terpotong. Ini belum pemahaman struktur kalimat lagu.
- Lirik otomatis multilingual dari vocal stem memakai faster-whisper (small, CPU int8), beserta perkiraan timestamp kata. Frasa diisi otomatis berdasarkan timeline yang sama.
- Preview menampilkan lirik frasa dan kata aktif mengikuti playback. Lirik tetap dapat dikoreksi; setelah teks frasa diedit, sorotan kata otomatis dinonaktifkan pada frasa itu agar tidak memakai timestamp teks lama.
- Jika ASR gagal/timeout/tidak mendapat kata yang layak, guide nada tetap disimpan dengan peringatan dan input manual.
- Proyek dan audio disimpan di Documents/Preparation; bisa dibuka lagi tanpa service.
- Jalur demo berlabel eksplisit, tanpa model atau service.

## Batas yang disengaja

Forced alignment setelah koreksi teks, tes range yang terhubung ke persiapan, transpose target, koreksi nada individual, recording kamera, scoring, auto-loop, dan comping belum termasuk. Layar terakhir tidak berpura-pura memulai rekaman. Basic Pitch bisa menghasilkan beberapa nada bersamaan ketika vokal berharmoni; pemilihan lead melody belum diselesaikan. Frasa yang panjang tanpa gap dapat tetap panjang agar tidak memotong nada yang ditahan.

Kode service ML tersedia, tetapi inferensi Demucs/Basic Pitch end-to-end belum diverifikasi di lingkungan ini. Tes API memakai pipeline stub dan **tidak** membuktikan kualitas transkripsi. Speech-to-text nyata telah diuji terpisah memakai model tiny pada ucapan sintetis (13 kata dan timestamp berhasil); ini belum validasi nyanyian ataupun model small default. Validasi lagu asli dan koneksi di iPhone fisik masih diperlukan. Demucs upstream sudah diarsipkan; dependensi dipatok untuk eksperimen, bukan janji pemeliharaan produksi.

## Verifikasi

```sh
cd Service
python3 -m unittest test_pipeline test_lyrics -v
# Sesudah dependensi web + httpx tersedia:
python3 -m unittest test_server -v
```

Build revisi iPhone tanpa signing dan Simulator berhasil pada Xcode 27.1. Sebanyak 16 tes Python serta tes kompatibilitas JSON Swift lolos. Rincian bukti dan batas pengujian ada di `Review/Pre/lyrics-revision-verification.md`. Signing/instalasi iPhone memerlukan Team milik pengguna. Bukti screenshot ada di `Review/Pre`.

## Struktur

- `PreparationModel.swift`: proyek, file, waveform, playback, transport job, persistensi.
- `PreparationView.swift`: impor, potongan, progress, guide, frasa, konfigurasi koneksi.
- `Service/pipeline.py`: pemisahan, Basic Pitch, penyusunan notes/segmen.
- `Service/server.py`: API dengan token, job serial, unduhan, pemulihan hasil selesai setelah restart.

Data nada memakai detik relatif terhadap awal pilihan. `sourceOffset` menyimpan posisi awal pilihan di file sumber. Track vokal dan pengiring sudah dipotong; referensi lokal memakai offset sumber. Rekaman nanti harus mempunyai timeline terpisah.

## Pengaturan lirik

Pasang ulang `requirements.txt` setelah revisi ini, lalu restart service. Tidak ada API key cloud; ASR berjalan lokal di Mac. Default `small` multilingual, bahasa dideteksi otomatis. Untuk lagu Indonesia, bisa memaksa bahasa agar lebih konsisten:

```sh
COVER_LYRICS_LANGUAGE=id ./start.command
```

Untuk lagu Inggris gunakan `en`; hilangkan variabel agar otomatis. `COVER_LYRICS_MODEL=medium` dapat meningkatkan kebutuhan memori dan waktu; default small lebih cocok untuk PoC. Worker ASR dibatasi 600 detik. Timestamp adalah estimasi model, bukan forced alignment yang sudah diverifikasi. Harmoni, musik yang bocor, pelafalan panjang, dan suara napas masih dapat menghasilkan kata keliru. Lirik otomatis selalu perlu ditinjau.

Proyek lama tetap terbaca karena field `words`, `language`, `lyricsStatus`, `warnings`, dan `lyricsEdited` bersifat opsional di iOS. Untuk mendapatkan lirik otomatis pada proyek lama, pilih **Ubah potongan dan analisis ulang**. Koreksi lama akan diganti oleh hasil analisis baru.

Referensi implementasi: https://github.com/spotify/basic-pitch dan https://github.com/facebookresearch/demucs dan https://github.com/SYSTRAN/faster-whisper.
