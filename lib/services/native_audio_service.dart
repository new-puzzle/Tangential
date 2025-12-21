import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Service for communicating with AudioForegroundService (native Android)
/// Handles audio streaming with proper foreground service, bluetooth support, and noise suppression
class NativeAudioService {
  static const MethodChannel _methodChannel = MethodChannel('com.tangential/audio');
  static const EventChannel _eventChannel = EventChannel('com.tangential/audio_stream');

  StreamSubscription? _audioSubscription;
  bool _isStreaming = false;
  bool _isPaused = false;

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
}
