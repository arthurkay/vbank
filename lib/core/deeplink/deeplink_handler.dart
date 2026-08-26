import 'dart:async';

import 'package:app_links/app_links.dart';

/// Listens for `vbank://` deep links and parses them into [DeepLinkResult]s.
///
/// Usage: subscribe to [onDeepLink] *before* calling [init] so the cold-start
/// link (which `app_links` re-emits on `uriLinkStream`) is not missed.
class DeepLinkHandler {
  static const scheme = 'vbank';

  final AppLinks _appLinks;
  StreamSubscription<Uri>? _sub;
  final _linkController = StreamController<DeepLinkResult>.broadcast();

  DeepLinkHandler({AppLinks? appLinks}) : _appLinks = appLinks ?? AppLinks();

  Stream<DeepLinkResult> get onDeepLink => _linkController.stream;

  /// Starts listening for links. `app_links` delivers the initial (cold-start)
  /// link on [AppLinks.uriLinkStream] as well, so we intentionally do NOT call
  /// `getInitialLink()` — doing both would handle the same link twice.
  void init() {
    if (_sub != null) return;
    _sub = _appLinks.uriLinkStream.listen(
      (uri) => _emit(parse(uri)),
      onError: (Object err) {
        _emit(DeepLinkResult(type: DeepLinkType.error, error: err.toString()));
      },
    );
  }

  void _emit(DeepLinkResult result) {
    if (!_linkController.isClosed) _linkController.add(result);
  }

  /// Builds a join link: `vbank://join?group=…&inviter=…&cid=…&addrs=…`
  ///
  /// [inviterAddrs] are the inviter's dialable multiaddrs. Peer discovery on a
  /// LAN is not reliable, so the joiner dials these directly before fetching
  /// the group snapshot.
  static String buildJoinLink({
    required String groupId,
    required String inviterPeerId,
    String? groupCid,
    String? inviteId,
    String? inviteNonceB64,
    List<String> inviterAddrs = const [],
  }) {
    return Uri(
      scheme: scheme,
      host: 'join',
      queryParameters: {
        'group': groupId,
        'inviter': inviterPeerId,
        'cid': ?groupCid,
        'invite': ?inviteId,
        'n': ?inviteNonceB64,
        if (inviterAddrs.isNotEmpty) 'addrs': inviterAddrs.join(','),
      },
    ).toString();
  }

  /// Parses a raw link string. Never throws.
  static DeepLinkResult parseString(String link) {
    final uri = Uri.tryParse(link.trim());
    if (uri == null) {
      return DeepLinkResult(
        type: DeepLinkType.error,
        rawLink: link,
        error: 'Invalid link: $link',
      );
    }
    return parse(uri);
  }

  /// Parses a [Uri]. Never throws — malformed percent-escapes and unknown
  /// links are reported as [DeepLinkType.error] / [DeepLinkType.unknown].
  static DeepLinkResult parse(Uri uri) {
    final raw = uri.toString();
    if (uri.scheme != scheme) {
      return DeepLinkResult(type: DeepLinkType.unknown, rawLink: raw);
    }

    final Map<String, String> params;
    try {
      // `queryParameters` throws FormatException on invalid UTF-8 escapes.
      params = uri.queryParameters;
    } on FormatException catch (e) {
      return DeepLinkResult(
        type: DeepLinkType.error,
        rawLink: raw,
        error: 'Malformed link parameters: ${e.message}',
      );
    }

    String? nonEmpty(String key) {
      final v = params[key]?.trim();
      return (v == null || v.isEmpty) ? null : v;
    }

    switch (uri.host) {
      case 'join':
        final groupId = nonEmpty('group');
        final inviterPeerId = nonEmpty('inviter');
        if (groupId == null || inviterPeerId == null) {
          return DeepLinkResult(
            type: DeepLinkType.error,
            rawLink: raw,
            error: 'Missing required parameters in join link',
          );
        }
        return DeepLinkResult(
          type: DeepLinkType.joinGroup,
          groupId: groupId,
          inviterPeerId: inviterPeerId,
          // CID of the encrypted group snapshot on IPFS (optional for
          // backwards compatibility with older links).
          groupCid: nonEmpty('cid'),
          inviteId: nonEmpty('invite'),
          inviteNonceB64: nonEmpty('n'),
          inviterAddrs: (nonEmpty('addrs') ?? '')
              .split(',')
              .map((a) => a.trim())
              .where((a) => a.isNotEmpty)
              .toList(),
          rawLink: raw,
        );
      case 'restore':
        // `backup` is optional: without it the restore screen offers the
        // most recent local backup.
        return DeepLinkResult(
          type: DeepLinkType.restoreBackup,
          backupId: nonEmpty('backup'),
          rawLink: raw,
        );
      default:
        return DeepLinkResult(type: DeepLinkType.unknown, rawLink: raw);
    }
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
    _linkController.close();
  }
}

enum DeepLinkType { joinGroup, restoreBackup, unknown, error }

class DeepLinkResult {
  final DeepLinkType type;
  final String? groupId;
  final String? inviterPeerId;
  final String? groupCid;
  final String? inviteId;
  final String? inviteNonceB64;
  /// Inviter's dialable multiaddrs from the link (may be empty).
  final List<String> inviterAddrs;
  final String? backupId;
  final String? rawLink;
  final String? error;

  const DeepLinkResult({
    required this.type,
    this.groupId,
    this.inviterPeerId,
    this.groupCid,
    this.inviteId,
    this.inviteNonceB64,
    this.inviterAddrs = const [],
    this.backupId,
    this.rawLink,
    this.error,
  });


  bool get isJoin => type == DeepLinkType.joinGroup;
  bool get isRestore => type == DeepLinkType.restoreBackup;
}
