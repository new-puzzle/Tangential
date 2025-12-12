import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Text-to-speech service for playing AI responses.
/// Uses device TTS with queue management and interruption support.
class TtsService {
  final FlutterTts _tts = FlutterTts();

  bool _isPlaying = false;
  bool _isInitialized = false;
  final List<String> _queue = [];
  Completer<void>? _currentSpeechCompleter;

  // Callbacks
  VoidCallback? onStart;
  VoidCallback? onComplete;
  VoidCallback? onError;
  Function(String)? onProgress;

  bool get isPlaying => _isPlaying;

  /// Initialize TTS engine
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Set default language
      await _tts.setLanguage('en-US');

      // Set speech parameters for natural conversation
      await _tts.setSpeechRate(0.5); // Moderate pace
      await _tts.setPitch(1.0);
      await _tts.setVolume(1.0);

      // Set up callbacks
      _tts.setStartHandler(() {
        _isPlaying = true;
        onStart?.call();
      });

      _tts.setCompletionHandler(() {
        _isPlaying = false;
        _currentSpeechCompleter?.complete();
        _currentSpeechCompleter = null;
        onComplete?.call();
        _processQueue();
      });

      _tts.setErrorHandler((message) {
        _isPlaying = false;
        _currentSpeechCompleter?.completeError(message);
        _currentSpeechCompleter = null;
        onError?.call();
        debugPrint('TTS Error: $message');
        _processQueue();
      });

      _tts.setProgressHandler((text, start, end, word) {
        onProgress?.call(word);
      });

      // Configure for background playback
      await _tts.setIosAudioCategory(
        IosTextToSpeechAudioCategory.playback,
        [
          IosTextToSpeechAudioCategoryOptions.allowBluetooth,
          IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
          IosTextToSpeechAudioCategoryOptions.mixWithOthers,
        ],
        IosTextToSpeechAudioMode.voicePrompt,
      );

      _isInitialized = true;
      debugPrint('TTS initialized successfully');
    } catch (e) {
      debugPrint('Error initializing TTS: $e');
    }
  }

  /// Speak text immediately (interrupts current speech)
  Future<void> speak(String text) async {
    if (!_isInitialized) await initialize();
    if (text.trim().isEmpty) return;

    // Stop current speech
    await stop();

    _currentSpeechCompleter = Completer<void>();

    try {
      await _tts.speak(text);
      await _currentSpeechCompleter?.future;
    } catch (e) {
      debugPrint('Error speaking: $e');
    }
  }

  /// Add text to the speech queue
  void enqueue(String text) {
    if (text.trim().isEmpty) return;
    _queue.add(text);

    if (!_isPlaying) {
      _processQueue();
    }
  }

  /// Process the next item in the queue
  Future<void> _processQueue() async {
    if (_queue.isEmpty || _isPlaying) return;

    final text = _queue.removeAt(0);
    await speak(text);
  }

  /// Stop current speech and clear queue
  Future<void> stop() async {
    _queue.clear();

    if (_isPlaying) {
      await _tts.stop();
      _isPlaying = false;
      _currentSpeechCompleter?.complete();
      _currentSpeechCompleter = null;
    }
  }

  /// Pause current speech
  Future<void> pause() async {
    if (_isPlaying) {
      await _tts.pause();
    }
  }

  /// Get available voices
  Future<List<dynamic>> getVoices() async {
    if (!_isInitialized) await initialize();
    return await _tts.getVoices;
  }

  /// Get available languages
  Future<List<dynamic>> getLanguages() async {
    if (!_isInitialized) await initialize();
    return await _tts.getLanguages;
  }

  /// Set the voice
  Future<void> setVoice(String name, String locale) async {
    await _tts.setVoice({'name': name, 'locale': locale});
  }

  /// Set speech rate (0.0 to 1.0)
  Future<void> setSpeechRate(double rate) async {
    await _tts.setSpeechRate(rate.clamp(0.0, 1.0));
  }

  /// Set pitch (0.5 to 2.0)
  Future<void> setPitch(double pitch) async {
    await _tts.setPitch(pitch.clamp(0.5, 2.0));
  }

  /// Set volume (0.0 to 1.0)
  Future<void> setVolume(double volume) async {
    await _tts.setVolume(volume.clamp(0.0, 1.0));
  }

  /// Dispose resources
  Future<void> dispose() async {
    await stop();
    // FlutterTts doesn't have a dispose method
  }
}
