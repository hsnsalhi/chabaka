import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/persistence/settings_service.dart';
import '../../ui/theme/chabaka_colors.dart';
import '../../ui/theme/chabaka_theme.dart';
import '../../ui/theme/text_styles.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late bool _soundEnabled;
  late bool _hapticEnabled;

  @override
  void initState() {
    super.initState();
    final svc = ref.read(settingsServiceProvider);
    _soundEnabled = svc.soundEnabled;
    _hapticEnabled = svc.hapticEnabled;
  }

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(themeModeProvider);
    final themeNotifier = ref.read(themeModeProvider.notifier);
    final palette = ref.watch(paletteProvider);
    final paletteNotifier = ref.read(paletteProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('الإعدادات'),
        leading: BackButton(onPressed: () => Navigator.of(context).maybePop()),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          // ── Thème ──────────────────────────────────────────────────────────
          _SectionHeader(title: 'المظهر'),
          _ThemeSection(
            currentMode: mode,
            onChanged: (m) => themeNotifier.set(m),
          ),

          const SizedBox(height: 20),

          // ── Palette de couleurs ────────────────────────────────────────────
          _SectionHeader(title: 'الألوان'),
          _PaletteSection(
            current: palette,
            onChanged: (p) => paletteNotifier.set(p),
          ),

          const Divider(height: 32),

          // ── Sons ───────────────────────────────────────────────────────────
          _SectionHeader(title: 'الصوت والاهتزاز'),
          _ToggleTile(
            icon: Icons.volume_up_outlined,
            title: 'الأصوات',
            subtitle: 'أصوات النقر والإكمال',
            value: _soundEnabled,
            onChanged: (v) async {
              await ref.read(settingsServiceProvider).setSoundEnabled(v);
              setState(() => _soundEnabled = v);
            },
          ),
          _ToggleTile(
            icon: Icons.vibration_outlined,
            title: 'الاهتزاز',
            subtitle: 'ردود الفعل اللمسية',
            value: _hapticEnabled,
            onChanged: (v) async {
              await ref.read(settingsServiceProvider).setHapticEnabled(v);
              setState(() => _hapticEnabled = v);
            },
          ),

          const Divider(height: 32),

          // ── Réinitialisation ───────────────────────────────────────────────
          _SectionHeader(title: 'إعادة التعيين'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: OutlinedButton.icon(
              onPressed: () => _confirmReset(context),
              icon: Icon(Icons.restart_alt, color: ChabakaColors.error),
              label: Text(
                'إعادة تعيين كل الإعدادات',
                style: ChabakaTextStyles.label.copyWith(
                  color: ChabakaColors.error,
                ),
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: ChabakaColors.error, width: 1.5),
                minimumSize: const Size(double.infinity, 52),
              ),
            ),
          ),

          const Divider(height: 32),

          // ── À propos ───────────────────────────────────────────────────────
          _SectionHeader(title: 'حول التطبيق'),
          _AboutSection(),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Future<void> _confirmReset(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'إعادة تعيين الإعدادات',
          style: ChabakaTextStyles.h3,
          textDirection: TextDirection.rtl,
        ),
        content: Text(
          'سيتم إعادة جميع الإعدادات إلى الوضع الافتراضي. لن تُحذف الإحصائيات.',
          style: ChabakaTextStyles.bodySmall,
          textDirection: TextDirection.rtl,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: ChabakaColors.error),
            child: const Text('إعادة تعيين'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final svc = ref.read(settingsServiceProvider);
      await svc.setThemeMode(ChabakaThemeMode.light);
      await svc.setPalette(ChabakaPalette.classic);
      await svc.setSoundEnabled(true);
      await svc.setHapticEnabled(true);
      if (!mounted) return;
      ref.read(themeModeProvider.notifier).set(ChabakaThemeMode.light);
      ref.read(paletteProvider.notifier).set(ChabakaPalette.classic);
      setState(() {
        _soundEnabled = true;
        _hapticEnabled = true;
      });
      messenger.showSnackBar(
        SnackBar(
          content: Text('تمت إعادة التعيين', textDirection: TextDirection.rtl),
          backgroundColor: ChabakaColors.success,
        ),
      );
    }
  }
}

