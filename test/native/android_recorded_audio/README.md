These tests run the production Android bridge against a controllable asynchronous MediaPlayer double. They cover delayed cue polling, seek/cue completion order, rapid seeks, pause, stop, verse looping, a missing seek callback, stale callbacks, and exceptions while resuming from a callback.

A seek that remains pending for ten seconds while reading stops with an explicit error. It never resumes from an estimated position. Pausing cancels the deadline, resuming re-arms it, and a late seek completion cannot restart playback after an error. Selecting another chapter then returning creates a new player.

The missing-callback cases are fault injection. They establish scheduling and error behavior, not a reproduction of the remote Sony report, device/API compatibility, audible-word correctness, or reviewed alignment. API values exercise code branches in the double, not actual Android versions.

Run: python3 test/native/android_recorded_audio/run.py /path/to/android.jar
Requires kotlinc and java.
