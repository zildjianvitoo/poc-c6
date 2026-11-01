"""Run deterministic session checks on macOS without microphone/simulator access."""
from pathlib import Path
import os
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
app = root / "poc-c6"
sources = list((app / "Domain").rglob("*.swift"))
sources += list((app / "Shared/Practice").glob("*.swift"))
sources += [app / path for path in [
    "Shared/PracticeConfiguration.swift", "Shared/DSP/PitchDetector.swift",
    "Shared/DSP/PitchFrameBuffer.swift", "Data/Demo/Twinkle.swift",
    "Data/Demo/TwinkleSessionGuide.swift", "Data/Session/SessionTakeLogRepositoryImpl.swift",
    "Data/Session/RecordingHandoff.swift",
]]
environment = dict(os.environ)
environment.setdefault("DEVELOPER_DIR", "/Applications/Xcode.app/Contents/Developer")
with tempfile.TemporaryDirectory(prefix="takin-session-checks-") as directory:
    for test in ["TwinkleSessionChecks", "SegmentEvaluationChecks"]:
        binary = str(Path(directory) / test)
        subprocess.run([
            "xcrun", "swiftc", "-D", "DEBUG", "-module-cache-path",
            str(Path(directory) / "ModuleCache"), *map(str, sources),
            str(root / "Tests" / (test + ".swift")), "-o", binary,
        ], check=True, env=environment)
        subprocess.run([binary], check=True, env=environment)
