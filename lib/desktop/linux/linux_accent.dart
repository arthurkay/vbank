/// Resolves the desktop's accent colour on Linux and follows changes to it.
///
/// Yaru's own detection only recognises Adwaita-* and Yaru-* theme names and
/// the GNOME 47+ `accent-color` key, so on any other desktop (Zorin, Pop!_OS,
/// Mint, elementary, custom themes) it silently falls back to Canonical orange.
/// This reads what the desktop is actually using, in order of authority:
///
/// 1. `org.gnome.desktop.interface accent-color` (GNOME 47+), mapped to the
///    GNOME palette.
/// 2. The current GTK theme's stylesheet: `@define-color accent_bg_color` from
///    `gtk-4.0/gtk.css`, else `theme_selected_bg_color` / `selected_bg_color`
///    from `gtk-3.0/gtk.css`, following `@name` references. This is what the
///    desktop itself paints selections and buttons with.
/// 3. A theme-name heuristic for well-known families.
///
/// Returns `null` when nothing can be determined, in which case the caller
/// keeps Yaru's default so Ubuntu still looks like Ubuntu.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

class LinuxAccent extends ValueNotifier<Color?> {
  LinuxAccent() : super(null);

  Process? _monitor;
  StreamSubscription<String>? _monitorSub;

  /// Test/debug hook: pretend this GTK theme is selected.
  static String? get _themeOverride => Platform.environment['VBANK_GTK_THEME'];

  /// Resolve once and start following `gsettings` changes.
  Future<void> start() async {
    value = await resolve();
    await _watch();
  }

  Future<void> _watch() async {
    if (_monitor != null) return;
    try {
      _monitor = await Process.start('gsettings', ['monitor', 'org.gnome.desktop.interface']);
      _monitorSub = _monitor!.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen(
        (line) async {
          if (line.startsWith('gtk-theme:') ||
              line.startsWith('accent-color:') ||
              line.startsWith('color-scheme:')) {
            value = await resolve();
          }
        },
      );
    } catch (_) {
      // No gsettings: nothing to follow; the resolved value stands.
    }
  }

  @override
  void dispose() {
    _monitorSub?.cancel();
    _monitor?.kill();
    super.dispose();
  }

  // ---------------------------------------------------------------------------

  static Future<Color?> resolve() async {
    final byKey = await _fromAccentColorKey();
    if (byKey != null) return byKey;

    final themeName = _themeOverride ?? await _gsetting('gtk-theme');
    if (themeName == null || themeName.isEmpty) return null;

    final fromCss = await fromGtkTheme(themeName);
    if (fromCss != null) return fromCss;

    return fromThemeName(themeName);
  }

  static Future<String?> _gsetting(String key) async {
    try {
      final r = await Process.run('gsettings', ['get', 'org.gnome.desktop.interface', key]);
      if (r.exitCode != 0) return null;
      return (r.stdout as String).trim().replaceAll("'", '');
    } catch (_) {
      return null;
    }
  }

  /// GNOME 47+ named accents → the GNOME palette they map to.
  static Future<Color?> _fromAccentColorKey() async {
    final name = await _gsetting('accent-color');
    return gnomeAccents[name];
  }

  static const gnomeAccents = <String, Color>{
    'blue': Color(0xFF3584E4),
    'teal': Color(0xFF2190A4),
    'green': Color(0xFF3A944A),
    'yellow': Color(0xFFC88800),
    'orange': Color(0xFFED5B00),
    'red': Color(0xFFE62D42),
    'pink': Color(0xFFD56199),
    'purple': Color(0xFF9141AC),
    'slate': Color(0xFF6F8396),
  };

  /// Reads the accent from the named theme's stylesheets.
  static Future<Color?> fromGtkTheme(String themeName) async {
    final dir = _themeDir(themeName);
    if (dir == null) return null;

    final gtk4 = File('${dir.path}/gtk-4.0/gtk.css');
    if (await gtk4.exists()) {
      final c = parseDefineColor(await gtk4.readAsString(), const ['accent_bg_color', 'accent_color']);
      if (c != null) return c;
    }
    final gtk3 = File('${dir.path}/gtk-3.0/gtk.css');
    if (await gtk3.exists()) {
      final c = parseDefineColor(
        await gtk3.readAsString(),
        const ['accent_bg_color', 'theme_selected_bg_color', 'selected_bg_color'],
      );
      if (c != null) return c;
    }
    return null;
  }

