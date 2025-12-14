import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

/// Service for recording audio from the microphone.
/// Handles permissions, recording state, and audio file management.
/// Supports both file-based recording and real-time streaming.
class RecordingService {
  final AudioRecorder _recorder = AudioRecorder();

  bool _isRecording = false;
  bool _isStreaming = false;
  String? _currentRecordingPath;
  Timer? _silenceTimer;
  StreamSubscription<List<int>>? _audioStreamSubscription;

  // Callbacks
  Function(Duration)? onRecordingDuration;
  VoidCallback? onSilenceDetected;
  Function(Uint8List)? onAudioData; // For streaming mode

  // Configuration
  int silenceTimeoutSeconds = 120; // 2 minutes default

  bool get isRecording => _isRecording;
  bool get isStreaming => _isStreaming;
  String? get currentRecordingPath => _currentRecordingPath;

  /// Request microphone permission
  Future<bool> requestPermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  /// Check if microphone permission is granted
  Future<bool> hasPermission() async {
    return await Permission.microphone.isGranted;
  }

  /// Start recording audio to a file
  Future<String?> startRecording({String? customFileName}) async {
    if (_isRecording) {
      await stopRecording();
    }

    // Check permission
    if (!await hasPermission()) {
      final granted = await requestPermission();
      if (!granted) {
        debugPrint('Microphone permission denied');
        return null;
      }
    }

    try {
      // Get directory for recordings
      final appDir = await getApplicationDocumentsDirectory();
      final recordingsDir = Directory('${appDir.path}/recordings');
      if (!await recordingsDir.exists()) {
        await recordingsDir.create(recursive: true);
      }

      // Generate filename
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = customFileName ?? 'recording_$timestamp.m4a';
      _currentRecordingPath = '${recordingsDir.path}/$fileName';

      // Configure recording
      const config = RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
        numChannels: 1,
      );

      // Start recording
      await _recorder.start(config, path: _currentRecordingPath!);
      _isRecording = true;

      // Start silence detection timer
      _resetSilenceTimer();

      debugPrint('Started recording to: $_currentRecordingPath');
      return _currentRecordingPath;
    } catch (e) {
      debugPrint('Error starting recording: $e');
      _isRecording = false;
      return null;
    }
  }

  /// Stop recording and return the file path
  Future<String?> stopRecording() async {
    if (!_isRecording) return null;

    _cancelSilenceTimer();

    try {
      final path = await _recorder.stop();
      _isRecording = false;
      debugPrint('Stopped recording: $path');
      return path;
    } catch (e) {
      debugPrint('Error stopping recording: $e');
      _isRecording = false;
      return null;
    }
  }

  /// Cancel the current recording without saving
  Future<void> cancelRecording() async {
    if (!_isRecording) return;

    _cancelSilenceTimer();

    try {
      await _recorder.stop();

      // Delete the incomplete file
      if (_currentRecordingPath != null) {
        final file = File(_currentRecordingPath!);
        if (await file.exists()) {
          await file.delete();
        }
      }
    } catch (e) {
      debugPrint('Error canceling recording: $e');
    }

    _isRecording = false;
    _currentRecordingPath = null;
  }

  /// Start streaming audio in PCM format for real-time APIs
  /// Audio is Int16 PCM Little Endian, mono
  /// sampleRate: 16000 for Gemini Live, 24000 for OpenAI Realtime
  Future<bool> startStreaming({
    Function(Uint8List)? onData,
    int sampleRate = 16000,
  }) async {
    debugPrint('MIC: startStreaming called (sampleRate=$sampleRate)');

    if (_isStreaming || _isRecording) {
      debugPrint('MIC: Stopping existing recording/streaming first');
      await stopStreaming();
      await stopRecording();
    }

    // Check permission
    if (!await hasPermission()) {
      debugPrint('MIC: No permission, requesting...');
      final granted = await requestPermission();
      if (!granted) {
        debugPrint('MIC: Permission denied!');
        return false;
      }
    }
    debugPrint('MIC: Permission OK');

    try {
      // Configure for PCM streaming - sample rate depends on the API
      final config = RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: sampleRate,
        numChannels: 1,
      );

      debugPrint('MIC: Calling _recorder.startStream...');
      final stream = await _recorder.startStream(config);
      debugPrint('MIC: Stream created successfully');

      _isStreaming = true;
      onAudioData = onData;

      int chunkCount = 0;

      _audioStreamSubscription = stream.listen(
        (data) {
          chunkCount++;
          // Log every 25 chunks to show mic is active
          if (chunkCount % 25 == 0) {
            debugPrint(
              'MIC: Received $chunkCount chunks (${data.length} bytes each)',
            );
          }
          // data is already Int16 PCM Little Endian from the record package
          final audioBytes = Uint8List.fromList(data);
          onAudioData?.call(audioBytes);
        },
        onError: (error) {
          debugPrint('MIC ERROR: Stream error: $error');
        },
        onDone: () {
          debugPrint('MIC: Stream ended (onDone)');
          _isStreaming = false;
        },
      );

      debugPrint('MIC: Streaming started successfully');
      return true;
    } catch (e) {
      debugPrint('MIC ERROR: Failed to start stream: $e');
      _isStreaming = false;
      return false;
    }
  }

  /// Stop streaming audio
  Future<void> stopStreaming() async {
    if (!_isStreaming) return;

    try {
      await _audioStreamSubscription?.cancel();
      _audioStreamSubscription = null;
      await _recorder.stop();
      _isStreaming = false;
      onAudioData = null;
      debugPrint('Stopped audio streaming');
    } catch (e) {
      debugPrint('Error stopping audio stream: $e');
      _isStreaming = false;
    }
  }

  /// Get the current amplitude (for visualization)
  /// Returns normalized amplitude 0.0-1.0, or -1.0 on timeout/error
  Future<double> getAmplitude() async {
    if (!_isRecording) {
      debugPrint('getAmplitude: NOT RECORDING - returning 0.0');
      return 0.0;
    }

    try {
      // Add timeout to prevent hanging - record package can hang on some devices
      final amplitude = await _recorder.getAmplitude().timeout(
        const Duration(milliseconds: 150),
        onTimeout: () {
          debugPrint('getAmplitude() timed out');
          return Amplitude(current: -60, max: -60);
        },
      );

      // Reset silence timer on voice activity
      if (amplitude.current > -40) {
        // Threshold for voice activity
        _resetSilenceTimer();
      }

      // Normalize amplitude for visualization (-60dB to 0dB -> 0.0 to 1.0)
      final normalized = (amplitude.current + 60) / 60;
      return normalized.clamp(0.0, 1.0);
    } catch (e) {
      debugPrint('getAmplitude() error: $e');
      return -1.0; // Signal error
    }
  }

  /// Reset the silence detection timer
  void _resetSilenceTimer() {
    _cancelSilenceTimer();
    _silenceTimer = Timer(Duration(seconds: silenceTimeoutSeconds), () {
      debugPrint('Silence detected - entering sleep mode');
      onSilenceDetected?.call();
    });
  }

  /// Cancel the silence detection timer
  void _cancelSilenceTimer() {
    _silenceTimer?.cancel();
    _silenceTimer = null;
  }

  /// Dispose resources
  Future<void> dispose() async {
    _cancelSilenceTimer();
    if (_isStreaming) {
      await stopStreaming();
    }
    if (_isRecording) {
      await stopRecording();
    }
    _recorder.dispose();
  }

  /// Get list of all recordings
  Future<List<FileSystemEntity>> getAllRecordings() async {
    final appDir = await getApplicationDocumentsDirectory();
    final recordingsDir = Directory('${appDir.path}/recordings');

    if (!await recordingsDir.exists()) {
      return [];
    }

    return recordingsDir
        .listSync()
        .where((entity) => entity.path.endsWith('.m4a'))
        .toList();
  }

  /// Delete recordings older than specified days
  Future<int> cleanupOldRecordings(int retentionDays) async {
    final recordings = await getAllRecordings();
    final cutoffDate = DateTime.now().subtract(Duration(days: retentionDays));
    int deletedCount = 0;

    for (final entity in recordings) {
      final file = File(entity.path);
      final stat = await file.stat();

      if (stat.modified.isBefore(cutoffDate)) {
        await file.delete();
        deletedCount++;
      }
    }

    debugPrint('Cleaned up $deletedCount old recordings');
    return deletedCount;
  }
}
