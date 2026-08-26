import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/app_backup.dart';
import '../../providers/auth_provider.dart';
import '../../providers/group_provider.dart';
import '../../services/backup_service.dart';
import '../../ui/ui.dart';

/// DESIGN_PLAN §22 restore flow: import a backup file (or pick one already on
/// this phone), enter the PIN, restore identity + groups + group keys.
class RestoreBackupScreen extends ConsumerStatefulWidget {
  /// Pre-selects a locally stored backup (from `vbank://restore?backup=<id>`).
  final String? backupId;

  const RestoreBackupScreen({super.key, this.backupId});

  @override
  ConsumerState<RestoreBackupScreen> createState() => _RestoreBackupScreenState();
}

class _RestoreBackupScreenState extends ConsumerState<RestoreBackupScreen> {
  final _pinController = TextEditingController();
  final _service = BackupService();
  bool _isLoading = false;
  List<AppBackup> _local = const [];
  String? _selectedId;
  Uint8List? _importedBytes;
  String? _importedName;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.backupId;
    _loadLocal();
  }

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _loadLocal() async {
    final list = await _service.getAllBackups();
    if (!mounted) return;
    setState(() {
      _local = list;
      if (_selectedId == null && list.isNotEmpty) _selectedId = list.first.id;
    });
  }

  void _msg(String message, {bool error = false}) {
    if (mounted) showMessage(context, message, error: error);
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.pickFiles(withData: true);
    final file = result?.files.single;
    if (file == null) return;
    final bytes = file.bytes;
    if (bytes == null) return _msg('Could not read the selected file', error: true);
    if (BackupEnvelope.tryDecode(bytes) == null) return _msg('That file is not a vBank backup', error: true);
    setState(() {
      _importedBytes = bytes;
      _importedName = file.name;
      _selectedId = null;
    });
  }

  Uint8List? get _payload {
    if (_importedBytes != null) return _importedBytes;
    return _local.where((b) => b.id == _selectedId).firstOrNull?.encryptedPayload;
  }

  Future<void> _restore() async {
    final pin = _pinController.text;
    if (pin.isEmpty) return _msg('Please enter your PIN', error: true);
    final payload = _payload;
    if (payload == null) return _msg('Choose a backup file first', error: true);

    setState(() => _isLoading = true);
    try {
      final restored = await _service.decryptBackup(encryptedPayload: payload, passphrase: pin);
      if (restored == null) return _msg('Invalid PIN or corrupted backup', error: true);
      if (_importedBytes != null) await _service.importBackupFile(_importedBytes!); // keep a local copy
      await _service.applyBackup(restored);
      await ref.read(authProvider.notifier).loadIdentity();
      await ref.read(groupListProvider.notifier).refresh();
      if (mounted) {
        _msg('Restored ${restored.identity.displayName} and ${restored.groups.length} group(s)');
        Navigator.pushNamedAndRemoveUntil(context, '/home', (_) => false);
      }
    } catch (e) {
      _msg('Error restoring backup: $e', error: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppPage(
      title: 'Restore Backup',
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(LucideIcons.archiveRestore, size: 64, color: scheme.primary),
            const Gap(24),
            const Text('Restore your identity from a backup', textAlign: TextAlign.center).h3,
            const Gap(8),
            const Text(
              'Import the backup file you exported from your old phone, then enter the PIN you set when creating it.',
              textAlign: TextAlign.center,
            ).muted,
            const Gap(24),
            Button.outline(
              onPressed: _isLoading ? null : _pickFile,
              leading: const Icon(LucideIcons.folderOpen),
              child: Text(_importedName == null ? 'Import backup file' : 'File: $_importedName', overflow: TextOverflow.ellipsis),
            ),
            if (_local.isNotEmpty) ...[
              const SectionTitle('Or choose a backup on this phone'),
              for (final b in _local)
                Builder(builder: (context) {
                  final selected = _importedBytes == null && _selectedId == b.id;
                  return ListRow(
                    leading: Icon(selected ? LucideIcons.circleDot : LucideIcons.circle,
                        color: selected ? scheme.primary : scheme.mutedForeground),
                    title: Text(fmtDateTime(b.createdAt)),
                    subtitle: Text('${b.type.name} backup').small.muted,
                    onTap: () => setState(() {
                      _selectedId = b.id;
                      _importedBytes = null;
                      _importedName = null;
                    }),
                  );
                }),
            ],
            const Gap(24),
            LabeledField(
              label: 'Backup PIN',
              child: TextField(cursorOpacityAnimates: false, 
                controller: _pinController,
                obscureText: true,
                keyboardType: TextInputType.visiblePassword,
                autocorrect: false,
                enableSuggestions: false,
                features: const [InputFeature.passwordToggle()],
                onSubmitted: (_) => _restore(),
              ),
            ),
            const Gap(24),
            Button.primary(
              onPressed: _isLoading ? null : _restore,
              child: _isLoading ? const CircularProgressIndicator(size: 18) : const Text('Restore Backup'),
            ),
          ],
        ),
      ),
    );
  }
}
