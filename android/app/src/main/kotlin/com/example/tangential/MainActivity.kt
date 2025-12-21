package com.example.tangential

import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
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
    private val AUDIO_FOCUS_CHANNEL = "com.tangential/audiofocus"
    
    private var playbackAudioFocusRequest: AudioFocusRequest? = null

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
        
        // MethodChannel for audio focus management (playback)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AUDIO_FOCUS_CHANNEL)
            .setMethodCallHandler { call, result ->
                val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                
                when (call.method) {
                    "requestPlaybackFocus" -> {
                        try {
                            val focusRequest = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
                                .setAudioAttributes(
                                    AudioAttributes.Builder()
                                        .setUsage(AudioAttributes.USAGE_MEDIA)
                                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                                        .build()
                                )
                                .build()
                                
                            playbackAudioFocusRequest = focusRequest
                            val res = audioManager.requestAudioFocus(focusRequest)
                            val granted = res == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
                            
                            if (granted) {
                                Log.d(TAG, "Playback audio focus granted")
                            } else {
                                Log.w(TAG, "Playback audio focus denied")
                            }
                            
                            result.success(granted)
                        } catch (e: Exception) {
                            Log.e(TAG, "Error requesting playback focus: ${e.message}")
                            result.success(false)
                        }
                    }
                    "releasePlaybackFocus" -> {
                        try {
                            playbackAudioFocusRequest?.let {
                                audioManager.abandonAudioFocusRequest(it)
                                Log.d(TAG, "Playback audio focus released")
                            }
                            playbackAudioFocusRequest = null
                            result.success(true)
                        } catch (e: Exception) {
                            Log.e(TAG, "Error releasing playback focus: ${e.message}")
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