  static Directory? _themeDir(String name) {
    final home = Platform.environment['HOME'] ?? '';
    final candidates = [
      '$home/.themes/$name',
      '$home/.local/share/themes/$name',
      '/usr/share/themes/$name',
      '/usr/local/share/themes/$name',
    ];
    for (final c in candidates) {
      final d = Directory(c);
      if (d.existsSync()) return d;
    }
    return null;
  }

  /// Finds the first of [names] defined with `@define-color` in [css],
  /// following `@other_name` references, and returns it as a colour.
  @visibleForTesting
  static Color? parseDefineColor(String css, List<String> names) {
    final defs = <String, String>{};
    for (final m in RegExp(r'@define-color\s+([A-Za-z0-9_\-]+)\s+([^;]+);').allMatches(css)) {
      defs[m.group(1)!] = m.group(2)!.trim();
    }
    for (final name in names) {
      final c = _resolveDefine(defs, name, 0);
      if (c != null) return c;
    }
    return null;
  }

  static Color? _resolveDefine(Map<String, String> defs, String name, int depth) {
    if (depth > 8) return null;
    final raw = defs[name];
    if (raw == null) return null;
    if (raw.startsWith('@')) return _resolveDefine(defs, raw.substring(1), depth + 1);
    return parseCssColor(raw);
  }

  /// `#rgb`, `#rrggbb`, `#rrggbbaa`, `rgb(r,g,b)`, `rgba(r,g,b,a)`.
  @visibleForTesting
  static Color? parseCssColor(String raw) {
    final v = raw.trim();
    if (v.startsWith('#')) {
      var hex = v.substring(1);
      if (hex.length == 3) hex = hex.split('').map((c) => '$c$c').join();
      final String argb;
      if (hex.length == 6) {
        argb = 'FF$hex';
      } else if (hex.length == 8) {
        argb = hex.substring(6, 8) + hex.substring(0, 6); // #rrggbbaa → aarrggbb
      } else {
        return null;
      }
      final n = int.tryParse(argb, radix: 16);
      return n == null ? null : Color(n);
    }
    final m = RegExp(r'rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)(?:\s*,\s*([0-9.]+))?\s*\)').firstMatch(v);
    if (m != null) {
      final a = m.group(4) == null ? 1.0 : double.parse(m.group(4)!);
      return Color.fromARGB(
        (a * 255).round().clamp(0, 255),
        int.parse(m.group(1)!),
        int.parse(m.group(2)!),
        int.parse(m.group(3)!),
      );
    }
    return null;
  }

  /// Last resort: colour families encoded in the theme name.
  @visibleForTesting
  static Color? fromThemeName(String name) {
    final n = name.toLowerCase();
    // Yaru and Ubuntu flavours: leave to Yaru's own variant detection.
    if (n.startsWith('yaru')) return null;
    const families = <String, Color>{
      'blue': Color(0xFF3584E4),
      'teal': Color(0xFF2190A4),
      'aqua': Color(0xFF2190A4),
      'green': Color(0xFF3A944A),
      'yellow': Color(0xFFC88800),
      'orange': Color(0xFFED5B00),
      'red': Color(0xFFE62D42),
      'pink': Color(0xFFD56199),
      'magenta': Color(0xFFD56199),
      'purple': Color(0xFF9141AC),
      'violet': Color(0xFF9141AC),
      'grey': Color(0xFF6F8396),
      'gray': Color(0xFF6F8396),
      'slate': Color(0xFF6F8396),
      'brown': Color(0xFF865E3C),
    };
    for (final e in families.entries) {
      if (n.contains(e.key)) return e.value;
    }
    if (n.startsWith('adwaita')) return const Color(0xFF3584E4);
    return null;
  }
}
