import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:vbank/src/presentation/mobile/vbank_theme.dart';

void main() {
  group('vbank theme', () {
    test('dark is matte black with a monochrome primary', () {
      expect(
        VBankTheme.darkScheme.background,
        const Color(0xFF0B0B0C),
      );
      expect(VBankTheme.darkScheme.brightness, Brightness.dark);
      expect(VBankTheme.darkScheme.primary, const Color(0xFFFAFAFA));
      expect(
        VBankTheme.darkScheme.primaryForeground,
        const Color(0xFF18181B),
      );
      expect(VBankTheme.darkScheme.card, const Color(0xFF171717));
      // Neutral surfaces: at most a whisper of blue bias (slate-900,
      // the old cast, differs by 0.11).
      for (final Color c in [
        VBankTheme.darkScheme.background,
        VBankTheme.darkScheme.card,
        VBankTheme.darkScheme.muted,
        VBankTheme.darkScheme.border,
      ]) {
        expect((c.r - c.b).abs(), lessThanOrEqualTo(0.01));
        expect((c.g - c.b).abs(), lessThanOrEqualTo(0.01));
      }
    });

    test('light is paper with a monochrome primary', () {
      expect(
        VBankTheme.lightScheme.background,
        const Color(0xFFFAFAFA),
      );
      expect(VBankTheme.lightScheme.brightness, Brightness.light);
      expect(VBankTheme.lightScheme.primary, const Color(0xFF18181B));
      expect(VBankTheme.lightScheme.card, const Color(0xFFFFFFFF));
    });

    test('motion tokens match the spec', () {
      expect(
        VBankTheme.pushDuration,
        const Duration(milliseconds: 220),
      );
      expect(
        VBankTheme.sheetDuration,
        const Duration(milliseconds: 260),
      );
      expect(
        VBankTheme.fadeDuration,
        const Duration(milliseconds: 150),
      );
    });
  });
}
