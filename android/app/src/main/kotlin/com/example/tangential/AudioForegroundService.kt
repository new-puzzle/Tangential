package com.example.tangential

import android.app.*
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.*
import android.media.audiofx.AcousticEchoCanceler
import android.media.audiofx.NoiseSuppressor
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import androidx.core.app.NotificationCompat
import io.flutter.plugin.common.EventChannel

class AudioForegroundService : Service() {
    companion object {
        const val NOTIFICATION_ID = 1001
        const val CHANNEL_ID = "tangential_audio"
        const val ACTION_START_RECORDING = "START_RECORDING"
        const val ACTION_STOP_RECORDING = "STOP_RECORDING"
        const val EXTRA_SAMPLE_RATE = "sampleRate"
        private const val TAG = "AudioForegroundService"
        
        // Static reference for EventChannel communication
        var eventSink: EventChannel.EventSink? = null
    }
    
    private lateinit var audioManager: AudioManager
    private var audioRecord: AudioRecord? = null
    private var noiseSuppressor: NoiseSuppressor? = null
    private var echoCanceler: AcousticEchoCanceler? = null
    
    private var recordingThread: Thread? = null
    private var isRecording = false
    private var pendingSampleRate = 16000
    
    // Bluetooth state tracking
    private var bluetoothScoState = AudioManager.SCO_AUDIO_STATE_DISCONNECTED
    private val scoStateReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            val state = intent?.getIntExtra(
                AudioManager.EXTRA_SCO_AUDIO_STATE, 
                AudioManager.SCO_AUDIO_STATE_ERROR
            )
            onBluetoothScoStateChanged(state)
        }
    }
    
    // Audio focus request
    private var audioFocusRequest: AudioFocusRequest? = null
    
    // Handler for posting audio data to Flutter
    private val audioDataHandler = Handler(Looper.getMainLooper())
    
    override fun onCreate() {
        super.onCreate()
        audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        createNotificationChannel()
        
        // Register bluetooth SCO state listener
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(
                scoStateReceiver,
                IntentFilter(AudioManager.ACTION_SCO_AUDIO_STATE_UPDATED),
                Context.RECEIVER_NOT_EXPORTED
            )
        } else {
            registerReceiver(
                scoStateReceiver, 
                IntentFilter(AudioManager.ACTION_SCO_AUDIO_STATE_UPDATED)
            )
        }
        
        Log.d(TAG, "Service created")
    }
    
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START_RECORDING -> {
                val sampleRate = intent.getIntExtra(EXTRA_SAMPLE_RATE, 16000)
                pendingSampleRate = sampleRate
                startRecording(sampleRate)
            }
            ACTION_STOP_RECORDING -> {
                stopRecording()
                stopSelf()
            }
        }
        return START_STICKY  // Restart if killed
    }
    
    private fun startRecording(sampleRate: Int) {
        if (isRecording) {
            Log.w(TAG, "Already recording")
            return
        }
        
        // Start foreground with notification
        val notification = createNotification("Preparing...")
        startForeground(NOTIFICATION_ID, notification)
        Log.d(TAG, "Started foreground service")
        
        // Request audio focus
        val focusRequestBuilder = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build()
            )
            .setOnAudioFocusChangeListener { focusChange ->
                handleAudioFocusChange(focusChange)
            }
            
        audioFocusRequest = focusRequestBuilder.build()
        val result = audioManager.requestAudioFocus(audioFocusRequest!!)
        
        if (result != AudioManager.AUDIOFOCUS_REQUEST_GRANTED) {
            Log.e(TAG, "Failed to get audio focus")
            updateNotification("Audio focus denied")
            return
        }
        
        Log.d(TAG, "Audio focus granted")
        
        // Check if bluetooth headset is ACTUALLY connected
        val isBluetoothConnected = audioManager.isBluetoothScoAvailableOffCall && 
                                   (audioManager.isBluetoothA2dpOn || audioManager.isBluetoothScoOn)
        
        if (isBluetoothConnected) {
            Log.d(TAG, "Bluetooth headset connected, starting SCO...")
            updateNotification("Connecting bluetooth...")
            audioManager.startBluetoothSco()
            audioManager.isBluetoothScoOn = true
            // Recording will start when SCO connects (see scoStateReceiver)
        } else {
            // No bluetooth headset, start recording immediately with phone mic
            Log.d(TAG, "No bluetooth headset, using phone mic/speaker")
            startActualRecording(sampleRate)
        }
    }
    
    private fun onBluetoothScoStateChanged(state: Int?) {
        bluetoothScoState = state ?: AudioManager.SCO_AUDIO_STATE_ERROR
        
        when (bluetoothScoState) {
            AudioManager.SCO_AUDIO_STATE_CONNECTED -> {
                Log.d(TAG, "Bluetooth SCO connected, starting recording")
                startActualRecording(pendingSampleRate)
            }
            AudioManager.SCO_AUDIO_STATE_DISCONNECTED -> {
                Log.d(TAG, "Bluetooth SCO disconnected")
                if (isRecording) {
                    // Bluetooth disconnected during recording - might need to handle reconnection
                    updateNotification("Bluetooth disconnected")
                }
            }
            AudioManager.SCO_AUDIO_STATE_CONNECTING -> {
                Log.d(TAG, "Bluetooth SCO connecting...")
                updateNotification("Connecting bluetooth...")
            }
            AudioManager.SCO_AUDIO_STATE_ERROR -> {
                Log.e(TAG, "Bluetooth SCO error")
                // Fallback to phone mic if bluetooth fails
                if (!isRecording) {
                    Log.d(TAG, "Bluetooth failed, falling back to phone mic")
                    startActualRecording(pendingSampleRate)
                }
            }
        }
    }
    
    private fun startActualRecording(sampleRate: Int) {
        if (isRecording) {
            Log.w(TAG, "Already recording")
            return
        }
        
        val minBufferSize = AudioRecord.getMinBufferSize(
            sampleRate,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT
        )
        
        if (minBufferSize == AudioRecord.ERROR || minBufferSize == AudioRecord.ERROR_BAD_VALUE) {
            Log.e(TAG, "Invalid buffer size: $minBufferSize")
            updateNotification("Recording error")
            return
        }
        
        val bufferSize = minBufferSize.coerceAtLeast(4096)
        
        try {
            audioRecord = AudioRecord(
                MediaRecorder.AudioSource.VOICE_COMMUNICATION,
                sampleRate,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
                bufferSize
            )
            
            if (audioRecord?.state != AudioRecord.STATE_INITIALIZED) {
                Log.e(TAG, "AudioRecord failed to initialize")
                updateNotification("Mic initialization failed")
                return
            }
            
            val audioSessionId = audioRecord!!.audioSessionId
            
            // Enable noise suppression
            if (NoiseSuppressor.isAvailable()) {
                noiseSuppressor = NoiseSuppressor.create(audioSessionId)
                noiseSuppressor?.enabled = true
                Log.d(TAG, "Noise suppressor enabled")
            }
            
            // Enable echo cancellation
            if (AcousticEchoCanceler.isAvailable()) {
                echoCanceler = AcousticEchoCanceler.create(audioSessionId)
                echoCanceler?.enabled = true
                Log.d(TAG, "Echo canceler enabled")
            }
            
            audioRecord?.startRecording()
            isRecording = true
            
            // Start recording thread (BACKGROUND THREAD, not main!)
            recordingThread = Thread {
                android.os.Process.setThreadPriority(
                    android.os.Process.THREAD_PRIORITY_URGENT_AUDIO
                )
                
                val buffer = ByteArray(bufferSize)
                var chunksProcessed = 0
                
                while (isRecording) {
                    val read = audioRecord?.read(buffer, 0, buffer.size) ?: 0
                    if (read > 0) {
                        chunksProcessed++
                        // Send to Flutter via EventChannel (on background thread)
                        sendAudioToFlutter(buffer.copyOf(read))
                        
                        // Log every 50 chunks to show activity
                        if (chunksProcessed % 50 == 0) {
                            Log.d(TAG, "Processed $chunksProcessed audio chunks")
                        }
                    }
                }
                
                Log.d(TAG, "Recording thread finished, processed $chunksProcessed chunks total")
            }.apply { 
                name = "AudioRecordingThread"
                start() 
            }
            
            Log.d(TAG, "Recording started successfully at ${sampleRate}Hz")
            updateNotification("Listening...")
            
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start recording: ${e.message}")
            updateNotification("Recording failed")
            stopRecording()
        }
    }
    
    private fun handleAudioFocusChange(focusChange: Int) {
        when (focusChange) {
            AudioManager.AUDIOFOCUS_LOSS -> {
                Log.d(TAG, "Audio focus lost")
                // Another app took audio focus, stop recording
                stopRecording()
            }
            AudioManager.AUDIOFOCUS_GAIN -> {
                Log.d(TAG, "Audio focus gained")
                // We got focus back - if we were supposed to be recording, we are
            }
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> {
                Log.d(TAG, "Audio focus lost temporarily")
                // Temporary loss (e.g., notification sound)
                // Keep recording but note it
            }
        }
    }
    
    private fun sendAudioToFlutter(audioData: ByteArray) {
        // This runs on recording thread (background)
        // Post to main thread ONLY for EventChannel send
        audioDataHandler.post {
            try {
                eventSink?.success(audioData)
            } catch (e: Exception) {
                Log.e(TAG, "Failed to send audio to Flutter: ${e.message}")
            }
        }
    }
    
    private fun stopRecording() {
        if (!isRecording && recordingThread == null) {
            Log.d(TAG, "Nothing to stop")
            return
        }
        
        Log.d(TAG, "Stopping recording...")
        isRecording = false
        
        // Stop recording thread
        try {
            recordingThread?.join(500)
        } catch (e: Exception) {
            Log.e(TAG, "Error joining recording thread: ${e.message}")
        }
        recordingThread = null
        
        // Release audio effects
        try {
            noiseSuppressor?.release()
        } catch (e: Exception) {
            Log.e(TAG, "Error releasing noise suppressor: ${e.message}")
        }
        noiseSuppressor = null
        
        try {
            echoCanceler?.release()
        } catch (e: Exception) {
            Log.e(TAG, "Error releasing echo canceler: ${e.message}")
        }
        echoCanceler = null
        
        // Stop AudioRecord
        try {
            audioRecord?.stop()
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping AudioRecord: ${e.message}")
        }
        
        try {
            audioRecord?.release()
        } catch (e: Exception) {
            Log.e(TAG, "Error releasing AudioRecord: ${e.message}")
        }
        audioRecord = null
        
        // Stop bluetooth SCO
        if (audioManager.isBluetoothScoOn) {
            audioManager.stopBluetoothSco()
            audioManager.isBluetoothScoOn = false
            Log.d(TAG, "Bluetooth SCO stopped")
        }
        
        // Release audio focus
        audioFocusRequest?.let {
            audioManager.abandonAudioFocusRequest(it)
            Log.d(TAG, "Audio focus released")
        }
        audioFocusRequest = null
        
        Log.d(TAG, "Recording stopped completely")
    }
    
    override fun onDestroy() {
        Log.d(TAG, "Service being destroyed")
        stopRecording()
        
        try {
            unregisterReceiver(scoStateReceiver)
        } catch (e: Exception) {
            Log.e(TAG, "Error unregistering SCO receiver: ${e.message}")
        }
        
        super.onDestroy()
    }
    
    private fun createNotification(text: String): Notification {
        val intent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_IMMUTABLE
            } else {
                0
            }
        )
        
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Tangential Voice")
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()
    }
    
    private fun updateNotification(text: String) {
        val notification = createNotification(text)
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.notify(NOTIFICATION_ID, notification)
    }
    
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Voice Conversation",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Shows when Tangential is listening to your voice"
                setShowBadge(false)
            }
            
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
            Log.d(TAG, "Notification channel created")
        }
    }
    
    override fun onBind(intent: Intent?): IBinder? = null
}

