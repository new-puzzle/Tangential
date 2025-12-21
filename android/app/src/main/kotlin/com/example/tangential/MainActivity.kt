package com.example.tangential

import android.content.Context
import android.content.Intent
import android.os.Build
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

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // EventChannel for audio streaming from foreground service
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, AUDIO_EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    // Set the static event sink in AudioForegroundService
                    AudioForegroundService.eventSink = events
                    Log.d(TAG, "Audio EventChannel connected")
                }

                override fun onCancel(arguments: Any?) {
                    AudioForegroundService.eventSink = null
                    Log.d(TAG, "Audio EventChannel disconnected")
                }
            })

        // MethodChannel for controlling the foreground service
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AUDIO_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startAudioStream" -> {
                        val sampleRate = call.argument<Int>("sampleRate") ?: 16000
                        
                        try {
                            // Start foreground service
                            val intent = Intent(this, AudioForegroundService::class.java).apply {
                                action = AudioForegroundService.ACTION_START_RECORDING
                                putExtra(AudioForegroundService.EXTRA_SAMPLE_RATE, sampleRate)
                            }
                            
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                startForegroundService(intent)
                            } else {
                                startService(intent)
                            }
                            
                            Log.d(TAG, "Started AudioForegroundService at ${sampleRate}Hz")
                            result.success(true)
                        } catch (e: Exception) {
                            Log.e(TAG, "Failed to start foreground service: ${e.message}")
                            result.success(false)
                        }
                    }
                    "stopAudioStream" -> {
                        try {
                            val intent = Intent(this, AudioForegroundService::class.java).apply {
                                action = AudioForegroundService.ACTION_STOP_RECORDING
                            }
                            startService(intent)
                            
                            Log.d(TAG, "Stopped AudioForegroundService")
                            result.success(true)
                        } catch (e: Exception) {
                            Log.e(TAG, "Failed to stop foreground service: ${e.message}")
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
