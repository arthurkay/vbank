import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class ShareService {
  static Future<void> shareInviteLink({
    required String groupName,
    required String inviteLink,
  }) async {
    await Share.share(
      'Join "$groupName" on vBank!\n\n$inviteLink',
      subject: 'vBank Group Invite',
    );
  }

  static Future<void> shareText({
    required String text,
    String? subject,
  }) async {
    await Share.share(text, subject: subject);
  }

  static Future<void> openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  static Future<void> copyToClipboard(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
  }
}
