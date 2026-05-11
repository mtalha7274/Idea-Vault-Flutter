import 'package:flutter/material.dart';

Future<bool?> showDeleteIdeasConfirmationDialog(
  BuildContext context, {
  required int selectedCount,
}) {
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final title =
          selectedCount == 1 ? 'Delete selected idea?' : 'Delete ideas?';
      final body = selectedCount == 1
          ? 'This idea will be removed from your vault.'
          : '$selectedCount ideas will be removed from your vault.';

      return AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('ideas-delete-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      );
    },
  );
}
