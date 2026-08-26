import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:vbank/desktop/linux/linux_accent.dart';

/// The Linux accent resolver has to read real desktop themes correctly; these
/// are the shapes found in Zorin, Adwaita and libadwaita-style stylesheets.
void main() {
  group('parseDefineColor', () {
    test('reads a gtk-4.0 accent_bg_color (Zorin Blue dark)', () {
      const css = '''
@define-color accent_bg_color #bde6fb;
@define-color accent_color #bde6fb;
@define-color window_bg_color #242424;
''';
      expect(LinuxAccent.parseDefineColor(css, ['accent_bg_color']), const Color(0xFFBDE6FB));
    });

    test('falls back through the name list', () {
      const css = '@define-color theme_selected_bg_color #add3e6;';
      expect(
        LinuxAccent.parseDefineColor(css, ['accent_bg_color', 'theme_selected_bg_color']),
        const Color(0xFFADD3E6),
      );
    });

    test('follows @references between defines (libadwaita palette style)', () {
      const css = '''
@define-color blue_3 #3584e4;
@define-color accent_bg_color @blue_3;
''';
      expect(LinuxAccent.parseDefineColor(css, ['accent_bg_color']), const Color(0xFF3584E4));
    });

    test('returns null when nothing matches', () {
      expect(LinuxAccent.parseDefineColor('@define-color foo #000;', ['accent_bg_color']), isNull);
    });

    test('does not loop on circular references', () {
      const css = '@define-color a @b;\n@define-color b @a;';
      expect(LinuxAccent.parseDefineColor(css, ['a']), isNull);
    });
  });

  group('parseCssColor', () {
    test('handles the CSS colour forms GTK themes use', () {
      expect(LinuxAccent.parseCssColor('#fff'), const Color(0xFFFFFFFF));
      expect(LinuxAccent.parseCssColor('#3584e4'), const Color(0xFF3584E4));
      expect(LinuxAccent.parseCssColor('#3584e480'), const Color(0x803584E4));
      expect(LinuxAccent.parseCssColor('rgb(53, 132, 228)'), const Color(0xFF3584E4));
      expect(LinuxAccent.parseCssColor('rgba(53,132,228,0.5)'), const Color(0x803584E4));
      expect(LinuxAccent.parseCssColor('transparent'), isNull);
    });
  });

  group('fromThemeName', () {
    test('maps colour families and leaves Yaru to Yaru', () {
      expect(LinuxAccent.fromThemeName('ZorinBlue-Dark'), const Color(0xFF3584E4));
      expect(LinuxAccent.fromThemeName('Pop-purple'), const Color(0xFF9141AC));
      expect(LinuxAccent.fromThemeName('Mint-Y-Dark-Teal'), const Color(0xFF2190A4));
      expect(LinuxAccent.fromThemeName('Adwaita-dark'), const Color(0xFF3584E4));
      expect(LinuxAccent.fromThemeName('Yaru-sage-dark'), isNull, reason: 'Yaru detects its own variants');
      expect(LinuxAccent.fromThemeName('SomethingElse'), isNull);
    });
  });
}
