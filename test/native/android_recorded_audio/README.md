These tests run the production Android bridge against a controllable asynchronous MediaPlayer double. They cover delayed cue polling, seek/cue completion order, rapid seeks, pause, stop, and verse looping. They establish scheduling behavior, not audible-word correctness or reviewed alignment.

Run: python3 test/native/android_recorded_audio/run.py /path/to/android.jar
Requires kotlinc and java.
