from pathlib import Path
import subprocess, sys, tempfile
root = Path(__file__).resolve().parents[3]
fixtures = Path(__file__).resolve().parent
android = str(Path(sys.argv[1]).resolve())
with tempfile.TemporaryDirectory(prefix="studybible-audio-test-") as directory:
    jar = str(Path(directory) / "regression.jar")
    sources = [str(p) for p in sorted(fixtures.glob("*.kt"))]
    sources.append(str(root / "android/app/src/main/kotlin/com/deanbowen/bibleappmac/RecordedBibleAudioBridge.kt"))
    subprocess.run(["kotlinc", "-nowarn", "-cp", android, *sources, "-include-runtime", "-d", jar], check=True)
    subprocess.run(["java", "-Djava.io.tmpdir=" + directory, "-cp", jar + ":" + android, "RegressionKt"], check=True)
