import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../../models/app_backup.dart';
import '../../providers/auth_provider.dart';
import '../../services/backup_service.dart';
import '../../ui/ui.dart';

/// DESIGN_PLAN §22 / §27 identity_backup_screen: create PIN-encrypted
/// backups (identity + signing key + groups + group keys), export them as a
/// file to move to a new phone, and delete old ones.
class IdentityBackupScreen extends ConsumerStatefulWidget {
  const IdentityBackupScreen({super.key});

  @override
  ConsumerState<IdentityBackupScreen> createState() => _IdentityBackupScreenState();
}

class _IdentityBackupScreenState extends ConsumerState<IdentityBackupScreen> {
  final _service = BackupService();
  List<AppBackup> _backups = const [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await _service.getAllBackups();
    if (mounted) setState(() => _backups = list);
  }

  void _msg(String m, {bool error = false}) {
    if (mounted) showMessage(context, m, error: error);
  }

  Future<void> _create() async {
    final pin = await _askPin();
    if (pin == null) return;
    setState(() => _busy = true);
    try {
      final id = await _service.createFullBackup(passphrase: pin);
      await _load();
      _msg('Backup created');
      if (!mounted) return;
      final share = await confirmSheet(
        context,
        title: 'Export now?',
        message: 'Send the encrypted backup file to Drive, WhatsApp or another phone?',
        confirmLabel: 'Export',
        cancelLabel: 'Later',
      );
      if (share) await _export(id);
    } catch (e) {
      _msg('Backup failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export(String id) async {
    try {
      final file = await _service.exportBackupToFile(id);
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/octet-stream')],
        subject: 'vBank backup',
        text: 'Encrypted vBank backup. You need the PIN to restore it.',
      );
    } catch (e) {
      _msg('Export failed: $e', error: true);
    }
  }

  Future<void> _delete(String id) async {
    final ok = await confirmSheet(
      context,
      title: 'Delete backup?',
      message: 'This cannot be undone. Exported copies are not affected.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok) return;
    await _service.deleteBackup(id);
    await _load();
  }

  Future<String?> _askPin() async {
    final c1 = TextEditingController();
    final c2 = TextEditingController();
    String? error;
    return showAppSheet<String>(
      context,
      title: 'Backup PIN',
      builder: (ctx, close) => StatefulBuilder(
        builder: (ctx, setS) {
          void submit() {
            final e = BackupService.validatePin(c1.text);
            if (e != null) return setS(() => error = e);
            if (c1.text != c2.text) return setS(() => error = 'PINs do not match');
            close(c1.text);
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'This PIN protects your signing key and all group keys. '
                'Anyone with the file and the PIN can act as you — choose at least 6 characters.',
              ).small.muted,
              const Gap(16),
              LabeledField(
                label: 'PIN',
                child: TextField(
                  controller: c1,
                  obscureText: true,
                  autofocus: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  features: const [InputFeature.passwordToggle()],
                ),
              ),
              const Gap(16),
              LabeledField(
                label: 'Confirm PIN',
                helper: error,
                child: TextField(
                  controller: c2,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  features: const [InputFeature.passwordToggle()],
                  onSubmitted: (_) => submit(),
                ),
              ),
              if (error != null) ...[
                const Gap(6),
                Text(error!, style: TextStyle(color: Theme.of(ctx).colorScheme.destructive)).small,
              ],
              const Gap(24),
              Button.primary(onPressed: submit, child: const Text('Create backup')),
              const Gap(8),
              OutlineButton(onPressed: () => close(), child: const Text('Cancel')),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final identity = ref.watch(authProvider).identity;
    return AppPage(
      title: 'Backup & Restore',
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (identity != null)
            Panel(
              child: Basic(
                leading: InitialsAvatar(identity.displayName, size: 44),
                leadingAlignment: Alignment.center,
                title: Text(identity.displayName),
                subtitle: Text(identity.peerId).xSmall.muted,
              ),
            ),
          const Gap(12),
          Button.primary(
            onPressed: _busy ? null : _create,
            leading: _busy ? const CircularProgressIndicator(size: 16) : const Icon(LucideIcons.cloudUpload),
            child: const Text('Create new backup'),
          ),
          const Gap(8),
          const Text(
            'A backup contains your identity, signing key, groups and group keys, encrypted with a PIN. '
            'Export it to a file and keep it somewhere safe; you need it to move to a new phone.',
          ).small.muted,
          const SectionTitle('Backups on this phone'),
          if (_backups.isEmpty) const Text('None yet').muted,
          for (final b in _backups)
            ListRow(
              leading: const Icon(LucideIcons.lock),
              title: Text(fmtDateTime(b.createdAt)),
              subtitle: Text('${(b.encryptedPayload.length / 1024).toStringAsFixed(1)} KB · encrypted').small.muted,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton.ghost(icon: const Icon(LucideIcons.upload), onPressed: () => _export(b.id)),
                  IconButton.ghost(icon: const Icon(LucideIcons.trash2), onPressed: () => _delete(b.id)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
