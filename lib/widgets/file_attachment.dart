import 'package:flutter/material.dart';

/// File attachment widget with paperclip button and preview
class FileAttachmentWidget extends StatelessWidget {
  final String? fileName;
  final VoidCallback onAttach;
  final VoidCallback onClear;

  const FileAttachmentWidget({
    super.key,
    this.fileName,
    required this.onAttach,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: fileName != null
              ? Border.all(
                  color: Theme.of(
                    context,
                  ).colorScheme.secondary.withOpacity(0.5),
                  width: 1,
                )
              : null,
        ),
        child: Row(
          children: [
            // Paperclip button
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onAttach,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  child: Icon(
                    Icons.attach_file,
                    color: fileName != null
                        ? Theme.of(context).colorScheme.secondary
                        : Colors.white54,
                    size: 20,
                  ),
                ),
              ),
            ),

            const SizedBox(width: 8),

            // File info or hint text
            Expanded(
              child: fileName != null
                  ? Row(
                      children: [
                        Icon(
                          _getFileIcon(fileName!),
                          size: 18,
                          color: Theme.of(context).colorScheme.secondary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            fileName!,
                            style: TextStyle(color: Colors.white, fontSize: 14),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    )
                  : Text(
                      'Attach PDF, image, or document',
                      style: TextStyle(color: Colors.white38, fontSize: 14),
                    ),
            ),

            // Clear button
            if (fileName != null)
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onClear,
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    child: const Icon(
                      Icons.close,
                      color: Colors.white54,
                      size: 18,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  IconData _getFileIcon(String fileName) {
    final extension = fileName.split('.').last.toLowerCase();
    switch (extension) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'png':
      case 'jpg':
      case 'jpeg':
      case 'gif':
      case 'webp':
        return Icons.image;
      case 'txt':
      case 'md':
        return Icons.description;
      default:
        return Icons.insert_drive_file;
    }
  }
}
