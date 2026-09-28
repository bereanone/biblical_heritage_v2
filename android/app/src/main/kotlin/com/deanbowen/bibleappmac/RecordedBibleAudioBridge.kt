package com.deanbowen.bibleappmac

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.AudioFormat
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.PlaybackParams
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import kotlin.math.abs
import kotlin.math.pow

/** Plays the same saved Qwen chapters and announcement cues used by the iPhone reader. */
class RecordedBibleAudioBridge(engine: FlutterEngine) {
    private data class CueEvent(val milliseconds: Int, val paths: List<String>)

    private val channel = MethodChannel(engine.dartExecutor.binaryMessenger, "studybible/recorded_audio")
    private val handler = Handler(Looper.getMainLooper())
    private var chapterPlayer: MediaPlayer? = null
    private var cuePlayer: MediaPlayer? = null
    private var cuePaths = emptyList<String>()
    private var cuePathIndex = 0
    private var events = emptyList<CueEvent>()
    private var nextEvent = 0
    private var reading = false
    private var generation = 0
    private var rate = 1.0f
    private var pitch = 1.0f
    private var loopStartMs: Int? = null
    private var loopEndMs: Int? = null

    private val tick = object : Runnable {
        override fun run() {
            if (!reading) return
            try {
                val player = chapterPlayer ?: return
                if (cuePlayer == null) {
                    val position = player.currentPosition
                    val end = loopEndMs
                    if (end != null && position >= end) {
                        val start = loopStartMs ?: 0
                        player.pause()
                        player.seekTo(start)
                        nextEvent = eventIndexAt(start)
                        channel.invokeMethod("looped", null)
                        if (!playDueCue(start)) startChapter()
                    } else {
                        playDueCue(position)
                    }
                }
            } catch (error: Exception) {
                reportError(error)
                return
            }
            handler.postDelayed(this, 25)
        }
    }

