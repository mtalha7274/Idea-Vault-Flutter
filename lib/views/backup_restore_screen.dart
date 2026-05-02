import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:idea_vault/config/theme/base.dart';
import 'package:idea_vault/core/constants/view_constants.dart';
import 'package:idea_vault/core/extensions/int.dart';
import 'package:provider/provider.dart';

import '../viewmodels/providers/theme_provider.dart';
import '../widgets/idea_vault_subpage_app_bar.dart';
import '../widgets/translated_text.dart';
import 'ideas/idea_vault_theme.dart';

class BackupRestoreScreen extends StatefulWidget {
  const BackupRestoreScreen({super.key});

  @override
  State<BackupRestoreScreen> createState() => _BackupRestoreScreenState();
}

class _BackupRestoreScreenState extends State<BackupRestoreScreen> {
  static const String _previewGoogleEmail = 'talha@gmail.com';

  bool _cloudBackupEnabled = false;
  bool _autoBackupEnabled = true;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().baseTheme;

    return Scaffold(
      backgroundColor: theme.background,
      appBar: const IdeaVaultSubpageAppBar(
        titleKey: ViewConstants.backupRestoreScreenTitle,
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 520.w),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(24.w, 8.h, 24.w, 28.h),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _settingsCard(
                    theme,
                    children: [
                      _toggleRow(
                        context,
                        theme,
                        labelKey: ViewConstants.backupRestoreCloudBackup,
                        value: _cloudBackupEnabled,
                        onChanged: (v) =>
                            setState(() => _cloudBackupEnabled = v),
                      ),
                      Gap(20.h),
                      TranslatedText(
                        ViewConstants.backupRestoreGoogleAccount,
                        style: ideaVaultLabel(
                          context,
                          size: 13,
                          weight: FontWeight.w700,
                          color: theme.textMuted,
                          letterSpacing: 0.2,
                        ),
                      ),
                      Gap(8.h),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Text(
                              _previewGoogleEmail,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: ideaVaultBody(
                                context,
                                size: 16,
                                weight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Gap(12.w),
                          TextButton(
                            onPressed: () {},
                            style: TextButton.styleFrom(
                              foregroundColor: theme.primary,
                              padding: EdgeInsets.symmetric(
                                horizontal: 8.w,
                                vertical: 6.h,
                              ),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: TranslatedText(
                              ViewConstants.backupRestoreChangeAccount,
                              style: ideaVaultLabel(
                                context,
                                size: 14,
                                weight: FontWeight.w800,
                                color: theme.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Gap(20.h),
                      _toggleRow(
                        context,
                        theme,
                        labelKey: ViewConstants.backupRestoreAutoBackup,
                        value: _autoBackupEnabled,
                        onChanged: (v) =>
                            setState(() => _autoBackupEnabled = v),
                      ),
                      Gap(8.h),
                      TranslatedText(
                        ViewConstants.backupRestoreAutoBackupDescription,
                        style: ideaVaultBody(
                          context,
                          size: 14,
                          weight: FontWeight.w500,
                          color: theme.textMuted,
                          height: 1.45,
                        ),
                      ),
                      Gap(20.h),
                      _valueRow(
                        context,
                        theme,
                        labelKey: ViewConstants.backupRestoreLastBackup,
                        valueKey:
                            ViewConstants.backupRestoreLastBackupStatusSample,
                        trailing: Icon(
                          Icons.check_circle_rounded,
                          size: 22.d,
                          color: theme.primary,
                        ),
                      ),
                      Gap(16.h),
                      _valueRow(
                        context,
                        theme,
                        labelKey: ViewConstants.backupRestoreBackupSize,
                        valueKey: ViewConstants.backupRestoreBackupSizeSample,
                      ),
                    ],
                  ),
                  Gap(22.h),
                  SizedBox(
                    height: 56.h,
                    child: FilledButton(
                      onPressed: () {},
                      style: FilledButton.styleFrom(
                        backgroundColor: theme.primary,
                        foregroundColor: theme.onPrimary,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                      child: TranslatedText(
                        ViewConstants.backupRestoreBackUpNow,
                        style: ideaVaultLabel(
                          context,
                          size: 15,
                          weight: FontWeight.w800,
                          color: theme.onPrimary,
                        ),
                      ),
                    ),
                  ),
                  Gap(28.h),
                  Divider(
                    height: 1,
                    thickness: 1,
                    color: theme.outlineSoft,
                  ),
                  Gap(20.h),
                  TranslatedText(
                    ViewConstants.backupRestoreSectionRestore,
                    style: ideaVaultLabel(
                      context,
                      size: 12,
                      weight: FontWeight.w800,
                      color: theme.textMuted,
                      letterSpacing: 1.2,
                    ),
                  ),
                  Gap(14.h),
                  SizedBox(
                    height: 56.h,
                    child: OutlinedButton(
                      onPressed: () {},
                      style: OutlinedButton.styleFrom(
                        foregroundColor: theme.primaryText,
                        side: BorderSide(
                          color: theme.outline.withValues(alpha: 0.55),
                          width: 1.5,
                        ),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                      child: TranslatedText(
                        ViewConstants.backupRestoreRestoreFromBackup,
                        style: ideaVaultLabel(
                          context,
                          size: 15,
                          weight: FontWeight.w800,
                          color: theme.primaryText,
                        ),
                      ),
                    ),
                  ),
                  Gap(12.h),
                  TranslatedText(
                    ViewConstants.backupRestoreRestoreWarning,
                    textAlign: TextAlign.center,
                    style: ideaVaultBody(
                      context,
                      size: 13,
                      weight: FontWeight.w500,
                      color: theme.textMuted,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _settingsCard(BaseTheme theme, {required List<Widget> children}) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(20.r),
        border: Border.all(color: theme.outlineSoft),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(18.w, 18.h, 14.w, 18.h),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }

  Widget _toggleRow(
    BuildContext context,
    BaseTheme theme, {
    required String labelKey,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: TranslatedText(
            labelKey,
            style: ideaVaultBody(
              context,
              size: 16,
              weight: FontWeight.w600,
            ),
          ),
        ),
        CupertinoSwitch(
          value: value,
          onChanged: onChanged,
          activeTrackColor: theme.primary,
          thumbColor: theme.settings.switchThumb,
        ),
      ],
    );
  }

  Widget _valueRow(
    BuildContext context,
    BaseTheme theme, {
    required String labelKey,
    required String valueKey,
    Widget? trailing,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TranslatedText(
            labelKey,
            style: ideaVaultBody(
              context,
              size: 16,
              weight: FontWeight.w600,
            ),
          ),
        ),
        Gap(12.w),
        Flexible(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: TranslatedText(
                  valueKey,
                  textAlign: TextAlign.end,
                  style: ideaVaultBody(
                    context,
                    size: 15,
                    weight: FontWeight.w600,
                    color: theme.textMuted,
                  ),
                ),
              ),
              if (trailing != null) ...[
                Gap(8.w),
                trailing,
              ],
            ],
          ),
        ),
      ],
    );
  }
}
