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

  bool get isStreaming => _isStreaming;

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
    if (_isStreaming) {
      debugPrint('NativeAudio: Already streaming, stopping first');
      await stopStreaming();
      // Add small delay for cleanup
      await Future.delayed(const Duration(milliseconds: 200));
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
        },
        onDone: () {
          debugPrint('NativeAudio: Stream ended');
          _isStreaming = false;
        },
      );

      // Tell native to start foreground service
      final result = await _methodChannel.invokeMethod<bool>(
        'startAudioStream',
        {'sampleRate': sampleRate},
      );

      _isStreaming = result ?? false;
      
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
      return false;
    }
  }

  /// Stop audio streaming and foreground service
  Future<void> stopStreaming() async {
    if (!_isStreaming && _audioSubscription == null) {
      debugPrint('NativeAudio: Nothing to stop');
      return;
    }
    
    debugPrint('NativeAudio: Stopping foreground service');
    
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
      debugPrint('NativeAudio: Stopped completely');
    }
  }
}
