class ViewConstants {
  // Error Messages
  static const String noInternet = 'noInternet';
  static const String serverError = 'serverError';
  static const String invalidResponse = 'invalidResponse';
  static const String errorOpeningCamera = 'errorOpeningCamera';
  static const String cameraAccessDenied = 'cameraAccessDenied';

  // Info Messages
  static const String noEmailAppAvailable = "noEmailAppAvailable";

  // Constants
  static const String newVersionTitle = 'newVersionTitle';
  static const String newVersionDescription = 'newVersionDescription';
  static const String update = 'update';
  static const String skip = 'skip';
  static const String watchAd = 'watchAd';
  static const String watchAdDescription = 'watchAdDescription';
  static const String watchAdDescription1 = 'watchAdDescription1';
  static const String watchAdDescription2 = 'watchAdDescription2';
  static const String continueButton = 'continueButton';
  static const String cancel = 'cancel';
  static const String privacyPolicy = "privacyPolicy";
  static const String termsAndConditions = "termsAndConditions";
  static const String rateApp = "rateApp";
  static const String shareApp = "shareApp";
  static const String contactUs = "contactUs";
  static const String settings = "settings";
  static const String settingsAppearance = "settingsAppearance";
  static const String settingsThemeLight = "settingsThemeLight";
  static const String settingsThemeDark = "settingsThemeDark";
  static const String settingsThemeDescription = "settingsThemeDescription";
  static const String home = "home";
  static const String search = "search";
  static const String more = "more";
  static const String cropImage = "cropImage";
  static const String requestTimeout = "requestTimeout";

  /// `{limit}` = formatted warning character count (keep in sync with [ideaSectionAiWarningCharacterLimit]).
  static const String organizeOverLimitDialogBody =
      'organizeOverLimitDialogBody';

  /// `{limit}` = formatted max character count (keep in sync with backend / [ideaSectionAiMaxCharacterLimit]).
  static const String organizeMaxLimitDialogBody = 'organizeMaxLimitDialogBody';

  static const String organizeSectionSheetTitle = 'organizeSectionSheetTitle';
  static const String organizeSectionSheetDescription =
      'organizeSectionSheetDescription';
  static const String organizeSectionSheetConfirmButton =
      'organizeSectionSheetConfirmButton';

  static const String organizeToolbarAiBadge = 'organizeToolbarAiBadge';

  static const String brainstorm = 'brainstorm';

  static const String ideaEditorTitleEdit = 'ideaEditorTitleEdit';
  static const String ideaEditorTitleNew = 'ideaEditorTitleNew';

  static const String paywallTitle = 'paywallTitle';
  static const String paywallSubtitle = 'paywallSubtitle';
  static const String paywallProUnlocks = 'paywallProUnlocks';
  static const String paywallFeatureAiOrganize = 'paywallFeatureAiOrganize';
  static const String paywallFeatureAiBrainstorm = 'paywallFeatureAiBrainstorm';
  static const String paywallFeatureSpeechToText = 'paywallFeatureSpeechToText';
  static const String paywallFeatureImageToText = 'paywallFeatureImageToText';
  static const String paywallFeatureCloudBackup = 'paywallFeatureCloudBackup';
  static const String paywallFeatureExportPdf = 'paywallFeatureExportPdf';
  static const String paywallFeatureEarlyAccess = 'paywallFeatureEarlyAccess';
  static const String paywallFeaturePrioritySupport =
      'paywallFeaturePrioritySupport';
  static const String paywallPlanYearly = 'paywallPlanYearly';
  static const String paywallYearlyHeadlinePrice = 'paywallYearlyHeadlinePrice';
  static const String paywallYearlyPriceLine = 'paywallYearlyPriceLine';
  static const String paywallYearlySubtitle = 'paywallYearlySubtitle';
  static const String paywallTrialLabel = 'paywallTrialLabel';
  static const String paywallBadgeSave = 'paywallBadgeSave';
  static const String paywallBadgeMostPopular = 'paywallBadgeMostPopular';
  static const String paywallPlanMonthly = 'paywallPlanMonthly';
  static const String paywallMonthlyPriceLine = 'paywallMonthlyPriceLine';
  static const String paywallMonthlySubtitle = 'paywallMonthlySubtitle';
  static const String paywallFooterYearly = 'paywallFooterYearly';
  static const String paywallFooterMonthly = 'paywallFooterMonthly';
  static const String paywallCtaStartTrial = 'paywallCtaStartTrial';
  static const String paywallCtaGetMonthly = 'paywallCtaGetMonthly';
  static const String paywallCtaSubscribeYearly = 'paywallCtaSubscribeYearly';
  static const String paywallFooterYearlyNoTrial = 'paywallFooterYearlyNoTrial';
  static const String paywallCloseTooltip = 'paywallCloseTooltip';
  static const String paywallComingSoon = 'paywallComingSoon';
  static const String paywallRestorePurchases = 'paywallRestorePurchases';
  static const String paywallTermsOfService = 'paywallTermsOfService';
  static const String paywallFooterDot = 'paywallFooterDot';

