import 'dart:io';

/// Which UI shell the app should present.
///
/// vBank ships one domain layer and four presentations: shadcn_flutter on
/// phones, and each desktop platform's own design system — Yaru on Linux,
/// macos_ui on macOS, Fluent on Windows (DESIGN_PLAN §37).
enum AppShell { mobile, linux, macos, windows }

class AppPlatform {
  AppPlatform._();

  static AppShell? _override;

  /// Test/debug hook: force a shell regardless of the host OS.
  static void overrideShell(AppShell? shell) => _override = shell;

  static AppShell get shell {
    final forced = _override;
    if (forced != null) return forced;
    if (Platform.isLinux) return AppShell.linux;
    if (Platform.isMacOS) return AppShell.macos;
    if (Platform.isWindows) return AppShell.windows;
    return AppShell.mobile;
  }

  static bool get isDesktop => shell != AppShell.mobile;
  static bool get isMobile => shell == AppShell.mobile;

  /// Camera QR scanning: mobile_scanner has no Linux or Windows backend, so
  /// those platforms join a group by pasting the invite link instead.
  static bool get canScanQr => Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

  /// flutter_local_notifications has no Windows backend in this version.
  static bool get canNotify => !Platform.isWindows;
}
