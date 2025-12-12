import 'package:flutter/material.dart';
import '../providers/app_state.dart';

/// Button for selecting an AI provider with optional mode toggle
class AiButton extends StatelessWidget {
  final AiProvider provider;
  final bool isSelected;
  final VoidCallback onTap;
  final AiMode? mode;
  final Function(AiMode)? onModeChanged;
  final bool showModeToggle;
  final Color color;

  const AiButton({
    super.key,
    required this.provider,
    required this.isSelected,
    required this.onTap,
    this.mode,
    this.onModeChanged,
    this.showModeToggle = false,
    required this.color,
  });

  String get _providerName {
    switch (provider) {
      case AiProvider.gemini:
        return 'Gemini';
      case AiProvider.openai:
        return 'OpenAI';
      case AiProvider.deepseek:
        return 'Deepseek';
      case AiProvider.mistral:
        return 'Mistral';
    }
  }

  IconData get _providerIcon {
    switch (provider) {
      case AiProvider.gemini:
        return Icons.auto_awesome;
      case AiProvider.openai:
        return Icons.psychology;
      case AiProvider.deepseek:
        return Icons.water_drop;
      case AiProvider.mistral:
        return Icons.air;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Main button
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
              decoration: BoxDecoration(
                color: isSelected
                    ? color.withOpacity(0.2)
                    : Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isSelected ? color : Colors.transparent,
                  width: 2,
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: color.withOpacity(0.3),
                          blurRadius: 12,
                          spreadRadius: 0,
                        ),
                      ]
                    : null,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _providerIcon,
                    color: isSelected ? color : Colors.white70,
                    size: 24,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _providerName,
                    style: TextStyle(
                      color: isSelected ? color : Colors.white70,
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // Mode toggle (only for Gemini and OpenAI)
        if (showModeToggle && isSelected) ...[
          const SizedBox(height: 8),
          _buildModeToggle(context),
        ],
      ],
    );
  }

  Widget _buildModeToggle(BuildContext context) {
    final isLive = mode == AiMode.live;

    String liveLabel;
    String standardLabel;

    switch (provider) {
      case AiProvider.gemini:
        liveLabel = 'Live';
        standardLabel = 'Flash';
        break;
      case AiProvider.openai:
        liveLabel = 'Realtime';
        standardLabel = 'GPT-4o';
        break;
      default:
        return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildModeOption(
            context,
            label: liveLabel,
            isActive: isLive,
            onTap: () => onModeChanged?.call(AiMode.live),
          ),
          const SizedBox(width: 4),
          _buildModeOption(
            context,
            label: standardLabel,
            isActive: !isLive,
            onTap: () => onModeChanged?.call(AiMode.standard),
          ),
        ],
      ),
    );
  }

  Widget _buildModeOption(
    BuildContext context, {
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? color : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? Colors.white : Colors.white54,
            fontSize: 12,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