  static const String exportForAiScreenTitle = 'exportForAiScreenTitle';
  static const String exportToPdfScreenTitle = 'exportToPdfScreenTitle';
  static const String exportForAiScreenSubtitle = 'exportForAiScreenSubtitle';
  static const String exportToPdfScreenSubtitle = 'exportToPdfScreenSubtitle';
  static const String exportForAiCopyToClipboardButton =
      'exportForAiCopyToClipboardButton';
  static const String exportToPdfButton = 'exportToPdfButton';
  static const String exportForAiSnackbarSelectSection =
      'exportForAiSnackbarSelectSection';
  static const String exportToPdfSnackbarSelectSection =
      'exportToPdfSnackbarSelectSection';
  static const String exportToPdfSnackbarFailed = 'exportToPdfSnackbarFailed';
  static const String exportForAiSnackbarCopied = 'exportForAiSnackbarCopied';
  static const String exportForAiClipboardIdeaLine =
      'exportForAiClipboardIdeaLine';
  static const String exportForAiSectionNoContentYet =
      'exportForAiSectionNoContentYet';

  static const String ideaEditorOptionsSheetTitle =
      'ideaEditorOptionsSheetTitle';
  static const String ideaEditorOptionsDeleteIdea =
      'ideaEditorOptionsDeleteIdea';
  static const String ideaEditorOptionsLockNote = 'ideaEditorOptionsLockNote';
  static const String ideaEditorOptionsUnlockNote =
      'ideaEditorOptionsUnlockNote';
  static const String noteLockCreatePinTitle = 'noteLockCreatePinTitle';
  static const String noteLockCreatePinBody = 'noteLockCreatePinBody';
  static const String noteLockConfirmPinTitle = 'noteLockConfirmPinTitle';
  static const String noteLockConfirmPinBody = 'noteLockConfirmPinBody';
  static const String noteLockEnterPinTitle = 'noteLockEnterPinTitle';
  static const String noteLockPinLabel = 'noteLockPinLabel';
  static const String noteLockConfirmPinLabel = 'noteLockConfirmPinLabel';
  static const String noteLockCreatePinAction = 'noteLockCreatePinAction';
  static const String noteLockPinTooShort = 'noteLockPinTooShort';
  static const String noteLockPinMismatch = 'noteLockPinMismatch';
  static const String noteLockUnlockTitle = 'noteLockUnlockTitle';
  static const String noteLockUnlockBody = 'noteLockUnlockBody';
  static const String noteLockWrongPin = 'noteLockWrongPin';
  static const String noteLockUnlockAction = 'noteLockUnlockAction';
  static const String noteLockUseBiometric = 'noteLockUseBiometric';
  static const String noteLockBiometricReason = 'noteLockBiometricReason';
  static const String noteLockEnableBiometricTitle = 'noteLockEnableBiometricTitle';
  static const String noteLockEnableBiometricBody = 'noteLockEnableBiometricBody';
  static const String noteLockEnableBiometricAction = 'noteLockEnableBiometricAction';
  static const String noteLockEnableBiometricUnlockAction =
      'noteLockEnableBiometricUnlockAction';
  static const String noteLockEnableBiometricSkip = 'noteLockEnableBiometricSkip';
  static const String noteLockEnableBiometricReason = 'noteLockEnableBiometricReason';
  static const String noteLockEditorTitle = 'noteLockEditorTitle';
  static const String noteLockEditorBody = 'noteLockEditorBody';
  static const String noteLockEditorAction = 'noteLockEditorAction';
  static const String noteLockEditorBackAction = 'noteLockEditorBackAction';
  static const String noteLockLockedSnackbar = 'noteLockLockedSnackbar';
  static const String noteLockUnlockedSnackbar = 'noteLockUnlockedSnackbar';
  static const String noteLockVerifyCurrentPinTitle =
      'noteLockVerifyCurrentPinTitle';
  static const String noteLockVerifyCurrentPinBody =
      'noteLockVerifyCurrentPinBody';
  static const String noteLockNewPinTitle = 'noteLockNewPinTitle';
  static const String noteLockNewPinBody = 'noteLockNewPinBody';
  static const String noteLockChangePinSuccess = 'noteLockChangePinSuccess';
  static const String settingsChangePin = 'settingsChangePin';

  static const String homepageSavedIdeasTooltipOne =
      'homepageSavedIdeasTooltipOne';
  static const String homepageSavedIdeasTooltipMany =
      'homepageSavedIdeasTooltipMany';

