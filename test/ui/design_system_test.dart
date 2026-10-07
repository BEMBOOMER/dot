import 'package:dot/ui/theme/dot_theme.dart';
import 'package:dot/ui/widgets/dot_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('theme uses the design tokens in both appearances', () {
    expect(lightTheme.scaffoldBackgroundColor, const Color(0xFFF7F7F8));
    expect(darkTheme.scaffoldBackgroundColor, const Color(0xFF0B0B0D));
    expect(lightTheme.colorScheme.primary, const Color(0xFF3D5AFE));
    expect(darkTheme.colorScheme.primary, const Color(0xFF6C83FF));
    for (final theme in [lightTheme, darkTheme]) {
      expect(theme.textTheme.displayMedium!.fontFamily, 'Inter');
      expect(theme.textTheme.displayMedium!.fontSize, 34);
      expect(theme.textTheme.titleLarge!.fontSize, 22);
      expect(theme.textTheme.titleMedium!.fontSize, 16);
      expect(theme.chipTheme.showCheckmark, false);
      expect(
        theme.inputDecorationTheme.enabledBorder!.borderSide,
        BorderSide.none,
      );
    }
  });

  testWidgets('buttons expose keyboard actions and disabled semantics', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: lightTheme,
        home: Scaffold(
          body: Column(
            children: [
              DotButton(label: 'Actie', onPressed: () => calls++),
              const DotButton(
                label: 'Niet beschikbaar',
                variant: DotButtonStyle.secondary,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.text('Actie'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(
      tester
          .widget<TextButton>(
            find.widgetWithText(TextButton, 'Niet beschikbaar'),
          )
          .onPressed,
      isNull,
    );
    expect(tester.getSize(find.widgetWithText(TextButton, 'Actie')).height, 52);
  });
}
