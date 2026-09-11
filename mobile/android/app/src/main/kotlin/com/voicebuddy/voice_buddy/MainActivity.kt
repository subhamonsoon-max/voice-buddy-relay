package com.voicebuddy.voice_buddy

import android.Manifest
import android.content.pm.PackageManager
import android.media.*
import android.os.Handler
import android.os.Looper
import androidx.core.app.ActivityCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val METHOD_CHANNEL = "com.voicebuddy.audio/pcm_control"
    private val EVENT_CHANNEL = "com.voicebuddy.audio/pcm_record_stream"

    private val inputSampleRate = 16000
    private val outputSampleRate = 24000

    private var audioRecord: AudioRecord? = null
    private var audioTrack: AudioTrack? = null
    private var isRecording = false
    private val recordExecutor = Executors.newSingleThreadExecutor()
    private var eventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Setup EventChannel for streaming recorded microphone PCM chunks
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })

        // Setup MethodChannel for control and playback
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "initAudio" -> {
                        initAudioTrack()
                        result.success(true)
                    }
                    "startRecording" -> {
                        startPcmRecording()
                        result.success(true)
                    }
                    "stopRecording" -> {
                        stopPcmRecording()
                        result.success(true)
                    }
                    "playChunk" -> {
                        val data = call.argument<ByteArray>("data")
                        if (data != null) {
                            playPcmChunk(data)
                        }
                        result.success(true)
                    }
                    "stopPlayback" -> {
                        stopAudioPlayback()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun initAudioTrack() {
        try {
            val minBufferSize = AudioTrack.getMinBufferSize(
                outputSampleRate,
                AudioFormat.CHANNEL_OUT_MONO,
                AudioFormat.ENCODING_PCM_16BIT
            )
            val bufferSize = minBufferSize.coerceAtLeast(outputSampleRate / 2) // 500ms buffer

            audioTrack = AudioTrack.Builder()
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                        .build()
                )
                .setAudioFormat(
                    AudioFormat.Builder()
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                        .setSampleRate(outputSampleRate)
                        .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                        .build()
                )
                .setBufferSizeInBytes(bufferSize)
                .setTransferMode(AudioTrack.MODE_STREAM)
                .build()

            audioTrack?.play()
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun startPcmRecording() {
        if (isRecording) return

        if (ActivityCompat.checkSelfPermission(
                this,
                Manifest.permission.RECORD_AUDIO
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.RECORD_AUDIO),
                1001
            )
            return
        }

        try {
            val bufferSize = AudioRecord.getMinBufferSize(
                inputSampleRate,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT
            ).coerceAtLeast(inputSampleRate / 10) // 100ms chunk

            audioRecord = AudioRecord(
                MediaRecorder.AudioSource.MIC,
                inputSampleRate,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
                bufferSize
            )

            audioRecord?.startRecording()
            isRecording = true

            recordExecutor.execute {
                val buffer = ByteArray(bufferSize)
                while (isRecording) {
                    val readBytes = audioRecord?.read(buffer, 0, buffer.size) ?: 0
                    if (readBytes > 0) {
                        val chunk = buffer.copyOf(readBytes)
                        mainHandler.post {
                            eventSink?.success(chunk)
                        }
                    }
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
            isRecording = false
        }
    }

    private fun stopPcmRecording() {
        isRecording = false
        try {
            audioRecord?.stop()
            audioRecord?.release()
            audioRecord = null
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun playPcmChunk(data: ByteArray) {
        try {
            if (audioTrack == null || audioTrack?.state != AudioTrack.STATE_INITIALIZED) {
                initAudioTrack()
            }
            audioTrack?.write(data, 0, data.size)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun stopAudioPlayback() {
        try {
            audioTrack?.pause()
            audioTrack?.flush()
            audioTrack?.play()
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    override fun onDestroy() {
        stopPcmRecording()
        try {
            audioTrack?.stop()
            audioTrack?.release()
            audioTrack = null
        } catch (e: Exception) {
            e.printStackTrace()
        }
        recordExecutor.shutdown()
        super.onDestroy()
    }
}
