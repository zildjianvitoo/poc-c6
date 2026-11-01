from pathlib import Path
import sys
import imageio_ffmpeg

link = Path(sys.executable).parent / 'ffmpeg'
if not link.exists() and not link.is_symlink():
    link.symlink_to(imageio_ffmpeg.get_ffmpeg_exe())
print('FFmpeg proyek siap.')