    init {
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "exportSegments" -> {
                        val args = call.argumentsMap()
                        Thread {
                            try {
                                exportSegments(args)
                                handler.post { result.success(null) }
                            } catch (error: Exception) {
                                handler.post { result.error("QWEN_EXPORT", error.message, null) }
                            }
                        }.start()
                    }
                    "load" -> {
                        val path = call.string("path") ?: error("Missing recording path")
                        load(path)
                        result.success(null)
                    }
                    "play" -> {
                        play(call.bool("announceAtStart") == true)
                        result.success(null)
                    }
                    "pause" -> {
                        pause()
                        result.success(null)
                    }
                    "stop" -> {
                        stop()
                        result.success(null)
                    }
                    "seek" -> {
                        seek((call.number("seconds") ?: 0.0) * 1000.0)
                        result.success(null)
                    }
                    "setRate" -> {
                        rate = (call.number("rate") ?: 1.0).toFloat().coerceIn(0.75f, 1.5f)
                        applyPlaybackParams()
                        result.success(null)
                    }
                    "setPitch" -> {
                        val semitones = (call.number("pitch") ?: 0.0).toFloat()
                        pitch = 2.0f.pow(semitones / 12.0f)
                        applyPlaybackParams()
                        result.success(null)
                    }
                    "setLoopRange" -> {
                        setLoopRange(call)
                        result.success(null)
                    }
                    "setAnnouncementEvents" -> result.success(setAnnouncementEvents(call))
                    "state" -> result.success(mapOf(
                        "position" to ((chapterPlayer?.currentPosition ?: 0) / 1000.0),
                        "playing" to reading,
                    ))
                    else -> result.notImplemented()
                }
            } catch (error: Exception) {
                result.error("ERROR", error.message ?: error.javaClass.simpleName, null)
            }
        }
    }

    private fun MethodCall.argumentsMap(): Map<*, *> = arguments as? Map<*, *> ?: emptyMap<Any, Any>()
    private fun MethodCall.string(key: String): String? = argumentsMap()[key] as? String
    private fun MethodCall.bool(key: String): Boolean? = argumentsMap()[key] as? Boolean
    private fun MethodCall.number(key: String): Double? = (argumentsMap()[key] as? Number)?.toDouble()

    private fun playerFor(path: String): MediaPlayer {
        require(File(path).isFile) { "Recording unavailable: ${File(path).name}" }
        return MediaPlayer().apply {
            setAudioAttributes(AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                .build())
            setDataSource(path)
            prepare()
        }
    }

    private fun load(path: String) {
        stop()
        val player = playerFor(path)
        player.setOnCompletionListener { completed ->
            if (completed !== chapterPlayer || !reading) return@setOnCompletionListener
            val start = loopStartMs
            if (start != null) {
                completed.seekTo(start)
                nextEvent = eventIndexAt(start)
                channel.invokeMethod("looped", null)
                if (!playDueCue(start)) startChapter()
            } else {
                reading = false
                handler.removeCallbacks(tick)
                channel.invokeMethod("complete", null)
            }
        }
        player.setOnErrorListener { _, what, extra ->
            reportError(IllegalStateException("Recording playback failed ($what/$extra)"))
            true
        }
        chapterPlayer = player
        events = emptyList()
        nextEvent = 0
        loopStartMs = null
        loopEndMs = null
    }

    private fun play(announceAtStart: Boolean) {
        val player = chapterPlayer ?: error("No recording loaded")
        if (reading) return
        reading = true
        if (announceAtStart) nextEvent = eventIndexAt(player.currentPosition)
        if (!playDueCue(player.currentPosition)) startChapter()
        handler.removeCallbacks(tick)
        handler.post(tick)
    }

    private fun startChapter() {
        if (!reading || cuePlayer != null) return
        val player = chapterPlayer ?: return
        if (!player.isPlaying) player.start()
        applyPlaybackParams()
    }

    private fun applyPlaybackParams() {
        val player = chapterPlayer ?: return
        if (!player.isPlaying) return
        player.playbackParams = PlaybackParams().setSpeed(rate).setPitch(pitch)
    }

    private fun pause() {
        reading = false
        ++generation
        handler.removeCallbacks(tick)
        releaseCue()
        chapterPlayer?.let { if (it.isPlaying) it.pause() }
    }

    private fun stop() {
        pause()
        chapterPlayer?.release()
        chapterPlayer = null
        events = emptyList()
        nextEvent = 0
        loopStartMs = null
        loopEndMs = null
    }

    private fun seek(milliseconds: Double) {
        val player = chapterPlayer ?: return
        val target = milliseconds.toInt().coerceIn(0, player.duration)
        releaseCue()
        player.seekTo(target)
        nextEvent = eventIndexAt(target)
        if (reading && !playDueCue(target)) startChapter()
    }

    private fun setLoopRange(call: MethodCall) {
        val start = call.number("startSeconds")?.times(1000.0)?.toInt()
        val end = call.number("endSeconds")?.times(1000.0)?.toInt()
        require((start == null && end == null) ||
            (start != null && end != null && end > start)) { "Invalid loop range" }
        loopStartMs = start
        loopEndMs = end
        if (call.bool("restart") == true && start != null) seek(start.toDouble())
    }

    private fun setAnnouncementEvents(call: MethodCall): Int {
        val rows = call.argumentsMap()["events"] as? List<*> ?: error("Invalid announcements")
        val parsed = rows.map { row ->
            val map = row as? Map<*, *> ?: error("Invalid announcement")
            val seconds = (map["seconds"] as? Number)?.toDouble() ?: error("Missing cue time")
            val paths = (map["paths"] as? List<*>)?.map { it as? String ?: error("Invalid cue path") }
                ?: error("Missing cue paths")
            require(seconds >= 0 && paths.isNotEmpty() && paths.all { File(it).isFile }) {
                "Announcement audio unavailable"
            }
            CueEvent((seconds * 1000.0).toInt(), paths)
        }.sortedBy { it.milliseconds }
        events = parsed
        nextEvent = eventIndexAt(chapterPlayer?.currentPosition ?: 0)
        return parsed.size
    }

    private fun eventIndexAt(position: Int): Int =
        events.indexOfFirst { it.milliseconds >= position - 30 }.let {
            if (it < 0) events.size else it
        }

    private fun playDueCue(position: Int): Boolean {
        if (!reading || cuePlayer != null || nextEvent >= events.size) return false
        val event = events[nextEvent]
        if (event.milliseconds > position + 30) return false
        ++nextEvent
        chapterPlayer?.let { if (it.isPlaying) it.pause() }
        cuePaths = event.paths
        cuePathIndex = 0
        startNextCue()
        return true
    }

    private fun startNextCue() {
        if (!reading) return
        if (cuePathIndex >= cuePaths.size) {
            cuePaths = emptyList()
            startChapter()
            return
        }
        val path = cuePaths[cuePathIndex++]
        val token = generation
        val player = playerFor(path)
        cuePlayer = player
        player.setOnCompletionListener {
            if (token != generation || it !== cuePlayer) return@setOnCompletionListener
            releaseCue()
            startNextCue()
        }
        player.setOnErrorListener { _, what, extra ->
            reportError(IllegalStateException("Qwen announcement failed ($what/$extra)"))
            true
        }
        player.start()
    }

    private fun releaseCue() {
        cuePlayer?.release()
        cuePlayer = null
    }

    private fun reportError(error: Exception) {
        pause()
        channel.invokeMethod("error", error.message ?: "Recorded Bible playback failed")
    }
    /** Decode only requested intervals, preserving the shipped voice in PCM. */
    private fun exportSegments(args: Map<*, *>) {
        val path = args["outputPath"] as? String ?: error("Missing output path")
        val segments = args["segments"] as? List<*> ?: error("Missing segments")
        require(segments.isNotEmpty())
        RandomAccessFile(path, "rw").use { output ->
            output.setLength(0)
            output.write(ByteArray(44))
            for (value in segments) {
                val segment = value as? Map<*, *> ?: error("Invalid segment")
                decodeSegment(segment, output)
            }
            val size = output.length() - 44
            require(size > 0 && size < Int.MAX_VALUE - 36)
            val header = ByteBuffer.allocate(44).order(ByteOrder.LITTLE_ENDIAN)
            header.put("RIFF".toByteArray()).putInt(size.toInt() + 36)
            header.put("WAVEfmt ".toByteArray()).putInt(16)
            header.putShort(1).putShort(1).putInt(24000).putInt(48000)
            header.putShort(2).putShort(16)
            header.put("data".toByteArray()).putInt(size.toInt())
            output.seek(0)
            output.write(header.array())
        }
    }

    private fun decodeSegment(segment: Map<*, *>, output: RandomAccessFile) {
        val extractor = MediaExtractor()
        var decoder: MediaCodec? = null
        try {
            extractor.setDataSource(segment["path"] as? String ?: error("Missing source"))
            val track = (0 until extractor.trackCount).firstOrNull {
                extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true
            } ?: error("Missing audio track")
            extractor.selectTrack(track)
            val format = extractor.getTrackFormat(track)
            require(format.getInteger(MediaFormat.KEY_SAMPLE_RATE) == 24000 &&
                format.getInteger(MediaFormat.KEY_CHANNEL_COUNT) == 1) { "Unexpected Qwen format" }
            val duration = format.getLong(MediaFormat.KEY_DURATION)
            val startSeconds = (segment["startSeconds"] as? Number)?.toDouble() ?: 0.0
            val endSeconds = (segment["endSeconds"] as? Number)?.toDouble() ?: duration / 1e6
            require(startSeconds.isFinite() && endSeconds.isFinite() &&
                startSeconds >= 0 && endSeconds > startSeconds && endSeconds * 1e6 <= duration + 50000)
            val startUs = (startSeconds * 1e6).toLong()
            val endUs = minOf((endSeconds * 1e6).toLong(), duration)
            extractor.seekTo(startUs, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
            val codec = MediaCodec.createDecoderByType(format.getString(MediaFormat.KEY_MIME)!!)
            decoder = codec
            codec.configure(format, null, null, 0)
            codec.start()
            val info = MediaCodec.BufferInfo()
            var inputDone = false
            var done = false
            val initialLength = output.length()
            val deadline = System.nanoTime() + 60_000_000_000L
            while (!done) {
                check(System.nanoTime() < deadline) { "Qwen clip decoding timed out" }
                if (!inputDone) {
                    val index = codec.dequeueInputBuffer(10000)
                    if (index >= 0) {
                        val input = codec.getInputBuffer(index)!!
                        val size = extractor.readSampleData(input, 0)
                        if (size < 0) {
                            codec.queueInputBuffer(index, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputDone = true
                        } else {
                            codec.queueInputBuffer(index, 0, size, extractor.sampleTime, 0)
                            extractor.advance()
                        }
                    }
                }
                val index = codec.dequeueOutputBuffer(info, 10000)
                if (index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    val decoded = codec.outputFormat
                    require(decoded.getInteger(MediaFormat.KEY_SAMPLE_RATE) == 24000 &&
                        decoded.getInteger(MediaFormat.KEY_CHANNEL_COUNT) == 1)
                    require(!decoded.containsKey(MediaFormat.KEY_PCM_ENCODING) ||
                        decoded.getInteger(MediaFormat.KEY_PCM_ENCODING) == AudioFormat.ENCODING_PCM_16BIT)
                } else if (index >= 0) {
                    try {
                        val frames = info.size / 2
                        val first = kotlin.math.ceil((startUs - info.presentationTimeUs) * 24000.0 / 1e6)
                            .toInt().coerceIn(0, frames)
                        val last = kotlin.math.floor((endUs - info.presentationTimeUs) * 24000.0 / 1e6)
                            .toInt().coerceIn(0, frames)
                        if (last > first) {
                            val buffer = codec.getOutputBuffer(index)!!
                            buffer.position(info.offset + first * 2)
                            val bytes = ByteArray((last - first) * 2)
                            buffer.get(bytes)
                            output.write(bytes)
                        }
                        done = info.presentationTimeUs + frames * 1_000_000L / 24000 >= endUs ||
                            info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
                    } finally {
                        codec.releaseOutputBuffer(index, false)
                    }
                }
            }
            check(output.length() > initialLength) { "Empty recording interval" }
        } finally {
            try { decoder?.stop() } catch (_: Exception) { }
            decoder?.release()
            extractor.release()
        }
    }

}
