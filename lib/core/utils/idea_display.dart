import 'package:easy_localization/easy_localization.dart';

import '../../models/idea.dart';
import '../constants/view_constants.dart';

String ideaDisplayTitle(Idea idea) {
  if (idea.titleHidden) {
    return ViewConstants.vaultLockedNoteTitle.tr();
  }
  return idea.title;
}
