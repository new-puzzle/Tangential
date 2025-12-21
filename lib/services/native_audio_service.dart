import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Service for communicating with AudioForegroundService (native Android)
/// Handles audio streaming with proper foreground service, bluetooth support, and noise suppression
///
/// For standard modes (DeepSeek, Mistral): Also accumulates audio for VAD + Whisper transcription
class NativeAudioService {
  static const MethodChannel _methodChannel = MethodChannel('com.tangential/audio');
  static const EventChannel _eventChannel = EventChannel('com.tangential/audio_stream');

  StreamSubscription? _audioSubscription;
  bool _isStreaming = false;
  bool _isPaused = false;

  // Audio buffering for standard modes (VAD + Whisper)
  final List<Uint8List> _audioBuffer = [];
  int _currentSampleRate = 16000;
  double _lastAmplitude = 0.0;

  bool get isStreaming => _isStreaming;
  bool get isPaused => _isPaused;

  /// Start audio streaming via foreground service
  /// This will:
  /// - Start Android foreground service (shows notification)
  /// - Handle bluetooth SCO for wireless headphones
  /// - Enable noise suppression and echo cancellation
  /// - Stream audio on background thread (no main thread blocking)
  Future<bool> startStreaming({
    required int sampleRate,
    required void Function(Uint8List) onData,
  }) async {
    // If already streaming and paused, just resume
    if (_isStreaming && _isPaused) {
      debugPrint('NativeAudio: Already streaming but paused, resuming');
      return await resumeStreaming();
    }

    // If already streaming and active, nothing to do
    if (_isStreaming && !_isPaused) {
      debugPrint('NativeAudio: Already streaming and active');
      return true;
    }

    try {
      debugPrint('NativeAudio: Starting foreground service at $sampleRate Hz');

      // Start listening to audio stream BEFORE starting service
      // This ensures we don't miss initial audio frames
      _audioSubscription = _eventChannel.receiveBroadcastStream().listen(
        (data) {
          if (data is Uint8List) {
            onData(data);
          } else if (data is List) {
            onData(Uint8List.fromList(data.cast<int>()));
          }
        },
        onError: (error) {
          debugPrint('NativeAudio: Stream error: $error');
          _isStreaming = false;
          _isPaused = false;
        },
        onDone: () {
          debugPrint('NativeAudio: Stream ended');
          _isStreaming = false;
          _isPaused = false;
        },
      );

      // Tell native to start foreground service
      final result = await _methodChannel.invokeMethod<bool>(
        'startAudioStream',
        {'sampleRate': sampleRate},
      );

      _isStreaming = result ?? false;
      _isPaused = false;

      if (_isStreaming) {
        debugPrint('NativeAudio: Foreground service started successfully');
      } else {
        debugPrint('NativeAudio: Failed to start foreground service');
        await _audioSubscription?.cancel();
        _audioSubscription = null;
      }

      return _isStreaming;
    } catch (e) {
      debugPrint('NativeAudio: Error starting: $e');
      await _audioSubscription?.cancel();
      _audioSubscription = null;
      _isStreaming = false;
      _isPaused = false;
      return false;
    }
  }

  /// Stop audio streaming and foreground service completely
  /// Only call this when ending the conversation
  Future<void> stopStreaming() async {
    if (!_isStreaming && _audioSubscription == null) {
      debugPrint('NativeAudio: Nothing to stop');
      return;
    }

    debugPrint('NativeAudio: Stopping foreground service completely');

    try {
      // Stop the foreground service first
      await _methodChannel.invokeMethod('stopAudioStream');
    } catch (e) {
      debugPrint('NativeAudio: Error stopping service: $e');
    }

    // Then cancel the stream subscription
    try {
      await _audioSubscription?.cancel();
    } catch (e) {
      debugPrint('NativeAudio: Error canceling subscription: $e');
    } finally {
      _audioSubscription = null;
      _isStreaming = false;
      _isPaused = false;
      debugPrint('NativeAudio: Stopped completely');
    }
  }

