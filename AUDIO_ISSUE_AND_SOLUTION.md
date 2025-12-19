# Tangential App - Audio Issue and Proposed Solution

## App Purpose

Tangential is a **walking companion voice app**. The user puts their phone in their pocket and has a conversation with an AI while walking outdoors. The app must:

- Work with **screen off** (pocket mode)
- Work in **noisy outdoor environments** (wind, traffic, footsteps)
- Support continuous back-and-forth conversation without touching the phone

---

## Current Issue

### Symptom
The app stops responding after 2-5 exchanges when used **outdoors with background noise**. It works fine indoors in a quiet environment.

### Root Cause
The app sends **raw microphone audio** (including all background noise) directly to the AI server's Voice Activity Detection (VAD). 

Native apps like ChatGPT and Gemini perform **client-side noise suppression** BEFORE sending audio. This app does not.

### What Happens

```
CURRENT FLOW (Tangential):
Mic → Raw Audio (voice + wind + traffic) → Server VAD → Confused → Timeout

NATIVE APP FLOW (ChatGPT/Gemini):
Mic → Noise Suppression → Clean Audio → Server VAD → Works Reliably
```

### Why Server VAD Fails With Noise

1. Constant background noise sounds like "someone is always talking"
2. Server waits for silence to know user stopped speaking
3. Noise never stops → Server never detects end of speech
4. Server times out or waits forever
5. App appears to "stop working"

---

## Current Technical Implementation

### Audio Recording (`lib/services/recording_service.dart`)

Uses the `record` Flutter package:

```dart
final config = RecordConfig(
  encoder: AudioEncoder.pcm16bits,
  sampleRate: sampleRate,  // 16000 for Gemini, 24000 for OpenAI
  numChannels: 1,
);
final stream = await _recorder.startStream(config);
```

**Problem**: This captures raw audio with NO processing:
- No noise suppression
- No echo cancellation
- No automatic gain control
- Uses default audio source (not optimized for voice)

### Audio Sending

Raw PCM bytes are sent directly to WebSocket:

**Gemini Live** (`lib/services/gemini_live_service.dart`):
```dart
void sendAudio(Uint8List audioData) {
  final message = {
    'realtimeInput': {
      'mediaChunks': [
        {'mimeType': 'audio/pcm;rate=16000', 'data': base64Encode(audioData)},
      ],
    },
  };
  _channel!.sink.add(jsonEncode(message));
}
```

**OpenAI Realtime** (`lib/services/openai_realtime_service.dart`):
```dart
void sendAudio(Uint8List audioData) {
  final message = {
    'type': 'input_audio_buffer.append',
    'audio': base64Encode(audioData),
  };
  _channel!.sink.add(jsonEncode(message));
}
```

---

## Proposed Solution: Option A - Native Android Audio Capture

### Overview

Replace the Flutter `record` package with **native Android (Kotlin) code** that uses the `VOICE_COMMUNICATION` audio source. This audio source automatically applies:

- **Acoustic Echo Cancellation (AEC)** - Removes speaker audio from mic
- **Noise Suppression (NS)** - Filters background noise
- **Automatic Gain Control (AGC)** - Normalizes volume levels

### How It Works

```
NEW FLOW:
Mic → Native Kotlin (with NS/AEC/AGC) → Clean Audio → Flutter → Server VAD → Works
```

### Technical Approach

#### 1. Create Native Audio Recorder (Kotlin)

File: `android/app/src/main/kotlin/com/example/tangential/AudioCaptureService.kt`

```kotlin
class AudioCaptureService {
    private var audioRecord: AudioRecord? = null
    private var isRecording = false
    private var noiseSuppressor: NoiseSuppressor? = null
    private var echoCanceler: AcousticEchoCanceler? = null
    
    fun startRecording(sampleRate: Int, onAudioData: (ByteArray) -> Unit): Boolean {
        val bufferSize = AudioRecord.getMinBufferSize(
            sampleRate,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT
        )
        
        // VOICE_COMMUNICATION source has built-in processing
        audioRecord = AudioRecord(
            MediaRecorder.AudioSource.VOICE_COMMUNICATION,  // ← KEY DIFFERENCE
            sampleRate,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
            bufferSize
        )
        
        // Enable additional noise suppression if available
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
        
        // Read audio in background thread
        Thread {
            val buffer = ByteArray(bufferSize)
            while (isRecording) {
                val read = audioRecord?.read(buffer, 0, bufferSize) ?: 0
                if (read > 0) {
                    onAudioData(buffer.copyOf(read))
                }
            }
        }.start()
        
        return true
    }
    
    fun stopRecording() {
        isRecording = false
        noiseSuppressor?.release()
        echoCanceler?.release()
        audioRecord?.stop()
        audioRecord?.release()
        audioRecord = null
    }
}
```

#### 2. Add Platform Channel (Kotlin side)

In `MainActivity.kt`, add method channel for audio:

```kotlin
private val AUDIO_CHANNEL = "com.tangential/audio"
private var audioCaptureService: AudioCaptureService? = null

// In configureFlutterEngine:
MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AUDIO_CHANNEL).setMethodCallHandler { call, result ->
    when (call.method) {
        "startAudioStream" -> {
            val sampleRate = call.argument<Int>("sampleRate") ?: 16000
            audioCaptureService = AudioCaptureService()
            audioCaptureService?.startRecording(sampleRate) { audioData ->
                // Send audio data back to Flutter via EventChannel
                runOnUiThread {
                    audioEventSink?.success(audioData)
                }
            }
            result.success(true)
        }
        "stopAudioStream" -> {
            audioCaptureService?.stopRecording()
            audioCaptureService = null
            result.success(true)
        }
    }
}
```

