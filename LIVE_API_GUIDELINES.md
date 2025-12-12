# Gemini Live & OpenAI Realtime API Guidelines

## CRITICAL LESSONS LEARNED

### 1. Audio Focus Conflict (MOST IMPORTANT)
**Problem:** On Android, when audio playback starts, the microphone recording STOPS due to audio focus loss.

**Solution:** ALWAYS restart mic streaming after AI finishes speaking:
```dart
onPlaybackComplete = () {
  // MUST restart mic streaming - Android kills it during playback
  _startAudioStreaming();
};
```

### 2. WebSocket Messages Can Be Binary
**Problem:** Gemini sends JSON messages as binary (bytes), not strings.

**Solution:** Try UTF-8 decode first, then parse as JSON:
```dart
if (message is List<int>) {
  try {
    messageStr = utf8.decode(message);
  } catch (e) {
    // Not UTF-8, treat as raw audio
    onAudio?.call(Uint8List.fromList(message));
    return;
  }
}
```

### 3. Text Responses Come Word-by-Word
**Problem:** Both APIs send transcript deltas word-by-word, flooding UI with messages.

**Solution:** Accumulate text in a buffer, send only on completion:
```dart
final StringBuffer _responseBuffer = StringBuffer();

// On delta:
_responseBuffer.write(delta);

// On turn complete:
onResponse?.call(_responseBuffer.toString());
_responseBuffer.clear();
```

---

## GEMINI LIVE API

### Correct WebSocket URL
```
wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent?key=YOUR_API_KEY
```

**CAUTION:** 
- Use `v1beta` NOT `v1alpha`
- API key goes in URL query parameter

### Correct Model Name
```
models/gemini-2.5-flash-native-audio-preview-09-2025
```

**CAUTION:** Include the `models/` prefix in the setup message.

### Setup Message Structure
```json
{
  "setup": {
    "model": "models/gemini-2.5-flash-native-audio-preview-09-2025",
    "generationConfig": {
      "responseModalities": ["AUDIO"],
      "temperature": 0.7,
      "topP": 0.95,
      "maxOutputTokens": 8192,
      "speechConfig": {
        "voiceConfig": {
          "prebuiltVoiceConfig": {"voiceName": "Kore"}
        }
      }
    },
    "systemInstruction": {
      "parts": [{"text": "Your system prompt here"}],
      "role": "user"
    },
    "outputAudioTranscription": {}
  }
}
```

### Available Voices (Gemini)
- Kore (default)
- Puck
- Charon
- Fenrir
- Aoede

### Audio Format
- **Input:** PCM Int16, Little Endian, 16kHz, Mono
- **Output:** PCM Int16, 24kHz, Mono

### Sending Audio
```json
{
  "realtimeInput": {
    "mediaChunks": [
      {"mimeType": "audio/pcm;rate=16000", "data": "BASE64_ENCODED_PCM"}
    ]
  }
}
```

### Key Response Fields
- `setupComplete` - Connection ready
- `serverContent.modelTurn.parts[].inlineData.data` - Audio (base64)
- `serverContent.outputTranscription.text` - What AI said (text)
- `serverContent.turnComplete` - AI finished speaking

---

## OPENAI REALTIME API

### Correct WebSocket URL
```
wss://api.openai.com/v1/realtime?model=gpt-4o-realtime-preview-2024-12-17
```

### Authentication (WebSocket)
Use protocol-based auth:
```dart
WebSocketChannel.connect(
  uri,
  protocols: [
    'realtime',
    'openai-insecure-api-key.$apiKey',
    'openai-beta.realtime-v1',
  ],
);
```

### Session Configuration
```json
{
  "type": "session.update",
  "session": {
    "modalities": ["text", "audio"],
    "instructions": "Your system prompt here",
    "voice": "alloy",
    "input_audio_format": "pcm16",
    "output_audio_format": "pcm16",
    "input_audio_transcription": {"model": "whisper-1"},
    "turn_detection": {
      "type": "server_vad",
      "threshold": 0.5,
      "prefix_padding_ms": 300,
      "silence_duration_ms": 500
    }
  }
}
```

### Available Voices (OpenAI)
- alloy
- echo
- fable
- onyx
- nova
- shimmer

### Audio Format
- **Input:** PCM Int16, 24kHz, Mono
- **Output:** PCM Int16, 24kHz, Mono

