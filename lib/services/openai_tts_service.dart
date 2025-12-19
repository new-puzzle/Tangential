import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

/// OpenAI TTS service for high-quality voice synthesis.
/// Uses OpenAI's TTS API with voices: alloy, echo, fable, onyx, nova, shimmer
class OpenaiTtsService {
  String? _apiKey;
  String _voice = 'nova'; // Default to nova (female, warm)
  String _model = 'tts-1'; // tts-1 for speed, tts-1-hd for quality
  
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  final List<String> _queue = [];
  
  // Callbacks
  VoidCallback? onStart;
  VoidCallback? onComplete;
  VoidCallback? onError;

  bool get isPlaying => _isPlaying;

  void setApiKey(String apiKey) {
    _apiKey = apiKey;
  }

  void setVoice(String voice) {
    _voice = voice;
  }

  void setModel(String model) {
    _model = model;
  }

  /// Speak text using OpenAI TTS
  Future<void> speak(String text) async {
    if (_apiKey == null || _apiKey!.isEmpty) {
      debugPrint('OpenAI TTS: No API key set');
      onError?.call();
      return;
    }
    if (text.trim().isEmpty) return;

    // Stop current speech
    await stop();

    try {
      _isPlaying = true;
      onStart?.call();

      // Call OpenAI TTS API
      final response = await http.post(
        Uri.parse('https://api.openai.com/v1/audio/speech'),
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json',
        },
        body: '''
{
  "model": "$_model",
  "input": ${_escapeJson(text)},
  "voice": "$_voice",
  "response_format": "mp3"
}
''',
      );

      if (response.statusCode == 200) {
        // Save audio to temp file
        final tempDir = await getTemporaryDirectory();
        final tempFile = File('${tempDir.path}/tts_${DateTime.now().millisecondsSinceEpoch}.mp3');
        await tempFile.writeAsBytes(response.bodyBytes);

        // Play audio
        await _audioPlayer.setFilePath(tempFile.path);
        _audioPlayer.playerStateStream.listen((state) {
          if (state.processingState == ProcessingState.completed) {
            _isPlaying = false;
            onComplete?.call();
            _processQueue();
            // Clean up temp file
            tempFile.delete().ignore();
          }
        });
        await _audioPlayer.play();
      } else {
        debugPrint('OpenAI TTS error: ${response.statusCode} - ${response.body}');
        _isPlaying = false;
        onError?.call();
        _processQueue();
      }
    } catch (e) {
      debugPrint('OpenAI TTS error: $e');
      _isPlaying = false;
      onError?.call();
      _processQueue();
    }
  }

  String _escapeJson(String text) {
    return '"${text.replaceAll('\\', '\\\\').replaceAll('"', '\\"').replaceAll('\n', '\\n').replaceAll('\r', '\\r')}"';
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
      await _audioPlayer.stop();
      _isPlaying = false;
    }
  }

  /// Dispose resources
  Future<void> dispose() async {
    await stop();
    await _audioPlayer.dispose();
  }
}

