import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:idea_vault/core/constants/view_constants.dart';
import 'package:idea_vault/core/extensions/int.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../models/idea.dart';
import '../models/premium/premium_feature.dart';
import '../viewmodels/providers/premium/paywall_view_model.dart';
import '../viewmodels/providers/theme_provider.dart';
import '../widgets/idea_vault_action_button.dart';
import '../widgets/idea_vault_subpage_app_bar.dart';
import '../widgets/translated_text.dart';
import 'ideas/idea_vault_theme.dart';

enum ExportMode {
  aiExport,
  pdfExport,
}

class ExportForAIScreen extends StatefulWidget {
  const ExportForAIScreen({
    super.key,
    required this.ideaTitle,
    required this.sections,
    required this.mode,
  });

  final String ideaTitle;
  final List<IdeaSection> sections;
  final ExportMode mode;

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
    final titleKey = switch (widget.mode) {
      ExportMode.aiExport => ViewConstants.exportForAiScreenTitle,
      ExportMode.pdfExport => ViewConstants.exportToPdfScreenTitle,
    };
    final subtitleKey = switch (widget.mode) {
      ExportMode.aiExport => ViewConstants.exportForAiScreenSubtitle,
      ExportMode.pdfExport => ViewConstants.exportToPdfScreenSubtitle,
    };
    final buttonLabelKey = switch (widget.mode) {
      ExportMode.aiExport => ViewConstants.exportForAiCopyToClipboardButton,
      ExportMode.pdfExport => ViewConstants.exportToPdfButton,
    };
    return Scaffold(
      backgroundColor: theme.background,
      appBar: IdeaVaultSubpageAppBar(titleKey: titleKey),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ReorderableListView.builder(
                padding: EdgeInsets.only(bottom: 8.h),
                header: ColoredBox(
                  color: theme.background,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(24.w, 8.h, 24.w, 18.h),
                    child: TranslatedText(
                      subtitleKey,
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
              padding: EdgeInsets.fromLTRB(24.w, 14.h, 24.w, 12.h),
              child: IdeaVaultActionButton(
                key: const Key('export-ai-copy'),
                label: buttonLabelKey,
                useTranslatedLabel: true,
                backgroundColor: theme.primary,
                foregroundColor: Colors.white,
                height: 56.h,
                onPressed: _handlePrimaryAction,
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

  Future<void> _handlePrimaryAction() async {
    switch (widget.mode) {
      case ExportMode.aiExport:
        await _copySelectedSections();
        break;
      case ExportMode.pdfExport:
        await _exportSelectedSectionsToPdf();
        break;
    }
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

    final hasAccess = await _ensurePremiumAccess(PremiumFeature.exportForAi);
    if (!hasAccess || !mounted) {
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

  Future<void> _exportSelectedSectionsToPdf() async {
    final selectedSections = _sections
        .where((section) => _selectedSectionIds.contains(section.id))
        .toList(growable: false);

    if (selectedSections.isEmpty) {
      _showMessageKey(ViewConstants.exportToPdfSnackbarSelectSection);
      return;
    }

    final hasAccess = await _ensurePremiumAccess(PremiumFeature.exportPdf);
    if (!hasAccess || !mounted) {
      return;
    }

    try {
      final markdownContent = _buildPdfMarkdown(selectedSections);
      final html = md.markdownToHtml(markdownContent);
      final styledHtml = '''
<!DOCTYPE html>
<html>
<head>
<style>
  body { font-family: Arial, sans-serif; padding: 32px; color: #1a1a1a; }
  h1 { font-size: 24px; margin-bottom: 8px; }
  h2 { font-size: 18px; margin-top: 24px; margin-bottom: 4px; }
  p { font-size: 14px; line-height: 1.6; }
  code { background: #f4f4f4; padding: 2px 6px; border-radius: 4px; }
  pre { background: #f4f4f4; padding: 12px; border-radius: 8px; }
  ul { padding-left: 20px; }
</style>
</head>
<body>$html</body>
</html>
''';

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async {
          // ignore: deprecated_member_use
          return await Printing.convertHtml(
            format: format,
            html: styledHtml,
          );
        },
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      _showMessageKey(ViewConstants.exportToPdfSnackbarFailed);
    }
  }

  Future<bool> _ensurePremiumAccess(PremiumFeature feature) async {
    try {
      return context.read<PaywallViewModel>().ensureAccess(context, feature);
    } on ProviderNotFoundException {
      return true;
    }
  }

  String _buildPdfMarkdown(List<IdeaSection> selectedSections) {
    final buffer = StringBuffer()..writeln('# ${widget.ideaTitle}');
    for (final section in selectedSections) {
      buffer
        ..writeln()
        ..writeln('## ${section.name}')
        ..write(section.content);
      if (!section.content.endsWith('\n')) {
        buffer.writeln();
      }
    }
    return buffer.toString().trimRight();
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
          padding: EdgeInsets.symmetric(vertical: 12.h, horizontal: 16.w),
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
