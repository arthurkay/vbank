import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_provider.dart';
import '../../ui/ui.dart';

class CreateAccountScreen extends ConsumerStatefulWidget {
  const CreateAccountScreen({super.key});

  @override
  ConsumerState<CreateAccountScreen> createState() => _CreateAccountScreenState();
}

class _CreateAccountScreenState extends ConsumerState<CreateAccountScreen> {
  final _nameController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _createAccount() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      showMessage(context, 'Please enter your name', error: true);
      return;
    }
    setState(() => _isLoading = true);
    try {
      await ref.read(authProvider.notifier).createIdentity(name);
      if (mounted) Navigator.pushReplacementNamed(context, '/home');
    } catch (e) {
      if (mounted) showMessage(context, 'Error creating account: $e', error: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppPage(
      title: 'Create Account',
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('What should we call you?').h3,
            const Gap(8),
            const Text('Your name is shown to the members of your groups. A signing key is created for you on this phone.').muted,
            const Gap(24),
            LabeledField(
              label: 'Display name',
              child: TextField(cursorOpacityAnimates: false, 
                controller: _nameController,
                autofocus: true,
                placeholder: const Text('e.g. Grace Mwanza'),
                textCapitalization: TextCapitalization.words,
                onSubmitted: (_) => _createAccount(),
              ),
            ),
            const Gap(32),
            Button.primary(
              onPressed: _isLoading ? null : _createAccount,
              child: _isLoading ? const CircularProgressIndicator(size: 18) : const Text('Create Account'),
            ),
          ],
        ),
      ),
    );
  }
}
