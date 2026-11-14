import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';

import '../../core/constants/view_constants.dart';

Future<bool?> showDeleteIdeasConfirmationDialog(
  BuildContext context, {
  required int selectedCount,
}) {
  return showSelectionDeleteConfirmationDialog(
    context,
    title: selectedCount == 1
        ? ViewConstants.selectionDeleteIdeaTitleOne.tr()
        : ViewConstants.selectionDeleteIdeasTitleMany.tr(
            namedArgs: {'count': '$selectedCount'},
          ),
    body: selectedCount == 1
        ? ViewConstants.selectionDeleteIdeaBodyOne.tr()
        : ViewConstants.selectionDeleteIdeasBodyMany.tr(
            namedArgs: {'count': '$selectedCount'},
          ),
    confirmKey: const Key('ideas-delete-confirm'),
  );
}

Future<bool?> showSelectionDeleteConfirmationDialog(
  BuildContext context, {
  required String title,
  required String body,
  required Key confirmKey,
}) {
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(ViewConstants.cancel.tr()),
          ),
          FilledButton(
            key: confirmKey,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(ViewConstants.selectionDeleteConfirm.tr()),
          ),
        ],
      );
    },
  );
}
