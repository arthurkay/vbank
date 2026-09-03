import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../../models/app_backup.dart';
import '../../providers/auth_provider.dart';
import '../../services/backup_service.dart';
import '../../services/cloud_backup_service.dart';
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
                child: TextField(cursorOpacityAnimates: false, 
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
                child: TextField(cursorOpacityAnimates: false, 
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
                subtitle: const Text('This identity is what a backup brings back').xSmall.muted,
              ),
            ),
          const Gap(12),
          const _CloudBackupPanel(),
          const Gap(12),
          const SectionTitle('Manual backup file'),
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


/// Automatic, encrypted backups to the member's Google Drive / iCloud.
class _CloudBackupPanel extends ConsumerStatefulWidget {
  const _CloudBackupPanel();
  @override
  ConsumerState<_CloudBackupPanel> createState() => _CloudBackupPanelState();
}

class _CloudBackupPanelState extends ConsumerState<_CloudBackupPanel> {
  final _cloud = CloudBackupService();
  bool _enabled = false;
  int _intervalDays = 1;
  bool _wifiOnly = true;
  DateTime? _lastAt;
  int? _lastSize;
  String? _lastError;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final enabled = await _cloud.enabled();
    final interval = await _cloud.intervalDays();
    final wifi = await _cloud.wifiOnly();
    final last = await _cloud.lastBackupAt();
    final size = await _cloud.lastBackupSize();
    final err = await _cloud.lastError();
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _intervalDays = interval;
      _wifiOnly = wifi;
      _lastAt = last;
      _lastSize = size;
      _lastError = err;
    });
  }

  Future<String?> _askPassphrase(String title) => promptSheet(
        context,
        title: title,
        message: 'This passphrase encrypts every automatic backup. ${_cloud.providerName} only ever stores '
            'ciphertext. If you forget it the backups cannot be opened — write it down.',
        label: 'Backup passphrase',
        obscure: true,
        confirmLabel: 'Save',
      );

  Future<void> _run(Future<void> Function() action, {String? success}) async {
    setState(() => _busy = true);
    try {
      await action();
      if (success != null && mounted) showMessage(context, success);
    } catch (e) {
      if (mounted) showMessage(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
      await _load();
    }
  }

  Future<void> _toggle(bool on) async {
    if (!on) {
      final ok = await confirmSheet(
        context,
        title: 'Turn off automatic backups?',
        message: 'Backups already in ${_cloud.providerName} stay there (unreadable without the passphrase). '
            'You can still export a file by hand.',
        confirmLabel: 'Turn off',
        destructive: true,
      );
      if (!ok) return;
      await _run(_cloud.disable);
      return;
    }
    final pass = await _askPassphrase('Set a backup passphrase');
    if (pass == null || pass.isEmpty || !mounted) return;
    await _run(() async {
      await _cloud.enable(passphrase: pass);
      await _cloud.runIfDue(force: true);
    }, success: 'Automatic backups on — first backup sent to ${_cloud.providerName}');
  }

  @override
  Widget build(BuildContext context) {
    if (!_cloud.isSupported) {
      return Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Automatic cloud backup').semiBold,
            const Gap(4),
            const Text('Available on Android (Google Drive) and iPhone (iCloud). On a computer, export a backup file '
                    'into a folder your Drive or iCloud client syncs.')
                .small
                .muted,
          ],
        ),
      );
    }
    final status = !_enabled
        ? 'Off'
        : _lastAt == null
            ? 'On · no backup yet'
            : 'Last backup ${fmtDateTime(_lastAt!)} · ${((_lastSize ?? 0) / 1024).toStringAsFixed(1)} KB';
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Automatic backup to ${_cloud.providerName}').semiBold,
                    const Gap(2),
                    Text(status).xSmall.muted,
                    if (_lastError != null) Text(_lastError!, style: TextStyle(color: VBankTheme.danger)).xSmall,
                  ],
                ),
              ),
              Switch(value: _enabled, onChanged: _busy ? null : _toggle),
            ],
          ),
          if (_enabled) ...[
            const Gap(12),
            Segmented<int>(
              values: const [1, 7],
              selected: _intervalDays,
              label: (d) => d == 1 ? 'Daily' : 'Weekly',
              onChanged: (d) => _run(() => _cloud.setIntervalDays(d)),
            ),
            const Gap(8),
            Row(
              children: [
                const Expanded(child: Text('Only on Wi-Fi')),
                Switch(value: _wifiOnly, onChanged: (v) => _run(() => _cloud.setWifiOnly(v))),
              ],
            ),
            const Gap(8),
            Row(
              children: [
                Button.outline(
                  onPressed: _busy
                      ? null
                      : () => _run(() => _cloud.backupNow(), success: 'Backed up to ${_cloud.providerName}'),
                  leading: _busy ? const CircularProgressIndicator(size: 14) : const Icon(LucideIcons.cloudUpload),
                  child: const Text('Back up now'),
                ),
                const Gap(8),
                Button.ghost(
                  onPressed: _busy
                      ? null
                      : () async {
                          final pass = await _askPassphrase('New backup passphrase');
                          if (pass == null || pass.isEmpty) return;
                          await _run(() => _cloud.changePassphrase(pass), success: 'Passphrase changed — next backup uses it');
                        },
                  child: const Text('Change passphrase'),
                ),
              ],
            ),
          ],
          const Gap(8),
          const Text(
            'Like WhatsApp: your data goes to your own account, encrypted so only your passphrase can open it. '
            'Records also live with your group members and the relay; the backup is what brings back your identity.',
          ).xSmall.muted,
        ],
      ),
    );
  }
}
