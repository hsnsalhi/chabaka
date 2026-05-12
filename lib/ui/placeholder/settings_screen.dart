import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/router.dart';
import '../../data/persistence/settings_service.dart';
import '../../ui/theme/chabaka_theme.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    final notifier = ref.read(themeModeProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('المظهر', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          SegmentedButton<ChabakaThemeMode>(
            segments: const [
              ButtonSegment(value: ChabakaThemeMode.light, label: Text('فاتح')),
              ButtonSegment(value: ChabakaThemeMode.sepia, label: Text('سيبيا')),
              ButtonSegment(value: ChabakaThemeMode.dark, label: Text('داكن')),
            ],
            selected: {mode},
            onSelectionChanged: (s) => notifier.set(s.first),
          ),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: () => context.go(AppRoutes.home),
            child: const Text('العودة للرئيسية'),
          ),
        ],
      ),
    );
  }
}
