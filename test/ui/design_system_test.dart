import 'dart:ui' as ui;

import 'package:dot/ui/dots/dot_sphere.dart';
import 'package:dot/ui/theme/dot_theme.dart';
import 'package:dot/ui/widgets/dot_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'sphere preserves its base hue with at most twenty percent shading',
    () async {
      for (final base in [
        const Color(0xFF3D5AFE),
        const Color(0xFF6C83FF),
        const Color(0xFF0E0E10),
        const Color(0xFFF4F4F6),
      ]) {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        DotSphere(
          baseColor: base,
          radius: 70,
          center: const Offset(100, 90),
        ).paint(canvas, const Size(200, 200));
        final picture = recorder.endRecording();
        final image = await picture.toImage(200, 200);
        final pixels = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        final channels = [
          ((base.r * 255).round()),
          ((base.g * 255).round()),
          ((base.b * 255).round()),
        ];
        for (final point in [
          const Offset(100, 90),
          const Offset(155, 125),
          const Offset(100, 150),
        ]) {
          final offset = (point.dy.toInt() * 200 + point.dx.toInt()) * 4;
          for (var channel = 0; channel < 3; channel++) {
            expect(
              pixels.getUint8(offset + channel),
              greaterThanOrEqualTo((channels[channel] * .8).floor()),
            );
          }
        }
        final center = (90 * 200 + 100) * 4;
        for (var channel = 0; channel < 3; channel++) {
          expect(
            pixels.getUint8(center + channel),
            closeTo(channels[channel], 16),
          );
        }
        image.dispose();
        picture.dispose();
      }
    },
  );

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
