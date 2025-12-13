import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

/// Plays raw PCM audio chunks in real-time with smooth buffering.
/// Accumulates chunks before playing to avoid choppy audio.
class PcmAudioPlayer {
  final AudioPlayer _audioPlayer = AudioPlayer();

  // Buffer for accumulating audio chunks
  final List<int> _audioBuffer = [];
  Timer? _playbackTimer;
  bool _isPlaying = false;
  bool _audioComplete = false;

  int _sampleRate = 24000; // Default for Gemini/OpenAI
  static const int _minBufferSize =
      8000; // Minimum bytes before starting playback (~166ms at 24kHz)
  static const int _playbackInterval = 100; // Check buffer every 100ms

  VoidCallback? onPlaybackStarted;
  VoidCallback? onPlaybackComplete;

  PcmAudioPlayer() {
    _audioPlayer.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        debugPrint('PCM_PLAYER: Chunk playback completed');
        _isPlaying = false;
        _checkAndPlayNext();
      }
    });
  }

  void setSampleRate(int rate) {
    _sampleRate = rate;
    debugPrint('PCM_PLAYER: Sample rate set to $rate');
  }

  /// Add audio chunk to buffer
  void addAudioChunk(Uint8List pcmData) {
    _audioBuffer.addAll(pcmData);
    debugPrint(
      'PCM_PLAYER: Added ${pcmData.length} bytes, buffer: ${_audioBuffer.length}',
    );

    // Start playback timer if not already running
    _playbackTimer ??= Timer.periodic(
      const Duration(milliseconds: _playbackInterval),
      (_) => _checkAndPlayNext(),
    );

    // Try to play immediately if buffer is big enough
    _checkAndPlayNext();
  }

  /// Signal that all audio has been received
  void audioComplete() {
    debugPrint(
      'PCM_PLAYER: Audio complete signal received, buffer: ${_audioBuffer.length}',
    );
    _audioComplete = true;
    _checkAndPlayNext();
  }

  void _checkAndPlayNext() {
    if (_isPlaying) return;

    // Play if we have enough data OR if audio is complete and we have any data
    final shouldPlay =
        _audioBuffer.length >= _minBufferSize ||
        (_audioComplete && _audioBuffer.isNotEmpty);

    if (shouldPlay) {
      _playBuffer();
    } else if (_audioComplete && _audioBuffer.isEmpty && !_isPlaying) {
      // All done
      _playbackTimer?.cancel();
      _playbackTimer = null;
      _audioComplete = false;
      debugPrint('PCM_PLAYER: All audio played, signaling complete');
      onPlaybackComplete?.call();
    }
  }

  Future<void> _playBuffer() async {
    if (_audioBuffer.isEmpty) return;

    _isPlaying = true;

    // Take all buffered audio
    final pcmData = Uint8List.fromList(_audioBuffer);
    _audioBuffer.clear();

    debugPrint('PCM_PLAYER: Playing ${pcmData.length} bytes');

    try {
      // Convert PCM to WAV
      final wavBytes = _pcmToWav(pcmData, _sampleRate);

      // Play using just_audio
      await _audioPlayer.setAudioSource(
        _ByteAudioSource(wavBytes),
        preload: true,
      );

      onPlaybackStarted?.call();
      await _audioPlayer.play();
    } catch (e) {
      debugPrint('PCM_PLAYER: Error playing: $e');
      _isPlaying = false;
    }
  }

  /// Convert raw PCM to WAV format
  Uint8List _pcmToWav(Uint8List pcmData, int sampleRate) {
    final dataLength = pcmData.length;
    final fileLength = dataLength + 36;

    final header = ByteData(44);

    // RIFF header
    header.setUint8(0, 0x52); // R
    header.setUint8(1, 0x49); // I
    header.setUint8(2, 0x46); // F
    header.setUint8(3, 0x46); // F
    header.setUint32(4, fileLength, Endian.little);
    header.setUint8(8, 0x57); // W
    header.setUint8(9, 0x41); // A
    header.setUint8(10, 0x56); // V
    header.setUint8(11, 0x45); // E

    // fmt chunk
    header.setUint8(12, 0x66); // f
    header.setUint8(13, 0x6D); // m
    header.setUint8(14, 0x74); // t
    header.setUint8(15, 0x20); // (space)
    header.setUint32(16, 16, Endian.little); // fmt chunk size
    header.setUint16(20, 1, Endian.little); // PCM format
    header.setUint16(22, 1, Endian.little); // Mono
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, sampleRate * 2, Endian.little); // Byte rate
    header.setUint16(32, 2, Endian.little); // Block align
    header.setUint16(34, 16, Endian.little); // Bits per sample

    // data chunk
    header.setUint8(36, 0x64); // d
    header.setUint8(37, 0x61); // a
    header.setUint8(38, 0x74); // t
    header.setUint8(39, 0x61); // a
    header.setUint32(40, dataLength, Endian.little);

    // Combine header and data
    final wavFile = Uint8List(44 + dataLength);
    wavFile.setRange(0, 44, header.buffer.asUint8List());
    wavFile.setRange(44, 44 + dataLength, pcmData);

    return wavFile;
  }

  Future<void> stop() async {
    debugPrint('PCM_PLAYER: Stopping');
    _playbackTimer?.cancel();
    _playbackTimer = null;
    _audioBuffer.clear();
    _isPlaying = false;
    _audioComplete = false;
    await _audioPlayer.stop();
  }

  Future<void> dispose() async {
    await stop();
    await _audioPlayer.dispose();
  }
}

/// Custom audio source for just_audio to play from bytes
class _ByteAudioSource extends StreamAudioSource {
  final Uint8List _buffer;

  _ByteAudioSource(this._buffer);

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    start ??= 0;
    end ??= _buffer.length;
    return StreamAudioResponse(
      sourceLength: _buffer.length,
      contentLength: end - start,
      offset: start,
      stream: Stream.value(_buffer.sublist(start, end)),
      contentType: 'audio/wav',
    );
  }
}
