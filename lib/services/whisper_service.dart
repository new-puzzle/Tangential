import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// OpenAI Whisper API service for speech-to-text transcription.
/// Used for non-realtime AI modes (Gemini Flash, GPT-4o, Deepseek, Mistral).
class WhisperService {
  final Dio _dio = Dio();
  String? _apiKey;

  static const String _baseUrl = 'https://api.openai.com/v1';

  /// Set the OpenAI API key
  void setApiKey(String apiKey) {
    _apiKey = apiKey;
  }

  /// Transcribe an audio file to text
  Future<String?> transcribe(String audioFilePath) async {
    if (_apiKey == null || _apiKey!.isEmpty) {
      debugPrint('Whisper API key not set');
      return null;
    }

    final file = File(audioFilePath);
    if (!await file.exists()) {
      debugPrint('Audio file not found: $audioFilePath');
      return null;
    }

    try {
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(
          audioFilePath,
          filename: 'audio.m4a',
        ),
        'model': 'whisper-1',
        'language': 'en',
        'response_format': 'text',
        // Optional: Add timestamp granularities for word-level timing
        // 'timestamp_granularities[]': 'word',
      });

      final response = await _dio.post(
        '$_baseUrl/audio/transcriptions',
        data: formData,
        options: Options(
          headers: {'Authorization': 'Bearer $_apiKey'},
          receiveTimeout: const Duration(seconds: 60),
          sendTimeout: const Duration(seconds: 60),
        ),
      );

      if (response.statusCode == 200) {
        final transcript = response.data.toString().trim();
        debugPrint('Whisper transcription: $transcript');
        return transcript;
      } else {
        debugPrint('Whisper API error: ${response.statusCode}');
        return null;
      }
    } on DioException catch (e) {
      debugPrint('Whisper API error: ${e.message}');
      if (e.response != null) {
        debugPrint('Response: ${e.response?.data}');
      }
      return null;
    } catch (e) {
      debugPrint('Error transcribing audio: $e');
      return null;
    }
  }

  /// Transcribe audio bytes directly (useful for streaming)
  Future<String?> transcribeBytes(
    Uint8List audioBytes, {
    String format = 'm4a',
  }) async {
    if (_apiKey == null || _apiKey!.isEmpty) {
      debugPrint('Whisper API key not set');
      return null;
    }

    try {
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(audioBytes, filename: 'audio.$format'),
        'model': 'whisper-1',
        'language': 'en',
        'response_format': 'text',
      });

      final response = await _dio.post(
        '$_baseUrl/audio/transcriptions',
        data: formData,
        options: Options(
          headers: {'Authorization': 'Bearer $_apiKey'},
          receiveTimeout: const Duration(seconds: 60),
          sendTimeout: const Duration(seconds: 60),
        ),
      );

      if (response.statusCode == 200) {
        return response.data.toString().trim();
      } else {
        debugPrint('Whisper API error: ${response.statusCode}');
        return null;
      }
    } on DioException catch (e) {
      debugPrint('Whisper API error: ${e.message}');
      return null;
    } catch (e) {
      debugPrint('Error transcribing audio: $e');
      return null;
    }
  }

  /// Translate audio to English text
  Future<String?> translate(String audioFilePath) async {
    if (_apiKey == null || _apiKey!.isEmpty) {
      debugPrint('Whisper API key not set');
      return null;
    }

    final file = File(audioFilePath);
    if (!await file.exists()) {
      debugPrint('Audio file not found: $audioFilePath');
      return null;
    }

    try {
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(
          audioFilePath,
          filename: 'audio.m4a',
        ),
        'model': 'whisper-1',
        'response_format': 'text',
      });

      final response = await _dio.post(
        '$_baseUrl/audio/translations',
        data: formData,
        options: Options(
          headers: {'Authorization': 'Bearer $_apiKey'},
          receiveTimeout: const Duration(seconds: 60),
          sendTimeout: const Duration(seconds: 60),
        ),
      );

      if (response.statusCode == 200) {
        return response.data.toString().trim();
      } else {
        debugPrint('Whisper API error: ${response.statusCode}');
        return null;
      }
    } on DioException catch (e) {
      debugPrint('Whisper API error: ${e.message}');
      return null;
    } catch (e) {
      debugPrint('Error translating audio: $e');
      return null;
    }
  }
}
