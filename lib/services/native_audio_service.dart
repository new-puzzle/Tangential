import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class NativeAudioService {
  static const MethodChannel _methodChannel = MethodChannel(
    'com.tangential/audio',
  );
  static const EventChannel _eventChannel = EventChannel(
    'com.tangential/audio_stream',
  );

  StreamSubscription? _audioSubscription;
  bool _isStreaming = false;

  bool get isStreaming => _isStreaming;

  Future<bool> startStreaming({
    required int sampleRate,
    required void Function(Uint8List) onData,
  }) async {
    try {
      // Start listening first so we don't miss initial frames.
      _audioSubscription = _eventChannel.receiveBroadcastStream().listen((
        data,
      ) {
        if (data is Uint8List) {
          onData(data);
        } else if (data is List) {
          onData(Uint8List.fromList(data.cast<int>()));
        }
      });

      final result = await _methodChannel.invokeMethod<bool>(
        'startAudioStream',
        {'sampleRate': sampleRate},
      );

      _isStreaming = result ?? false;
      if (!_isStreaming) {
        await _audioSubscription?.cancel();
        _audioSubscription = null;
      }

      return _isStreaming;
    } catch (e) {
      debugPrint('Error starting native audio: $e');
      await _audioSubscription?.cancel();
      _audioSubscription = null;
      _isStreaming = false;
      return false;
    }
  }

  Future<void> stopStreaming() async {
    try {
      await _methodChannel.invokeMethod('stopAudioStream');
    } catch (e) {
      debugPrint('Error stopping native audio: $e');
    } finally {
      await _audioSubscription?.cancel();
      _audioSubscription = null;
      _isStreaming = false;
    }
  }
}
