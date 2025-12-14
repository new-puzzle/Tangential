import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';

/// The singleton audio handler instance used throughout the app
late TangentialAudioHandler audioHandler;

/// Background audio handler for Tangential voice companion.
/// Manages foreground service, notifications, and media controls.
/// This enables the app to work with screen off and phone in pocket.
class TangentialAudioHandler extends BaseAudioHandler with SeekHandler {
  // Current state
  String _currentAiName = '';
  ConversationState _conversationState = ConversationState.idle;

  // Callbacks for UI updates
  VoidCallback? onStateChanged;
  VoidCallback? onStopRequested;
  VoidCallback? onPauseRequested;
  VoidCallback? onResumeRequested;

  /// Initialize the audio handler with audio_service
  static Future<TangentialAudioHandler> init() async {
    audioHandler = await AudioService.init(
      builder: () => TangentialAudioHandler(),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.tangential.audio',
        androidNotificationChannelName: 'Tangential Voice',
        androidNotificationChannelDescription: 'Voice companion notifications',
        androidStopForegroundOnPause:
            false, // Keep foreground service alive for pocket mode
        androidNotificationClickStartsActivity: true,
        fastForwardInterval: Duration(seconds: 10),
        rewindInterval: Duration(seconds: 10),
      ),
    );
    return audioHandler;
  }

  /// Start the foreground service and show notification
  Future<void> startConversation(String aiName) async {
    _currentAiName = aiName;
    _updateState(ConversationState.listening);

    // Set media item to show in notification
    mediaItem.add(
      MediaItem(
        id: 'tangential_conversation',
        album: 'Tangential',
        title: 'Talking with $aiName',
        artist: 'Listening...',
        artUri: null,
        playable: true,
      ),
    );

    // Set playback state with controls
    _updatePlaybackState(playing: true);
  }

  /// Update the conversation state (listening, speaking, sleeping)
  void updateConversationState(ConversationState state) {
    _updateState(state);
  }

  void _updateState(ConversationState state) {
    _conversationState = state;

    String statusText;
    switch (state) {
      case ConversationState.listening:
        statusText = 'Listening...';
        break;
      case ConversationState.speaking:
        statusText = 'Speaking...';
        break;
      case ConversationState.sleeping:
        statusText = 'Sleeping (tap to wake)';
        break;
      case ConversationState.processing:
        statusText = 'Thinking...';
        break;
      case ConversationState.idle:
        statusText = 'Ready';
        break;
    }

    // Update notification
    mediaItem.add(
      MediaItem(
        id: 'tangential_conversation',
        album: 'Tangential',
        title: 'Talking with $_currentAiName',
        artist: statusText,
        playable: true,
      ),
    );

    onStateChanged?.call();
  }

  /// Stop the conversation and remove notification
  Future<void> stopConversation() async {
    _conversationState = ConversationState.idle;
    _currentAiName = '';
    await stop();
  }

  // Media button handlers
  @override
  Future<void> play() async {
    // Resume from sleep or paused state
    _updatePlaybackState(playing: true);
    onResumeRequested?.call();
  }

  @override
  Future<void> pause() async {
    _updatePlaybackState(playing: false);
    onPauseRequested?.call();
  }

  @override
  Future<void> stop() async {
    _updatePlaybackState(playing: false);
    playbackState.add(
      playbackState.value.copyWith(processingState: AudioProcessingState.idle),
    );
    onStopRequested?.call();
  }

  void _updatePlaybackState({required bool playing}) {
    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.stop,
        ],
        systemActions: const {
          MediaAction.play,
          MediaAction.pause,
          MediaAction.stop,
        },
        androidCompactActionIndices: const [0, 1],
        processingState: AudioProcessingState.ready,
        playing: playing,
      ),
    );
  }

  // Getters
  ConversationState get conversationState => _conversationState;
  String get currentAiName => _currentAiName;
  bool get isActive => _conversationState != ConversationState.idle;
}

/// Represents the current state of the voice conversation
enum ConversationState {
  idle, // Not in a conversation
  listening, // Listening to user speech
  processing, // Processing/sending to AI
  speaking, // AI is responding via TTS
  sleeping, // Idle due to silence, waiting for wake word
}
