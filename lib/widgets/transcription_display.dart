import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../providers/app_state.dart';
import '../services/audio_handler.dart';

/// Displays the live conversation transcript
class TranscriptionDisplay extends StatelessWidget {
  final List<TranscriptEntry> entries;
  final ScrollController scrollController;
  final ConversationState conversationState;

  const TranscriptionDisplay({
    super.key,
    required this.entries,
    required this.scrollController,
    required this.conversationState,
  });

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return _buildEmptyState(context);
    }

    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount:
          entries.length +
          (conversationState != ConversationState.idle ? 1 : 0),
      itemBuilder: (context, index) {
        // Show status indicator at the end
        if (index == entries.length) {
          return _buildStatusIndicator(context);
        }

        return _buildTranscriptBubble(context, entries[index]);
      },
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.chat_bubble_outline, size: 64, color: Colors.white24),
          const SizedBox(height: 16),
          Text(
            'Select an AI and start a conversation',
            style: TextStyle(color: Colors.white54, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            'Works with screen off in your pocket',
            style: TextStyle(color: Colors.white38, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildTranscriptBubble(BuildContext context, TranscriptEntry entry) {
    final isUser = entry.speaker == 'user';
    final timeFormat = DateFormat.Hm();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            _buildAvatar(entry.provider),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isUser
                    ? Theme.of(context).colorScheme.primary.withOpacity(0.3)
                    : Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isUser ? 16 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 16),
                ),
              ),
              child: Column(
                crossAxisAlignment: isUser
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.text,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    timeFormat.format(entry.timestamp),
                    style: TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 8),
            CircleAvatar(
              radius: 14,
              backgroundColor: Theme.of(context).colorScheme.primary,
              child: const Icon(Icons.person, size: 16, color: Colors.white),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAvatar(AiProvider? provider) {
    Color color;
    IconData icon;

    switch (provider) {
      case AiProvider.gemini:
        color = const Color(0xFF4285F4);
        icon = Icons.auto_awesome;
        break;
      case AiProvider.openai:
        color = const Color(0xFF10A37F);
        icon = Icons.psychology;
        break;
      case AiProvider.deepseek:
        color = const Color(0xFF6366F1);
        icon = Icons.water_drop;
        break;
      case AiProvider.mistral:
        color = const Color(0xFFFF7000);
        icon = Icons.air;
        break;
      default:
        color = Colors.grey;
        icon = Icons.smart_toy;
    }

    return CircleAvatar(
      radius: 14,
      backgroundColor: color,
      child: Icon(icon, size: 16, color: Colors.white),
    );
  }

  Widget _buildStatusIndicator(BuildContext context) {
    String text;
    IconData icon;
    Color color;

    switch (conversationState) {
      case ConversationState.listening:
        text = 'Listening...';
        icon = Icons.hearing;
        color = Colors.green;
        break;
      case ConversationState.processing:
        text = 'Thinking...';
        icon = Icons.psychology;
        color = Colors.amber;
        break;
      case ConversationState.speaking:
        text = 'Speaking...';
        icon = Icons.volume_up;
        color = Colors.blue;
        break;
      case ConversationState.sleeping:
        text = 'Sleeping...';
        icon = Icons.bedtime;
        color = Colors.purple;
        break;
      case ConversationState.idle:
        return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildPulsingDot(color),
          const SizedBox(width: 8),
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPulsingDot(Color color) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.5, end: 1.0),
      duration: const Duration(milliseconds: 800),
      builder: (context, value, child) {
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withOpacity(value),
          ),
        );
      },
      onEnd: () {
        // This creates a continuous pulse effect
      },
    );
  }
}
