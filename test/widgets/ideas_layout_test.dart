import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:idea_vault/data/repositories/local/theme.dart';
import 'package:idea_vault/models/idea.dart';
import 'package:idea_vault/viewmodels/providers/theme_provider.dart';
import 'package:idea_vault/widgets/ideas/ideas_layout.dart';
import 'package:provider/provider.dart';

import '../helpers/memory_local_storage.dart';

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets('locked idea card keeps title visible with icon only overlay',
      (tester) async {
    final themeProvider = ThemeProvider(ThemeRepo(MemoryLocalStorageManager()));
    final idea = Idea(
      id: 'idea-1',
      title: 'Visible Title',
      createdAt: DateTime.utc(2026, 6, 24),
      updatedAt: DateTime.utc(2026, 6, 24),
      isLocked: true,
      sections: const [
        IdeaSection(
          id: 'section-1',
          name: 'Idea',
          content: 'Private preview',
        ),
      ],
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>.value(
        value: themeProvider,
        child: MaterialApp(
          theme: themeProvider.baseTheme.themeData,
          home: Scaffold(
            body: SizedBox(
              width: 360,
              height: 190,
              child: IdeaCard(
                idea: idea,
                layout: IdeaCardLayout.list,
                isSelected: false,
                onTap: () {},
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Visible Title'), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
    expect(find.text('Private preview'), findsNothing);
    expect(find.text('homepageIdeaCardOneSection'), findsNothing);
    expect(find.text('Locked note'), findsNothing);
  });
}