  /// Pause audio streaming (keeps foreground service alive)
  /// Use this when AI is speaking to avoid SecurityException on resume
  Future<bool> pauseStreaming() async {
    if (!_isStreaming) {
      debugPrint('NativeAudio: Cannot pause - not streaming');
      return false;
    }

    if (_isPaused) {
      debugPrint('NativeAudio: Already paused');
      return true;
    }

    try {
      debugPrint('NativeAudio: Pausing audio stream (service stays alive)');
      await _methodChannel.invokeMethod('pauseAudioStream');
      _isPaused = true;
      return true;
    } catch (e) {
      debugPrint('NativeAudio: Error pausing: $e');
      return false;
    }
  }

  /// Resume audio streaming after pause
  Future<bool> resumeStreaming() async {
    if (!_isStreaming) {
      debugPrint('NativeAudio: Cannot resume - not streaming');
      return false;
    }

    if (!_isPaused) {
      debugPrint('NativeAudio: Already active');
      return true;
    }

    try {
      debugPrint('NativeAudio: Resuming audio stream');
      await _methodChannel.invokeMethod('resumeAudioStream');
      _isPaused = false;
      return true;
    } catch (e) {
      debugPrint('NativeAudio: Error resuming: $e');
      return false;
    }
  }

  // ==================== BUFFERED MODE FOR STANDARD AI MODES ====================
  // These methods are used by standard modes (DeepSeek, Mistral, Gemini Flash, GPT-4o)
  // to accumulate audio for VAD-based recording, then save to file for Whisper.

  /// Start streaming with audio buffering for standard modes
  /// Audio is accumulated in memory and can be saved to file when speech ends
  Future<bool> startBufferedStreaming({
    int sampleRate = 16000,
  }) async {
    _currentSampleRate = sampleRate;
    _audioBuffer.clear();
    _lastAmplitude = 0.0;

    return await startStreaming(
      sampleRate: sampleRate,
      onData: _onBufferedAudioData,
    );
  }

  /// Internal handler for buffered audio data
  void _onBufferedAudioData(Uint8List data) {
    if (_isPaused) return;

    // Calculate amplitude for VAD
    _lastAmplitude = _calculateAmplitude(data);

    // Accumulate in buffer
    _audioBuffer.add(Uint8List.fromList(data));
  }

  /// Calculate amplitude from PCM 16-bit audio data
  /// Returns normalized amplitude 0.0-1.0
  double _calculateAmplitude(Uint8List pcmData) {
    if (pcmData.isEmpty) return 0.0;

    // PCM 16-bit little-endian: each sample is 2 bytes
    final samples = pcmData.length ~/ 2;
    if (samples == 0) return 0.0;

    int maxSample = 0;
    final byteData = ByteData.sublistView(pcmData);

    for (int i = 0; i < samples; i++) {
      final sample = byteData.getInt16(i * 2, Endian.little).abs();
      if (sample > maxSample) {
        maxSample = sample;
      }
    }

    // Normalize to 0.0-1.0 (16-bit max is 32767)
    return maxSample / 32767.0;
  }

  /// Get current amplitude for VAD (Voice Activity Detection)
  /// Returns normalized amplitude 0.0-1.0, or -1.0 on error
  double getAmplitude() {
    if (!_isStreaming || _isPaused) return 0.0;
    return _lastAmplitude;
  }

  /// Get the number of buffered audio bytes
  int get bufferedBytes {
    int total = 0;
    for (final chunk in _audioBuffer) {
      total += chunk.length;
    }
    return total;
  }

  /// Get buffered duration in milliseconds
  int get bufferedDurationMs {
    final bytes = bufferedBytes;
    // 16-bit mono PCM: 2 bytes per sample
    final samples = bytes ~/ 2;
    return (samples * 1000) ~/ _currentSampleRate;
  }

