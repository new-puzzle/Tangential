package com.example.tangential

import android.content.Context
import android.util.Log
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import com.ryanheise.audioservice.AudioServicePlugin

class MainActivity : FlutterFragmentActivity() {
    private val TAG = "TangentialAudio"

    private val AUDIO_CHANNEL = "com.tangential/audio"
    private val AUDIO_EVENT_CHANNEL = "com.tangential/audio_stream"

    private var audioCaptureService: AudioCaptureService? = null
    private var audioEventSink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Native audio streaming for foreground service
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, AUDIO_EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    audioEventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    audioEventSink = null
                }
            })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AUDIO_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startAudioStream" -> {
                        val sampleRate = call.argument<Int>("sampleRate") ?: 16000
                        try {
                            if (audioCaptureService == null) {
                                audioCaptureService = AudioCaptureService()
                            }
                            val started = audioCaptureService?.startRecording(sampleRate) { audioData ->
                                // Ensure events are sent on the main thread.
                                runOnUiThread {
                                    audioEventSink?.success(audioData)
                                }
                            } ?: false
                            result.success(started)
                        } catch (e: Exception) {
                            Log.e(TAG, "Failed to start native audio: ${e.message}")
                            result.success(false)
                        }
                    }
                    "stopAudioStream" -> {
                        try {
                            audioCaptureService?.stopRecording()
                            audioCaptureService = null
                            result.success(true)
                        } catch (e: Exception) {
                            Log.e(TAG, "Failed to stop native audio: ${e.message}")
                            result.success(false)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun provideFlutterEngine(context: Context): FlutterEngine? {
        return AudioServicePlugin.getFlutterEngine(context)
    }
}
