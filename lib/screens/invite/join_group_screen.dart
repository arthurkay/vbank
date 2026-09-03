import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../core/deeplink/deeplink_handler.dart';
import '../../core/ipfs/sync_manager.dart';
import '../../models/group.dart';
import '../../providers/auth_provider.dart';
import '../../providers/data_version.dart';
import '../../providers/group_provider.dart';
import '../../providers/ipfs_provider.dart';
import '../../services/group_key_service.dart';
import '../../core/deeplink/pending_invite.dart';
import '../../ui/ui.dart';

class JoinGroupScreen extends ConsumerStatefulWidget {
  /// When opened from a `vbank://join` deep link, the already-parsed link is
  /// passed here so the join starts immediately.
  final DeepLinkResult? deepLink;
  const JoinGroupScreen({super.key, this.deepLink});

  @override
  ConsumerState<JoinGroupScreen> createState() => _JoinGroupScreenState();
}

class _JoinGroupScreenState extends ConsumerState<JoinGroupScreen> {
  bool _isScanning = false;
  MobileScannerController? _scanner;
  bool _isProcessing = false;
  String? _progress;

  @override
  void initState() {
    super.initState();
    _scanner = MobileScannerController(detectionSpeed: DetectionSpeed.normal, facing: CameraFacing.back);
    final link = widget.deepLink;
    if (link != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _processInvite(link);
      });
    }
  }

  @override
  void dispose() {
    _scanner?.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_isProcessing) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw != null && raw.startsWith('${DeepLinkHandler.scheme}://join')) {
        _stopScanning();
        _processInvite(DeepLinkHandler.parseString(raw));
        return;
      }
    }
  }

  Future<void> _processInvite(DeepLinkResult result) async {
    if (_isProcessing) return;
    final groupId = result.groupId;
    final inviterPeerId = result.inviterPeerId;
    if (!result.isJoin || groupId == null || inviterPeerId == null) {
      return showMessage(context, result.error ?? 'Invalid invite link', error: true);
    }
    final identity = ref.read(authProvider).identity;
    if (identity == null) {
      // First contact with the app is often an invite link: park it, take the
      // person through account creation and resume the join afterwards.
      PendingInvite.link = result;
      showMessage(context, 'Create your account first — you will join the group right after');
      Navigator.pushReplacementNamed(context, '/create-account');
      return;
    }

    final existing = await ref.read(groupServiceProvider).getGroup(groupId);
    if (!mounted) return;
    if (existing != null && existing.members.any((m) => m.peerId == identity.peerId)) {
      showMessage(context, 'You are already a member of this group');
      ref.read(selectedGroupProvider.notifier).state = existing;
      Navigator.pushReplacementNamed(context, '/group-detail');
      return;
    }

    // New links carry a one-time secret that unwraps the group key. Older
    // links (no `k`) still need the group passphrase shared out-of-band.
    String? passphrase;
    if (result.inviteSecretB64 == null) {
      passphrase = await promptSheet(
        context,
        title: 'Group passphrase',
        message: 'This is an older invite. Ask the person who invited you for the group passphrase.',
        label: 'Passphrase',
        obscure: true,
        confirmLabel: 'Join',
      );
      if (passphrase == null || !mounted) return;
      final error = GroupKeyService.validatePassphrase(passphrase);
      if (error != null) return showMessage(context, error, error: true);
    }

    setState(() {
      _isProcessing = true;
      _progress = 'Fetching group from the network…';
    });
    try {
      final keyPair = await ref.read(authProvider.notifier).requireSigningKeyPair();
      final self = Member(
        peerId: identity.peerId,
        name: identity.displayName,
        role: MemberRole.member,
        joinedAt: DateTime.now().toUtc(),
        publicKey: identity.publicKey,
      );
      if (result.relayAddrs.isNotEmpty) await ref.read(syncManagerProvider).addRelays(result.relayAddrs);
      final group = await ref.read(syncManagerProvider).joinGroup(
            groupId: groupId,
            groupCid: result.groupCid,
            inviteId: result.inviteId,
            inviteNonceB64: result.inviteNonceB64,
            inviterPeerId: inviterPeerId,
            inviterAddrs: result.inviterAddrs,
            passphrase: passphrase,
            inviteSecretB64: result.inviteSecretB64,
            self: self,
            keyPair: keyPair,
          );
      await ref.read(groupListProvider.notifier).refresh();
      if (!mounted) return;
      showMessage(
        context,
        group.requireApproval
            ? 'Join request sent to "${group.name}" — waiting for an admin to approve'
            : 'Joined "${group.name}"',
      );
      ref.read(selectedGroupProvider.notifier).state = group;
      Navigator.pushReplacementNamed(context, '/group-detail');
    } on JoinParkedException catch (e) {
      // Nobody reachable: the join is saved and retried every sync round; the
      // Groups list shows it until it completes.
      ref.read(dataVersionProvider.notifier).state++;
      if (!mounted) return;
      showMessage(context, e.message);
      Navigator.pushNamedAndRemoveUntil(context, '/home', (_) => false);
    } on JoinGroupException catch (e) {
      debugPrint('[join] ${e.message}');
      if (mounted) showMessage(context, e.message, error: true);
    } catch (e, st) {
      debugPrint('[join] $e\n$st');
      if (mounted) showMessage(context, 'Error joining group: $e', error: true);
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _progress = null;
        });
      }
    }
  }

  void _startScanning() => setState(() => _isScanning = true);
  void _stopScanning() {
    if (!_isScanning) return;
    setState(() => _isScanning = false);
    _scanner?.stop();
  }

  Future<void> _enterManually() async {
    final link = await promptSheet(
      context,
      title: 'Enter invite code',
      label: 'Invite link',
      hint: 'vbank://join?group=...',
      maxLines: 3,
      confirmLabel: 'Join',
    );
    if (link != null && link.trim().isNotEmpty && mounted) {
      _processInvite(DeepLinkHandler.parseString(link));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppPage(
      title: 'Join Group',
      trailing: [
        if (_isScanning) IconButton.ghost(icon: const Icon(LucideIcons.x), onPressed: _stopScanning),
      ],
      child: _isScanning ? _scannerView() : _options(),
    );
  }

  Widget _scannerView() => Column(
        children: [
          Expanded(flex: 5, child: MobileScanner(controller: _scanner!, onDetect: _onDetect)),
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Scan a group QR code').large,
                  const Gap(6),
                  const Text('Point your camera at the QR code').muted,
                ],
              ),
            ),
          ),
        ],
      );

  Widget _options() => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(LucideIcons.scanLine, size: 96, color: Theme.of(context).colorScheme.primary),
              const Gap(24),
              const Text('Join a Village Banking Group', textAlign: TextAlign.center).h3,
              const Gap(8),
              const Text(
                'Scan the QR code or open the link a group admin sent you. It admits you once and expires in 12 hours.',
                textAlign: TextAlign.center,
              ).muted,
              if (_progress != null) ...[
                const Gap(24),
                const Center(child: CircularProgressIndicator()),
                const Gap(12),
                Text(_progress!, textAlign: TextAlign.center),
              ],
              const Spacer(),
              Button.primary(
                onPressed: _isProcessing ? null : _startScanning,
                leading: const Icon(LucideIcons.scanLine),
                child: Text(_isProcessing ? 'Joining…' : 'Scan QR Code'),
              ),
              const Gap(12),
              Button.outline(
                onPressed: _isProcessing ? null : _enterManually,
                leading: const Icon(LucideIcons.pencil),
                child: const Text('Enter Code Manually'),
              ),
            ],
          ),
        ),
      );
}
