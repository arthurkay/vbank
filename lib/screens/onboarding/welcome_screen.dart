import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_provider.dart';
import '../../ui/ui.dart';

class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
  late final _logoScale = Tween<double>(begin: 0.8, end: 1.0).animate(
    CurvedAnimation(parent: _controller, curve: Curves.easeOut),
  );
  late final _logoFade = CurvedAnimation(parent: _controller, curve: const Interval(0, 0.6, curve: Curves.easeOut));
  late final _textFade = CurvedAnimation(parent: _controller, curve: const Interval(0.2, 0.8, curve: Curves.easeOut));
  late final _buttonFade = CurvedAnimation(parent: _controller, curve: const Interval(0.4, 1.0, curve: Curves.easeOut));

  @override
  void initState() {
    super.initState();
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    if (auth.isLoaded && auth.isLoggedIn) {
      // Only redirect while this is the visible route. Welcome stays at the
      // bottom of the stack during onboarding, and pushReplacement replaces the
      // *top* route — it would swallow whatever Create Account just pushed
      // (e.g. the join screen for a pending invite).
      final isCurrent = ModalRoute.of(context)?.isCurrent ?? true;
      if (isCurrent) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted && (ModalRoute.of(context)?.isCurrent ?? true)) {
            Navigator.pushReplacementNamed(context, '/home');
          }
        });
      }
      return const Scaffold(child: LoadingView());
    }
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(flex: 3),
                FadeTransition(
                  opacity: _logoFade,
                  child: ScaleTransition(
                    scale: _logoScale,
                    child: Center(
                      child: Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(color: scheme.foreground, borderRadius: BorderRadius.circular(24)),
                        alignment: Alignment.center,
                        child: Icon(LucideIcons.landmark, size: 48, color: scheme.background),
                      ),
                    ),
                  ),
                ),
                const Gap(24),
                FadeTransition(
                  opacity: _textFade,
                  child: const Text(
                    'vBank',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                  ),
                ),
                const Gap(8),
                FadeTransition(
                  opacity: _textFade,
                  child: Text(
                    'Distributed village banking',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, color: scheme.mutedForeground),
                  ),
                ),
                const Spacer(flex: 4),
                FadeTransition(
                  opacity: _buttonFade,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      PrimaryButton(
                        onPressed: () => Navigator.pushNamed(context, '/create-account'),
                        child: const Text('Get started'),
                      ),
                      const Gap(8),
                      OutlineButton(
                        onPressed: () => Navigator.pushNamed(context, '/restore-backup'),
                        child: const Text('Restore from backup'),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