  static const String homepageTitle = 'homepageTitle';

  static const String backupRestoreScreenTitle = 'backupRestoreScreenTitle';
  static const String backupRestoreCloudBackup = 'backupRestoreCloudBackup';
  static const String backupRestoreGoogleAccount = 'backupRestoreGoogleAccount';
  static const String backupRestoreChangeAccount = 'backupRestoreChangeAccount';
  static const String backupRestoreAutoBackup = 'backupRestoreAutoBackup';
  static const String backupRestoreAutoBackupDescription =
      'backupRestoreAutoBackupDescription';
  static const String backupRestoreLastBackup = 'backupRestoreLastBackup';
  static const String backupRestoreBackupSize = 'backupRestoreBackupSize';
  static const String backupRestoreBackUpNow = 'backupRestoreBackUpNow';
  static const String backupRestoreSectionRestore =
      'backupRestoreSectionRestore';
  static const String backupRestoreRestoreFromBackup =
      'backupRestoreRestoreFromBackup';
  static const String backupRestoreRestoreWarning =
      'backupRestoreRestoreWarning';

  static const String homepageFabNewIdea = 'homepageFabNewIdea';
  static const String homepageSortSheetTitle = 'homepageSortSheetTitle';
  static const String homepageSortSheetSubtitle = 'homepageSortSheetSubtitle';
  static const String homepageSortNewestFirst = 'homepageSortNewestFirst';
  static const String homepageSortOldestFirst = 'homepageSortOldestFirst';
  static const String homepageSortMostSections = 'homepageSortMostSections';
  static const String homepageSwitchToGridTooltip =
      'homepageSwitchToGridTooltip';
  static const String homepageSwitchToListTooltip =
      'homepageSwitchToListTooltip';
  static const String homepageGetIdeaVaultPro = 'homepageGetIdeaVaultPro';
  static const String homepageBackupOffIndicator = 'homepageBackupOffIndicator';
  static const String homepageBackupOffAction = 'homepageBackupOffAction';
  static const String freeUsageDrawerTitle = 'freeUsageDrawerTitle';
  static const String freeUsageScreenTitle = 'freeUsageScreenTitle';
  static const String freeUsageScreenBody = 'freeUsageScreenBody';
  static const String freeUsageScreenAction = 'freeUsageScreenAction';
  static const String freeUsageScreenDrawerTitle = 'freeUsageScreenDrawerTitle';
  static const String freeUsageScreenDrawerBody = 'freeUsageScreenDrawerBody';
  static const String freeUsageScreenDrawerAction =
      'freeUsageScreenDrawerAction';
  static const String freeUsageCurrentUsageTitle = 'freeUsageCurrentUsageTitle';
  static const String freeUsageProgressSemantic = 'freeUsageProgressSemantic';
  static const String homepageEmptyTitle = 'homepageEmptyTitle';
  static const String homepageEmptySubtitle = 'homepageEmptySubtitle';
  static const String homepageIdeaCardOneSection = 'homepageIdeaCardOneSection';
  static const String homepageIdeaCardSectionsMany =
      'homepageIdeaCardSectionsMany';
  static const String homepageIdeaCardUpdatedToday =
      'homepageIdeaCardUpdatedToday';
  static const String homepageIdeaCardUpdatedYesterday =
      'homepageIdeaCardUpdatedYesterday';
  static const String homepageIdeaCardUpdatedOnDate =
      'homepageIdeaCardUpdatedOnDate';
  static const String homepageSearchHint = 'homepageSearchHint';
  static const String homepageNoSearchResults = 'homepageNoSearchResults';
  static const String homepageMenuChangeLayout = 'homepageMenuChangeLayout';
  static const String homepageMenuFilter = 'homepageMenuFilter';
  static const String searchIdeasScreenTitle = 'searchIdeasScreenTitle';
  static const String searchIdeasEmptyTitle = 'searchIdeasEmptyTitle';
  static const String searchIdeasEmptyPrompt = 'searchIdeasEmptyPrompt';
  static const String homepageIdeaCardPreviewPlaceholder =
      'homepageIdeaCardPreviewPlaceholder';

