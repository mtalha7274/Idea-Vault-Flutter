import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:idea_vault/core/constants/view_constants.dart';
import 'package:idea_vault/core/extensions/int.dart';
import 'package:provider/provider.dart';

import '../models/idea.dart';
import '../viewmodels/providers/theme_provider.dart';
import '../widgets/idea_vault_action_button.dart';
import '../widgets/translated_text.dart';
import 'ideas/idea_vault_theme.dart';

class ExportForAIScreen extends StatefulWidget {
  const ExportForAIScreen({
    super.key,
    required this.ideaTitle,
    required this.sections,
  });

  final String ideaTitle;
  final List<IdeaSection> sections;

  @override
  State<ExportForAIScreen> createState() => _ExportForAIScreenState();
}

class _ExportForAIScreenState extends State<ExportForAIScreen> {
  late List<IdeaSection> _sections;
  late Set<String> _selectedSectionIds;

  @override
  void initState() {
    super.initState();
    _sections = widget.sections.map((section) => section.copyWith()).toList();
    _selectedSectionIds = _sections.map((section) => section.id).toSet();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        backgroundColor: theme.background,
        foregroundColor: theme.primaryText,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        leadingWidth: 52.w,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 18.d,
          ),
          padding: EdgeInsets.all(10.d),
          splashRadius: 20.d,
          visualDensity: VisualDensity.compact,
        ),
        title: TranslatedText(
          ViewConstants.exportForAiScreenTitle,
          style: ideaVaultHeadline(
            context,
            size: 20,
            weight: FontWeight.w800,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ColoredBox(
              color: theme.background,
              child: Padding(
                padding:
                    EdgeInsets.fromLTRB(24.w, 8.h, 24.w, 18.h),
                child: TranslatedText(
                  ViewConstants.exportForAiScreenSubtitle,
                  style: ideaVaultBody(
                    context,
                    size: 15,
                    weight: FontWeight.w500,
                    color: theme.textMuted,
                    height: 1.45,
                  ),
                ),
              ),
            ),
            Expanded(
              child: ReorderableListView.builder(
                padding: EdgeInsets.only(bottom: 8.h),
                buildDefaultDragHandles: false,
                proxyDecorator: (child, index, animation) => Material(
                  color: Colors.transparent,
                  child: child,
                ),
                itemCount: _sections.length,
                onReorder: _handleReorder,
                itemBuilder: (context, index) {
                  final section = _sections[index];
                  final isSelected = _selectedSectionIds.contains(section.id);
                  return _ExportSectionTile(
                    key: ValueKey(section.id),
                    section: section,
                    index: index,
                    isSelected: isSelected,
                    onTap: () => _toggleSection(section.id),
                  );
                },
              ),
            ),
            Padding(
              padding:
                  EdgeInsets.fromLTRB(24.w, 14.h, 24.w, 12.h),
              child: IdeaVaultActionButton(
                key: const Key('export-ai-copy'),
                label: ViewConstants.exportForAiCopyToClipboardButton,
                useTranslatedLabel: true,
                backgroundColor: theme.primary,
                foregroundColor: Colors.white,
                height: 56.h,
                onPressed: _copySelectedSections,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleReorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) {
        newIndex -= 1;
      }
      final section = _sections.removeAt(oldIndex);
      _sections.insert(newIndex, section);
    });
  }

  void _toggleSection(String sectionId) {
    setState(() {
      if (_selectedSectionIds.contains(sectionId)) {
        _selectedSectionIds.remove(sectionId);
      } else {
        _selectedSectionIds.add(sectionId);
      }
    });
  }

  Future<void> _copySelectedSections() async {
    final selectedSections = _sections
        .where((section) => _selectedSectionIds.contains(section.id))
        .toList(growable: false);

    if (selectedSections.isEmpty) {
      _showMessageKey(ViewConstants.exportForAiSnackbarSelectSection);
      return;
    }

    final buffer = StringBuffer()
      ..writeln(
        ViewConstants.exportForAiClipboardIdeaLine.tr(
          namedArgs: {'title': widget.ideaTitle},
        ),
      );
    for (final section in selectedSections) {
      buffer
        ..writeln()
        ..writeln(section.name)
        ..write(section.content);
      if (!section.content.endsWith('\n')) {
        buffer.writeln();
      }
    }

    await Clipboard.setData(ClipboardData(text: buffer.toString().trimRight()));
    if (!mounted) {
      return;
    }
    _showMessageKey(ViewConstants.exportForAiSnackbarCopied);
  }

  void _showMessageKey(String key, {Map<String, String>? namedArgs}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: TranslatedText(
          key,
          namedArgs: namedArgs,
        ),
      ),
    );
  }
}

class _ExportSectionTile extends StatelessWidget {
  const _ExportSectionTile({
    super.key,
    required this.section,
    required this.index,
    required this.isSelected,
    required this.onTap,
  });

  final IdeaSection section;
  final int index;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;
    final firstLine = _firstContentLine(section.content);
    final themeMuted = theme.textMuted;
    return Material(
      color: theme.surface,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding:
              EdgeInsets.symmetric(vertical: 12.h, horizontal: 16.w),
          child: Row(
            children: [
              Checkbox(
                value: isSelected,
                onChanged: (_) => onTap(),
              ),
              SizedBox(width: 8.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      section.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ideaVaultLabel(
                        context,
                        size: 15,
                        weight: FontWeight.w800,
                        color: theme.primaryText,
                      ),
                    ),
                    SizedBox(height: 4.h),
                    firstLine == null
                        ? TranslatedText(
                            ViewConstants.exportForAiSectionNoContentYet,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: ideaVaultBody(
                              context,
                              size: 13,
                              weight: FontWeight.w500,
                              color: themeMuted,
                            ),
                          )
                        : Text(
                            firstLine,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: ideaVaultBody(
                              context,
                              size: 13,
                              weight: FontWeight.w500,
                              color: themeMuted,
                            ),
                          ),
                  ],
                ),
              ),
              ReorderableDragStartListener(
                index: index,
                child: Padding(
                  padding: EdgeInsets.all(8.d),
                  child: Icon(
                    Icons.drag_handle_rounded,
                    color: theme.textMuted,
                    size: 24.d,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? _firstContentLine(String content) {
    final lines = content.split('\n');
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty) {
        return trimmed;
      }
    }
    return null;
  }
}
