import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

/// Service for recording audio from the microphone.
/// Handles permissions, recording state, and audio file management.
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

  /// Start streaming audio (for realtime modes - Gemini Live, OpenAI Realtime)
  Future<bool> startStreaming({
    Function(Uint8List)? onData,
    int sampleRate = 16000,
  }) async {
    if (_isStreaming) return true;
    if (_isRecording) await stopRecording();

    // Check permission
    if (!await hasPermission()) {
      final granted = await requestPermission();
      if (!granted) {
        debugPrint('MIC: Permission denied');
        return false;
      }
    }

    try {
      final config = RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: sampleRate,
        numChannels: 1,
      );

      final stream = await _recorder.startStream(config);
      _isStreaming = true;
      onAudioData = onData;

      _audioStreamSubscription = stream.listen(
        (data) {
          final audioBytes = Uint8List.fromList(data);
          onAudioData?.call(audioBytes);
        },
        onError: (e) {
          debugPrint('MIC: Stream error: $e');
        },
        onDone: () {
          debugPrint('MIC: Stream ended');
          _isStreaming = false;
        },
      );

      debugPrint('MIC: Streaming started at ${sampleRate}Hz');
      return true;
    } catch (e) {
      debugPrint('MIC: Error starting stream: $e');
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
      debugPrint('MIC: Streaming stopped');
    } catch (e) {
      debugPrint('MIC: Error stopping stream: $e');
      _isStreaming = false;
    }
  }

  /// Get the current amplitude (for visualization)
  Future<double> getAmplitude() async {
    if (!_isRecording) return 0.0;

    try {
      final amplitude = await _recorder.getAmplitude();

      // Reset silence timer on voice activity
      if (amplitude.current > -40) {
        // Threshold for voice activity
        _resetSilenceTimer();
      }

      // Normalize amplitude for visualization (-60dB to 0dB -> 0.0 to 1.0)
      final normalized = (amplitude.current + 60) / 60;
      return normalized.clamp(0.0, 1.0);
    } catch (e) {
      return 0.0;
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