  /// Clear the audio buffer (start fresh for next recording)
  void clearBuffer() {
    _audioBuffer.clear();
    _lastAmplitude = 0.0;
    debugPrint('NativeAudio: Buffer cleared');
  }

  /// Save buffered audio to WAV file for Whisper transcription
  /// Returns the file path, or null on failure
  Future<String?> saveBufferToFile() async {
    if (_audioBuffer.isEmpty) {
      debugPrint('NativeAudio: No audio in buffer to save');
      return null;
    }

    try {
      // Combine all chunks into single buffer
      final totalBytes = bufferedBytes;
      final combinedBuffer = Uint8List(totalBytes);
      int offset = 0;
      for (final chunk in _audioBuffer) {
        combinedBuffer.setRange(offset, offset + chunk.length, chunk);
        offset += chunk.length;
      }

      // Create WAV file
      final wavData = _createWavFile(combinedBuffer, _currentSampleRate);

      // Save to temp file
      final appDir = await getApplicationDocumentsDirectory();
      final recordingsDir = Directory('${appDir.path}/recordings');
      if (!await recordingsDir.exists()) {
        await recordingsDir.create(recursive: true);
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filePath = '${recordingsDir.path}/recording_$timestamp.wav';
      final file = File(filePath);
      await file.writeAsBytes(wavData);

      debugPrint('NativeAudio: Saved ${bufferedDurationMs}ms audio to $filePath');

      // Clear buffer after saving
      clearBuffer();

      return filePath;
    } catch (e) {
      debugPrint('NativeAudio: Error saving buffer to file: $e');
      return null;
    }
  }

  /// Create a WAV file from PCM data
  /// WAV format: 44-byte header + raw PCM data
  Uint8List _createWavFile(Uint8List pcmData, int sampleRate) {
    final numChannels = 1;
    final bitsPerSample = 16;
    final byteRate = sampleRate * numChannels * bitsPerSample ~/ 8;
    final blockAlign = numChannels * bitsPerSample ~/ 8;
    final dataSize = pcmData.length;
    final fileSize = 36 + dataSize;

    final wavData = Uint8List(44 + dataSize);
    final byteData = ByteData.sublistView(wavData);

    // RIFF header
    wavData[0] = 0x52; // 'R'
    wavData[1] = 0x49; // 'I'
    wavData[2] = 0x46; // 'F'
    wavData[3] = 0x46; // 'F'
    byteData.setUint32(4, fileSize, Endian.little); // File size - 8
    wavData[8] = 0x57;  // 'W'
    wavData[9] = 0x41;  // 'A'
    wavData[10] = 0x56; // 'V'
    wavData[11] = 0x45; // 'E'

    // fmt subchunk
    wavData[12] = 0x66; // 'f'
    wavData[13] = 0x6D; // 'm'
    wavData[14] = 0x74; // 't'
    wavData[15] = 0x20; // ' '
    byteData.setUint32(16, 16, Endian.little); // Subchunk1Size (16 for PCM)
    byteData.setUint16(20, 1, Endian.little);  // AudioFormat (1 = PCM)
    byteData.setUint16(22, numChannels, Endian.little); // NumChannels
    byteData.setUint32(24, sampleRate, Endian.little);  // SampleRate
    byteData.setUint32(28, byteRate, Endian.little);    // ByteRate
    byteData.setUint16(32, blockAlign, Endian.little);  // BlockAlign
    byteData.setUint16(34, bitsPerSample, Endian.little); // BitsPerSample

    // data subchunk
    wavData[36] = 0x64; // 'd'
    wavData[37] = 0x61; // 'a'
    wavData[38] = 0x74; // 't'
    wavData[39] = 0x61; // 'a'
    byteData.setUint32(40, dataSize, Endian.little); // Subchunk2Size

    // Copy PCM data
    wavData.setRange(44, 44 + dataSize, pcmData);

    return wavData;
  }
}
