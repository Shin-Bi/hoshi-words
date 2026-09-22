import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

String formatQuizAccuracyRecord({required int attempts, required int correct}) {
  if (attempts <= 0) return '정답률 없음';
  final safeCorrect = correct.clamp(0, attempts);
  final percent = (safeCorrect * 100 / attempts).round();
  return '정답률 $percent% ($safeCorrect/$attempts)';
}

/// A glowing star used on loading and brand surfaces.
class StarMark extends StatelessWidget {
  const StarMark({
    super.key,
    this.size = 72,
    this.glow = true,
    this.semanticsLabel = '별빛 단어 앱 로고',
  });

  final double size;
  final bool glow;
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: semanticsLabel,
      child: ExcludeSemantics(
        child: SizedBox.square(
          dimension: size,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.deepBlue,
              borderRadius: BorderRadius.circular(size * 0.3),
              border: Border.all(color: AppColors.moon.withValues(alpha: 0.45)),
              boxShadow: glow
                  ? [
                      BoxShadow(
                        color: AppColors.moon.withValues(alpha: 0.3),
                        blurRadius: size * 0.42,
                        spreadRadius: size * 0.04,
                      ),
                    ]
                  : null,
            ),
            child: Icon(
              Icons.star_rounded,
              size: size * 0.56,
              color: AppColors.moon,
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact square application mark suitable for an app bar.
class AppMark extends StatelessWidget {
  const AppMark({
    super.key,
    this.size = 40,
    this.icon = Icons.star_rounded,
    this.semanticsLabel = '별빛 단어 앱',
  });

  final double size;
  final IconData icon;
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: semanticsLabel,
      child: ExcludeSemantics(
        child: SizedBox.square(
          dimension: size,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.moon,
              borderRadius: BorderRadius.circular(size * 0.325),
            ),
            child: Icon(icon, size: size * 0.5, color: AppColors.ink),
          ),
        ),
      ),
    );
  }
}

/// A wrap-friendly pill control used for filters and display options.
class CompactToggle extends StatelessWidget {
  const CompactToggle({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.semanticsLabel,
    this.selectedIcon = Icons.check_rounded,
    this.unselectedIcon = Icons.remove_rounded,
    this.exclusiveSelection = false,
    this.minimumTapTargetHeight,
  });

  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? semanticsLabel;
  final IconData selectedIcon;
  final IconData unselectedIcon;
  final bool exclusiveSelection;
  final double? minimumTapTargetHeight;

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    final foreground = value
        ? Colors.white
        : enabled
        ? AppColors.body
        : AppColors.subtleText;

    return Semantics(
      button: true,
      checked: exclusiveSelection ? null : value,
      selected: exclusiveSelection ? value : null,
      enabled: enabled,
      label: semanticsLabel ?? '$label 선택',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? () => onChanged!(!value) : null,
          borderRadius: BorderRadius.circular(AppRadii.pill),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minimumTapTargetHeight ?? 0),
            child: Center(
              widthFactor: 1,
              child: AnimatedContainer(
                duration: AppDurations.fast,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: value ? AppColors.ink : AppColors.toggleSurface,
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      value ? selectedIcon : unselectedIcon,
                      size: 14,
                      color: value ? AppColors.moon : AppColors.subtleText,
                    ),
                    const SizedBox(width: AppSpacing.xxs),
                    Text(
                      label,
                      style: TextStyle(
                        color: foreground,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Consistent title/subtitle row for regular sections and dark hero sections.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.dark = false,
    this.padding,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final bool dark;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final subtitle = this.subtitle?.trim();
    final effectivePadding =
        padding ??
        (dark
            ? const EdgeInsets.fromLTRB(22, 26, 22, 28)
            : const EdgeInsets.fromLTRB(16, 18, 16, 14));

    return ColoredBox(
      color: dark ? AppColors.ink : Colors.transparent,
      child: Padding(
        padding: effectivePadding,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (leading != null) ...[
              leading!,
              const SizedBox(width: AppSpacing.lg),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: dark ? Colors.white : AppColors.ink,
                      fontSize: dark ? 27 : 22,
                      height: dark ? 1.25 : 1.35,
                      fontWeight: FontWeight.w800,
                      letterSpacing: dark ? -0.6 : -0.5,
                    ),
                  ),
                  if (subtitle != null && subtitle.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: dark
                            ? Colors.white.withValues(alpha: 0.68)
                            : AppColors.subtleText,
                        fontSize: 13,
                        height: 1.45,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: AppSpacing.lg),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Friendly, centered empty state with an optional action.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
    this.padding = const EdgeInsets.all(32),
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final message = this.message?.trim();

    return Center(
      child: Padding(
        padding: padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: AppColors.toggleSurface,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: AppColors.mutedBlue),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.ink,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (message != null && message.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.subtleText,
                  fontSize: 12,
                  height: 1.45,
                ),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: AppSpacing.xxl),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