  static const String randomAdditionsTitle = 'randomAdditionsTitle';
  static const String randomAdditionsCountOne = 'randomAdditionsCountOne';
  static const String randomAdditionsCountMany = 'randomAdditionsCountMany';
  static const String randomAdditionsComposerHint =
      'randomAdditionsComposerHint';
  static const String randomAdditionsSendTooltip = 'randomAdditionsSendTooltip';
  static const String randomAdditionsFileTooltip = 'randomAdditionsFileTooltip';
  static const String randomAdditionsEmptyTitle = 'randomAdditionsEmptyTitle';
  static const String randomAdditionsEmptySubtitle =
      'randomAdditionsEmptySubtitle';
  static const String randomAdditionsChooseIdeaTitle =
      'randomAdditionsChooseIdeaTitle';
  static const String randomAdditionsChooseSectionTitle =
      'randomAdditionsChooseSectionTitle';
  static const String randomAdditionsAppendToSection =
      'randomAdditionsAppendToSection';
  static const String randomAdditionsNoIdeasTitle =
      'randomAdditionsNoIdeasTitle';
  static const String randomAdditionsNoIdeasSubtitle =
      'randomAdditionsNoIdeasSubtitle';
  static const String randomAdditionsFiledSnackbar =
      'randomAdditionsFiledSnackbar';

  static const String ideaEditorUntitledIdea = 'ideaEditorUntitledIdea';
  static const String ideaEditorTitleHint = 'ideaEditorTitleHint';
  static const String ideaEditorListening = 'ideaEditorListening';
  static const String ideaEditorAddSectionTooltip =
      'ideaEditorAddSectionTooltip';
  static const String ideaEditorPlaceholderDefaultSection =
      'ideaEditorPlaceholderDefaultSection';
  static const String ideaEditorPlaceholderNamedSection =
      'ideaEditorPlaceholderNamedSection';
  static const String ideaEditorSnackbarNothingToOrganize =
      'ideaEditorSnackbarNothingToOrganize';
  static const String ideaEditorSnackbarOrganizeFailed =
      'ideaEditorSnackbarOrganizeFailed';
  static const String ideaEditorSnackbarSpeechStopped =
      'ideaEditorSnackbarSpeechStopped';
  static const String ideaEditorSnackbarSpeechUnavailable =
      'ideaEditorSnackbarSpeechUnavailable';
  static const String ideaEditorImageTextTakePhoto =
      'ideaEditorImageTextTakePhoto';
  static const String ideaEditorImageTextChoosePhoto =
      'ideaEditorImageTextChoosePhoto';
  static const String ideaEditorImageTextReading = 'ideaEditorImageTextReading';
  static const String ideaEditorImageTextPreparing =
      'ideaEditorImageTextPreparing';
  static const String ideaEditorImageTextTooltip = 'ideaEditorImageTextTooltip';
  static const String ideaEditorImageTextNoText = 'ideaEditorImageTextNoText';
  static const String ideaEditorImageTextFailed = 'ideaEditorImageTextFailed';
  static const String ideaEditorImagePermissionTitle =
      'ideaEditorImagePermissionTitle';
  static const String ideaEditorImagePermissionBody =
      'ideaEditorImagePermissionBody';
  static const String ideaEditorSnackbarDuplicateSection =
      'ideaEditorSnackbarDuplicateSection';
  static const String ideaEditorMicPermissionTitle =
      'ideaEditorMicPermissionTitle';
  static const String ideaEditorMicPermissionBody =
      'ideaEditorMicPermissionBody';
  static const String ideaEditorOpenSettings = 'ideaEditorOpenSettings';
  static const String ideaEditorMicLongPressToTalk =
      'ideaEditorMicLongPressToTalk';

  static const String paywallPurchaseUnavailable = 'paywallPurchaseUnavailable';

  static const String backupRestoreCloudUpdateFailed =
      'backupRestoreCloudUpdateFailed';
  static const String backupRestoreLastBackupNever =
      'backupRestoreLastBackupNever';
  static const String backupRestoreNoBackupYet = 'backupRestoreNoBackupYet';
  static const String backupRestoreAccountPlaceholderIcloud =
      'backupRestoreAccountPlaceholderIcloud';
  static const String backupRestoreBackingUp = 'backupRestoreBackingUp';
  static const String backupRestoreRestoring = 'backupRestoreRestoring';
  static const String backupRestoreAutoBackupUpdateFailed =
      'backupRestoreAutoBackupUpdateFailed';
  static const String backupRestoreBackupComplete =
      'backupRestoreBackupComplete';
  static const String backupRestoreConfirmRestoreTitle =
      'backupRestoreConfirmRestoreTitle';
  static const String backupRestoreConfirmRestoreBody =
      'backupRestoreConfirmRestoreBody';
  static const String backupRestoreConfirmRestoreButton =
      'backupRestoreConfirmRestoreButton';
  static const String backupRestoreNoBackupFound = 'backupRestoreNoBackupFound';
  static const String backupRestoreRestoredMessage =
      'backupRestoreRestoredMessage';
  static const String backupRestoreFormatBytesB = 'backupRestoreFormatBytesB';
  static const String backupRestoreFormatBytesKb = 'backupRestoreFormatBytesKb';
  static const String backupRestoreFormatBytesMb = 'backupRestoreFormatBytesMb';
}