#### 3. Add EventChannel for Audio Stream (Kotlin side)

```kotlin
private val AUDIO_EVENT_CHANNEL = "com.tangential/audio_stream"
private var audioEventSink: EventChannel.EventSink? = null

// In configureFlutterEngine:
EventChannel(flutterEngine.dartExecutor.binaryMessenger, AUDIO_EVENT_CHANNEL)
    .setStreamHandler(object : EventChannel.StreamHandler {
        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
            audioEventSink = events
        }
        override fun onCancel(arguments: Any?) {
            audioEventSink = null
        }
    })
```

#### 4. Create Flutter Service to Use Native Audio

File: `lib/services/native_audio_service.dart`

```dart
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/services.dart';

class NativeAudioService {
  static const MethodChannel _methodChannel = MethodChannel('com.tangential/audio');
  static const EventChannel _eventChannel = EventChannel('com.tangential/audio_stream');
  
  StreamSubscription? _audioSubscription;
  Function(Uint8List)? onAudioData;
  bool _isStreaming = false;
  
  bool get isStreaming => _isStreaming;
  
  Future<bool> startStreaming({
    required int sampleRate,
    required Function(Uint8List) onData,
  }) async {
    onAudioData = onData;
    
    try {
      // Start listening to audio stream from native
      _audioSubscription = _eventChannel
          .receiveBroadcastStream()
          .listen((data) {
            if (data is Uint8List) {
              onAudioData?.call(data);
            } else if (data is List) {
              onAudioData?.call(Uint8List.fromList(data.cast<int>()));
            }
          });
      
      // Tell native to start recording
      final result = await _methodChannel.invokeMethod<bool>(
        'startAudioStream',
        {'sampleRate': sampleRate},
      );
      
      _isStreaming = result ?? false;
      return _isStreaming;
    } catch (e) {
      print('Error starting native audio: $e');
      return false;
    }
  }
  
  Future<void> stopStreaming() async {
    try {
      await _methodChannel.invokeMethod('stopAudioStream');
      await _audioSubscription?.cancel();
      _audioSubscription = null;
      _isStreaming = false;
    } catch (e) {
      print('Error stopping native audio: $e');
    }
  }
}
```

#### 5. Integrate Into ConversationManager

In `lib/services/conversation_manager.dart`, replace `_recordingService.startStreaming()` with `_nativeAudioService.startStreaming()` for realtime modes.

---

## What Changes vs What Stays The Same

### Changes (Isolated to Audio Capture)
- New Kotlin file for audio capture with noise suppression
- New Flutter service to communicate with native code
- `conversation_manager.dart` uses new service for mic streaming

### Stays The Same
- All UI code
- WebSocket connections to Gemini/OpenAI
- Audio playback (`pcm_audio_player.dart`)
- Wake locks and background service
- Screen on/off detection
- Settings, API keys, everything else

---

## IMPORTANT: Implement As Optional Toggle

**Do NOT replace the existing audio capture. Make this an OPTIONAL feature.**

### ⚠️ CRITICAL: Do Not Modify Existing Code

- **DO NOT** change `lib/services/recording_service.dart` - leave it exactly as is
- **DO NOT** remove or modify any existing audio code
- **ONLY ADD** new files alongside existing ones
- When toggle is OFF, app must behave **exactly as it does today** - same code paths, same behavior
- The new native audio is **purely additive** - it's a second option, not a replacement

### Implementation Requirement

1. Add a setting in `lib/screens/settings_screen.dart`:
   - **"Use Native Audio (Experimental)"** - Toggle switch
   - Default: **OFF**
   - Description: "Enable hardware noise suppression for noisy environments. May improve outdoor performance."

2. In `lib/providers/app_state.dart`:
   - Add `bool _useNativeAudio = false;`
   - Add getter/setter with `notifyListeners()`

3. In `lib/services/conversation_manager.dart`:
   - Check `appState.useNativeAudio` before starting audio
   - If OFF → use existing `_recordingService.startStreaming()` (current behavior)
   - If ON → use new `_nativeAudioService.startStreaming()`

### Why Toggle Is Critical

- Current audio works indoors - don't break it
- Native audio is untested - might have issues
- User can switch back instantly if problems occur
- Allows A/B comparison

---

## Risks

| Risk | Mitigation |
|------|------------|
| Audio format mismatch | Use same PCM16 format, same sample rates |
| Platform channel errors | Add proper error handling and fallback |
| Breaks existing functionality | **Toggle OFF by default**, user enables manually |
| iOS not supported | This solution is Android-only; iOS would need separate implementation |

---

## Testing Plan

1. Test indoors (quiet) - should still work
2. Test outdoors (noisy) - should now work better
3. Test screen off - should still work
4. Compare audio quality: old vs new
5. If new breaks, revert to old `record` package

---

## Files To Create/Modify

### New Files
- `android/app/src/main/kotlin/com/example/tangential/AudioCaptureService.kt`
- `lib/services/native_audio_service.dart`

### Modified Files
- `android/app/src/main/kotlin/com/example/tangential/MainActivity.kt` (add channels)
- `lib/services/conversation_manager.dart` (use new service)

---

## Summary

The core issue is **raw audio with noise confusing server VAD**. The solution is to use Android's built-in `VOICE_COMMUNICATION` audio source which provides automatic noise suppression. This requires ~200 lines of new code, mostly in Kotlin, while keeping the rest of the Flutter app unchanged.