// ── Widgets internes ─────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 8),
      child: Text(
        title,
        style: ChabakaTextStyles.label.copyWith(
          color: context.brand.primary,
          fontWeight: FontWeight.w700,
          fontSize: 14,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _ThemeSection extends StatelessWidget {
  final ChabakaThemeMode currentMode;
  final ValueChanged<ChabakaThemeMode> onChanged;

  const _ThemeSection({required this.currentMode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _ThemeOption(
            label: 'فاتح',
            icon: Icons.light_mode_outlined,
            selected: currentMode == ChabakaThemeMode.light,
            onTap: () => onChanged(ChabakaThemeMode.light),
            bgColor: const Color(0xFFF8F8F4),
            fgColor: const Color(0xFF15192B),
          ),
          const SizedBox(width: 12),
          _ThemeOption(
            label: 'سيبيا',
            icon: Icons.book_outlined,
            selected: currentMode == ChabakaThemeMode.sepia,
            onTap: () => onChanged(ChabakaThemeMode.sepia),
            bgColor: const Color(0xFFF2E8D2),
            fgColor: const Color(0xFF2A1F0F),
          ),
          const SizedBox(width: 12),
          _ThemeOption(
            label: 'داكن',
            icon: Icons.dark_mode_outlined,
            selected: currentMode == ChabakaThemeMode.dark,
            onTap: () => onChanged(ChabakaThemeMode.dark),
            bgColor: const Color(0xFF0D1124),
            fgColor: const Color(0xFFE6E8F2),
          ),
        ],
      ),
    );
  }
}

class _ThemeOption extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final Color bgColor;
  final Color fgColor;

  const _ThemeOption({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    required this.bgColor,
    required this.fgColor,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Semantics(
        label: label,
        selected: selected,
        button: true,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: 80,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected
                    ? context.brand.primary
                    : ChabakaColors.outlineVariantLight,
                width: selected ? 2.5 : 1,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: context.brand.primary.withValues(alpha: 0.18),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: fgColor, size: 24),
                const SizedBox(height: 6),
                Text(
                  label,
                  style: ChabakaTextStyles.caption.copyWith(
                    color: fgColor,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Choix de la palette : une pastille par palette (marque + accent sur le
/// fond clair de la palette), nom en dessous.
class _PaletteSection extends StatelessWidget {
  final ChabakaPalette current;
  final ValueChanged<ChabakaPalette> onChanged;

  const _PaletteSection({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          for (final p in ChabakaPalette.values) ...[
            if (p != ChabakaPalette.values.first) const SizedBox(width: 8),
            _PaletteOption(
              palette: p,
              selected: p == current,
              onTap: () => onChanged(p),
            ),
          ],
        ],
      ),
    );
  }
}

class _PaletteOption extends StatelessWidget {
  final ChabakaPalette palette;
  final bool selected;
  final VoidCallback onTap;

  const _PaletteOption({
    required this.palette,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Semantics(
        label: palette.labelAr,
        selected: selected,
        button: true,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: 88,
            decoration: BoxDecoration(
              color: palette.bgLight,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? palette.primary : scheme.outlineVariant,
                width: selected ? 2.5 : 1,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: palette.primary.withValues(alpha: 0.18),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 34,
                  height: 34,
                  child: Stack(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: palette.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                      PositionedDirectional(
                        end: 0,
                        bottom: 0,
                        child: Container(
                          width: 15,
                          height: 15,
                          decoration: BoxDecoration(
                            color: palette.accent,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: palette.bgLight,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  palette.labelAr,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ChabakaTextStyles.caption.copyWith(
                    color: palette.onSurfaceLight,
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ToggleTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SwitchListTile(
      secondary: Icon(icon, color: context.brand.primary),
      title: Text(title, style: ChabakaTextStyles.label),
      subtitle: Text(
        subtitle,
        style: ChabakaTextStyles.caption.copyWith(
          color: scheme.onSurface.withValues(alpha: 0.6),
        ),
      ),
      value: value,
      onChanged: onChanged,
      activeThumbColor: context.brand.primary,
      activeTrackColor: context.brand.primary.withValues(alpha: 0.5),
      contentPadding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 0),
    );
  }
}

class _AboutSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: context.brand.primary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.grid_4x4,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'شبكة',
                        style: ChabakaTextStyles.h3.copyWith(
                          color: scheme.onSurface,
                          fontFamily: 'Amiri',
                        ),
                      ),
                      Text(
                        'الإصدار 1.1.0',
                        style: ChabakaTextStyles.caption.copyWith(
                          color: scheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'لعبة كلمات مسهمة عربية تعمل بالكامل دون اتصال بالإنترنت.',
                style: ChabakaTextStyles.bodySmall.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.75),
                  height: 1.6,
                ),
                textDirection: TextDirection.rtl,
              ),
              const SizedBox(height: 10),
              Text(
                'Inspired and designed by TechLYB',
                style: ChabakaTextStyles.caption.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.7),
                ),
                textDirection: TextDirection.ltr,
              ),
              const SizedBox(height: 2),
              Text(
                'contact@techlyb.com',
                style: ChabakaTextStyles.caption.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.7),
                ),
                textDirection: TextDirection.ltr,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
