import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/view_constants.dart';
import '../../models/idea.dart';
import '../../viewmodels/providers/theme_provider.dart';
import '../../views/ideas/idea_vault_theme.dart';

Future<IdeaEditorSectionSheetResult?> showIdeaEditorSectionSheet(
  BuildContext context, {
  IdeaSection? section,
  required int sectionCount,
}) {
  final sheetSurface = context.read<ThemeProvider>().baseTheme.surface;
  return showModalBottomSheet<IdeaEditorSectionSheetResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: sheetSurface,
    builder: (sheetContext) {
      return _IdeaEditorSectionSheet(
        section: section,
        sectionCount: sectionCount,
      );
    },
  );
}

class _IdeaEditorSectionSheet extends StatefulWidget {
  const _IdeaEditorSectionSheet({
    required this.section,
    required this.sectionCount,
  });

  final IdeaSection? section;
  final int sectionCount;

  @override
  State<_IdeaEditorSectionSheet> createState() =>
      _IdeaEditorSectionSheetState();
}

class _IdeaEditorSectionSheetState extends State<_IdeaEditorSectionSheet> {
  late final TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    final initial = widget.section?.name ?? '';
    _nameController = TextEditingController(text: initial);
    _nameController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: initial.length,
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sheetTheme = context.watch<ThemeProvider>().baseTheme;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final isEditing = widget.section != null;
    final canDelete = isEditing && widget.sectionCount > 1;

    return Padding(
      padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            (isEditing
                    ? ViewConstants.editorSectionSheetEditTitle
                    : ViewConstants.editorSectionSheetAddTitle)
                .tr(),
            style: ideaVaultHeadline(
              context,
              size: 24,
              weight: FontWeight.w800,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            (isEditing
                    ? ViewConstants.editorSectionSheetEditBody
                    : ViewConstants.editorSectionSheetAddBody)
                .tr(),
            style: ideaVaultBody(
              context,
              size: 15,
              weight: FontWeight.w500,
              color: sheetTheme.textMuted,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 18),
          TextField(
            key: const Key('idea-editor-section-name'),
            controller: _nameController,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              hintText: ViewConstants.editorSectionSheetNameHint.tr(),
              filled: true,
              fillColor: sheetTheme.surfaceLow,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Flexible(
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    ViewConstants.editorSectionSheetCancel.tr(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ideaVaultLabel(
                      context,
                      size: 14,
                      weight: FontWeight.w700,
                      color: sheetTheme.textMuted,
                    ),
                  ),
                ),
              ),
              if (canDelete) ...[
                Flexible(
                  child: TextButton(
                    key: const Key('idea-editor-delete-section'),
                    onPressed: () => Navigator.of(context).pop(
                      const IdeaEditorSectionSheetResult.delete(),
                    ),
                    child: Text(
                      ViewConstants.editorSectionSheetDelete.tr(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ideaVaultLabel(
                        context,
                        size: 14,
                        weight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ),
              ],
              const Spacer(),
              Flexible(
                flex: 2,
                child: FilledButton(
                  key: const Key('idea-editor-create-section'),
                  style: FilledButton.styleFrom(
                    backgroundColor: sheetTheme.primary,
                    foregroundColor: sheetTheme.onPrimary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 14,
                    ),
                  ),
                  onPressed: () {
                    final nextName = _nameController.text.trim();
                    if (nextName.isEmpty) {
                      return;
                    }
                    Navigator.of(context).pop(
                      IdeaEditorSectionSheetResult.rename(nextName),
                    );
                  },
                  child: Text(
                    (isEditing
                            ? ViewConstants.editorSectionSheetSave
                            : ViewConstants.editorSectionSheetAdd)
                        .tr(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ideaVaultLabel(
                      context,
                      size: 14,
                      weight: FontWeight.w700,
                      color: sheetTheme.onPrimary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class IdeaEditorSectionSheetResult {
  const IdeaEditorSectionSheetResult.rename(this.name) : shouldDelete = false;

  const IdeaEditorSectionSheetResult.delete()
      : name = null,
        shouldDelete = true;

  final String? name;
  final bool shouldDelete;
}
