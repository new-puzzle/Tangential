package com.example.tangential

import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.media.audiofx.AcousticEchoCanceler
import android.media.audiofx.NoiseSuppressor
import android.util.Log

class AudioCaptureService {
    private var audioRecord: AudioRecord? = null
    private var isRecording = false
    private var noiseSuppressor: NoiseSuppressor? = null
    private var echoCanceler: AcousticEchoCanceler? = null
    private var recordingThread: Thread? = null

    fun startRecording(sampleRate: Int, onAudioData: (ByteArray) -> Unit): Boolean {
        if (isRecording) return true

        return try {
            val minBufferSize = AudioRecord.getMinBufferSize(
                sampleRate,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT
            )

            if (minBufferSize == AudioRecord.ERROR || minBufferSize == AudioRecord.ERROR_BAD_VALUE) {
                Log.e("NativeAudio", "Invalid minBufferSize: $minBufferSize")
                return false
            }

            // VOICE_COMMUNICATION enables built-in processing (NS/AEC/AGC) on many devices.
            val bufferSize = minBufferSize.coerceAtLeast(2048)
            audioRecord = AudioRecord(
                MediaRecorder.AudioSource.VOICE_COMMUNICATION,
                sampleRate,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
                bufferSize
            )

            if (audioRecord?.state != AudioRecord.STATE_INITIALIZED) {
                Log.e("NativeAudio", "AudioRecord failed to initialize")
                stopRecording()
                return false
            }

            val audioSessionId = audioRecord!!.audioSessionId

            if (NoiseSuppressor.isAvailable()) {
                noiseSuppressor = NoiseSuppressor.create(audioSessionId)
                noiseSuppressor?.enabled = true
            }

            if (AcousticEchoCanceler.isAvailable()) {
                echoCanceler = AcousticEchoCanceler.create(audioSessionId)
                echoCanceler?.enabled = true
            }

            audioRecord?.startRecording()
            isRecording = true

            recordingThread = Thread {
                val buffer = ByteArray(bufferSize)
                while (isRecording) {
                    val read = audioRecord?.read(buffer, 0, buffer.size) ?: 0
                    if (read > 0) {
                        onAudioData(buffer.copyOf(read))
                    }
                }
            }.apply { start() }

            true
        } catch (e: Exception) {
            Log.e("NativeAudio", "Failed to startRecording: ${e.message}")
            stopRecording()
            false
        }
    }

    fun stopRecording() {
        isRecording = false

        try {
            recordingThread?.join(250)
        } catch (_: Exception) {
        } finally {
            recordingThread = null
        }

        try {
            noiseSuppressor?.release()
        } catch (_: Exception) {
        } finally {
            noiseSuppressor = null
        }

        try {
            echoCanceler?.release()
        } catch (_: Exception) {
        } finally {
            echoCanceler = null
        }

        try {
            audioRecord?.stop()
        } catch (_: Exception) {
        }

        try {
            audioRecord?.release()
        } catch (_: Exception) {
        } finally {
            audioRecord = null
        }
    }
}
