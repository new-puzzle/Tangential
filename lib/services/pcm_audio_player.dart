import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

/// Real-time PCM audio player for Gemini Live and OpenAI Realtime responses.
/// Converts raw PCM Int16 audio to playable format.
class PcmAudioPlayer {
  final AudioPlayer _player = AudioPlayer();
  final List<int> _audioBuffer = [];
  Timer? _playbackTimer;
  bool _isPlaying = false;
  int _sampleRate;
  
  // Callbacks
  VoidCallback? onPlaybackStarted;
  VoidCallback? onPlaybackComplete;

  PcmAudioPlayer({int sampleRate = 24000}) : _sampleRate = sampleRate;

  void setSampleRate(int rate) {
    _sampleRate = rate;
  }

  /// Add PCM audio chunk to buffer
  void addAudioChunk(Uint8List chunk) {
    _audioBuffer.addAll(chunk);
    
    // Start playing when we have enough audio (about 2 seconds worth)
    // This reduces choppiness by buffering more before starting
    // 24000 Hz * 2 bytes * 2 sec = 96000 bytes
    final minBuffer = _sampleRate * 4; // 2 seconds of audio
    if (!_isPlaying && _audioBuffer.length > minBuffer) {
      _startPlayback();
    }
  }

  /// Signal that the audio stream is complete
  void audioComplete() {
    // Play any remaining buffered audio
    if (_audioBuffer.isNotEmpty && !_isPlaying) {
      _startPlayback();
    }
  }

  Future<void> _startPlayback() async {
    if (_audioBuffer.isEmpty) return;
    
    _isPlaying = true;
    onPlaybackStarted?.call();
    
    try {
      // Take current buffer and clear it
      final audioData = Uint8List.fromList(_audioBuffer);
      _audioBuffer.clear();
      
      // Convert PCM to WAV
      final wavData = _pcmToWav(audioData, _sampleRate);
      
      // Create audio source and play
      final source = _WavAudioSource(wavData);
      await _player.setAudioSource(source);
      await _player.play();
      
      // Wait for playback to complete
      await _player.playerStateStream.firstWhere(
        (state) => state.processingState == ProcessingState.completed,
      );
      
      debugPrint('PCM playback completed (${audioData.length} bytes)');
    } catch (e) {
      debugPrint('PCM playback error: $e');
    } finally {
      _isPlaying = false;
      
      // Check if more audio arrived while playing
      if (_audioBuffer.isNotEmpty) {
        _startPlayback();
      } else {
        onPlaybackComplete?.call();
      }
    }
  }

  /// Convert raw PCM Int16 data to WAV format
  Uint8List _pcmToWav(Uint8List pcmData, int sampleRate) {
    const int channels = 1;
    const int bitsPerSample = 16;
    final int byteRate = sampleRate * channels * (bitsPerSample ~/ 8);
    final int blockAlign = channels * (bitsPerSample ~/ 8);
    
    final wavHeader = ByteData(44);
    
    // RIFF header
    wavHeader.setUint8(0, 0x52); // 'R'
    wavHeader.setUint8(1, 0x49); // 'I'
    wavHeader.setUint8(2, 0x46); // 'F'
    wavHeader.setUint8(3, 0x46); // 'F'
    wavHeader.setUint32(4, 36 + pcmData.length, Endian.little); // File size - 8
    wavHeader.setUint8(8, 0x57);  // 'W'
    wavHeader.setUint8(9, 0x41);  // 'A'
    wavHeader.setUint8(10, 0x56); // 'V'
    wavHeader.setUint8(11, 0x45); // 'E'
    
    // fmt chunk
    wavHeader.setUint8(12, 0x66); // 'f'
    wavHeader.setUint8(13, 0x6D); // 'm'
    wavHeader.setUint8(14, 0x74); // 't'
    wavHeader.setUint8(15, 0x20); // ' '
    wavHeader.setUint32(16, 16, Endian.little); // Subchunk1Size (16 for PCM)
    wavHeader.setUint16(20, 1, Endian.little);  // AudioFormat (1 = PCM)
    wavHeader.setUint16(22, channels, Endian.little);
    wavHeader.setUint32(24, sampleRate, Endian.little);
    wavHeader.setUint32(28, byteRate, Endian.little);
    wavHeader.setUint16(32, blockAlign, Endian.little);
    wavHeader.setUint16(34, bitsPerSample, Endian.little);
    
    // data chunk
    wavHeader.setUint8(36, 0x64); // 'd'
    wavHeader.setUint8(37, 0x61); // 'a'
    wavHeader.setUint8(38, 0x74); // 't'
    wavHeader.setUint8(39, 0x61); // 'a'
    wavHeader.setUint32(40, pcmData.length, Endian.little);
    
    // Combine header and data
    final wavFile = Uint8List(44 + pcmData.length);
    wavFile.setAll(0, wavHeader.buffer.asUint8List());
    wavFile.setAll(44, pcmData);
    
    return wavFile;
  }

  /// Stop playback and clear buffer
  Future<void> stop() async {
    _playbackTimer?.cancel();
    _audioBuffer.clear();
    await _player.stop();
    _isPlaying = false;
  }

  /// Clear the audio buffer without stopping current playback
  void clearBuffer() {
    _audioBuffer.clear();
  }

  bool get isPlaying => _isPlaying;
  int get bufferedBytes => _audioBuffer.length;

  void dispose() {
    _playbackTimer?.cancel();
    _player.dispose();
  }
}

/// Custom audio source for playing WAV data from memory
class _WavAudioSource extends StreamAudioSource {
  final Uint8List _wavData;

  _WavAudioSource(this._wavData);

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    start ??= 0;
    end ??= _wavData.length;
    
    return StreamAudioResponse(
      sourceLength: _wavData.length,
      contentLength: end - start,
      offset: start,
      stream: Stream.value(_wavData.sublist(start, end)),
      contentType: 'audio/wav',
    );
  }
}

