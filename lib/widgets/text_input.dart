import 'package:flutter/material.dart';

/// Text input widget for typing messages instead of speaking
class TextInputWidget extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final bool enabled;

  const TextInputWidget({
    super.key,
    required this.controller,
    required this.onSend,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              enabled: enabled,
              decoration: InputDecoration(
                hintText: enabled
                    ? 'Type a message...'
                    : 'Start conversation to type',
                hintStyle: TextStyle(color: Colors.white38),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surface,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
              ),
              style: const TextStyle(color: Colors.white),
              textInputAction: TextInputAction.send,
              onSubmitted: (_) {
                if (enabled) onSend();
              },
            ),
          ),
          const SizedBox(width: 8),
          Container(
            decoration: BoxDecoration(
              color: enabled
                  ? Theme.of(context).colorScheme.primary
                  : Colors.grey.shade700,
              shape: BoxShape.circle,
            ),
            child: IconButton(
              onPressed: enabled ? onSend : null,
              icon: const Icon(Icons.send),
              color: Colors.white,
              tooltip: 'Send',
            ),
          ),
        ],
      ),
    );
  }
}