### Sending Audio
```json
{
  "type": "input_audio_buffer.append",
  "audio": "BASE64_ENCODED_PCM"
}
```

### Key Event Types
- `session.created` / `session.updated` - Connection ready
- `input_audio_buffer.speech_started` - User started talking
- `input_audio_buffer.speech_stopped` - User stopped talking
- `response.audio.delta` - Audio chunk (base64)
- `response.audio_transcript.delta` - Text word
- `response.audio_transcript.done` - Full transcript
- `response.done` - AI finished

---

## PCM AUDIO PLAYBACK

### Converting PCM to WAV for Playback
```dart
Uint8List pcmToWav(Uint8List pcmData, int sampleRate) {
  // WAV header is 44 bytes
  final wavHeader = ByteData(44);
  
  // RIFF header
  wavHeader.setUint8(0, 0x52); // 'R'
  wavHeader.setUint8(1, 0x49); // 'I'
  wavHeader.setUint8(2, 0x46); // 'F'
  wavHeader.setUint8(3, 0x46); // 'F'
  wavHeader.setUint32(4, 36 + pcmData.length, Endian.little);
  wavHeader.setUint8(8, 0x57);  // 'W'
  wavHeader.setUint8(9, 0x41);  // 'A'
  wavHeader.setUint8(10, 0x56); // 'V'
  wavHeader.setUint8(11, 0x45); // 'E'
  
  // fmt chunk
  wavHeader.setUint8(12, 0x66); // 'f'
  wavHeader.setUint8(13, 0x6D); // 'm'
  wavHeader.setUint8(14, 0x74); // 't'
  wavHeader.setUint8(15, 0x20); // ' '
  wavHeader.setUint32(16, 16, Endian.little); // Subchunk1Size
  wavHeader.setUint16(20, 1, Endian.little);  // AudioFormat (PCM)
  wavHeader.setUint16(22, 1, Endian.little);  // NumChannels (Mono)
  wavHeader.setUint32(24, sampleRate, Endian.little);
  wavHeader.setUint32(28, sampleRate * 2, Endian.little); // ByteRate
  wavHeader.setUint16(32, 2, Endian.little);  // BlockAlign
  wavHeader.setUint16(34, 16, Endian.little); // BitsPerSample
  
  // data chunk
  wavHeader.setUint8(36, 0x64); // 'd'
  wavHeader.setUint8(37, 0x61); // 'a'
  wavHeader.setUint8(38, 0x74); // 't'
  wavHeader.setUint8(39, 0x61); // 'a'
  wavHeader.setUint32(40, pcmData.length, Endian.little);
  
  // Combine
  final wavFile = Uint8List(44 + pcmData.length);
  wavFile.setAll(0, wavHeader.buffer.asUint8List());
  wavFile.setAll(44, pcmData);
  
  return wavFile;
}
```

---

## COMMON MISTAKES TO AVOID

| Mistake | Consequence | Fix |
|---------|-------------|-----|
| Wrong API version in URL | Connection fails | Use `v1beta` for Gemini |
| Missing `models/` prefix | Model not found | Include `models/` in model name |
| Not handling binary WebSocket messages | Setup message missed | UTF-8 decode first |
| Not restarting mic after playback | No second turn | Call `_startAudioStreaming()` |
| Showing every text delta | 40 messages for 40 words | Buffer and show on complete |
| Wrong sample rate | Garbled audio | 16kHz input for Gemini, 24kHz for OpenAI |
| Using HTTP headers for OpenAI WS auth | Auth fails on mobile | Use protocol-based auth |

---

## FLUTTER PACKAGES USED

```yaml
dependencies:
  web_socket_channel: ^3.0.0  # WebSocket connections
  record: ^6.0.0              # Mic recording/streaming
  just_audio: ^0.9.40         # Audio playback
  flutter_secure_storage: ^9.0.0  # API key storage
  permission_handler: ^11.0.0 # Mic permissions
```

---

## QUICK REFERENCE

| Setting | Gemini Live | OpenAI Realtime |
|---------|-------------|-----------------|
| Input Sample Rate | 16000 Hz | 24000 Hz |
| Output Sample Rate | 24000 Hz | 24000 Hz |
| Audio Format | PCM Int16 LE | PCM Int16 LE |
| Channels | Mono | Mono |
| Auth Method | URL query param | WS protocol |
| VAD | Built-in | Server VAD config |

---

*Created from Tangential project debugging session - December 2025*

