import 'package:flutter/material.dart';

import '../../domain/vocabulary.dart';
import '../../services/live_wallpaper_service.dart';
import '../../theme/app_theme.dart';
import 'common_widgets.dart';

Future<void> showLiveWallpaperSettingsSheet(
  BuildContext context, {
  required LiveWallpaperService service,
}) async {
  await service.refreshStatus();
  if (!context.mounted) return;
  await Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => _LiveWallpaperSettingsPage(service: service),
      settings: const RouteSettings(name: '/settings/live-wallpaper'),
    ),
  );
}

class _LiveWallpaperSettingsPage extends StatelessWidget {
  const _LiveWallpaperSettingsPage({required this.service});

  final LiveWallpaperService service;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('잠금화면 단어')),
      body: AnimatedBuilder(
        animation: service,
        builder: (context, _) {
          final enabled = service.isReady && service.isPlatformAvailable;
          final settings = service.settings;
          return SafeArea(
            top: false,
            child: SingleChildScrollView(
              key: const ValueKey('live-wallpaper-settings-page'),
              padding: EdgeInsets.fromLTRB(
                AppSpacing.screenHorizontal,
                AppSpacing.xl,
                AppSpacing.screenHorizontal,
                MediaQuery.viewInsetsOf(context).bottom +
                    AppSpacing.screenBottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _SheetHeader(),
                  const SizedBox(height: AppSpacing.xxl),
                  _StatusCard(service: service),
                  const SizedBox(height: AppSpacing.lg),
                  _SettingsCard(
                    service: service,
                    enabled: enabled,
                    settings: settings,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _DeckSummaryCard(service: service),
                  const SizedBox(height: AppSpacing.lg),
                  const _WallpaperTimerGuide(),
                  const SizedBox(height: AppSpacing.lg),
                  _SamsungGuide(isSamsung: service.status.isSamsung),
                  if (service.errorMessage case final error?) ...[
                    const SizedBox(height: AppSpacing.lg),
                    _ErrorBanner(message: error, onDismiss: service.clearError),
                  ],
                  const SizedBox(height: AppSpacing.xxl),
                  FilledButton.icon(
                    key: const ValueKey('live-wallpaper-apply-button'),
                    onPressed:
                        enabled &&
                            service.status.supported &&
                            !service.isBusy &&
                            service.availableWordCount > 0
                        ? () => _apply(context)
                        : null,
                    icon: service.isBusy
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.wallpaper_rounded),
                    label: const Text('배경화면 적용'),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  const Text(
                    '적용 버튼을 누르면 Android 미리보기에서 기기가 제공하는 적용 대상을 선택할 수 있어요.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.subtleText,
                      fontSize: 11,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _apply(BuildContext context) async {
    final opened = await service.applyWallpaper();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          opened
              ? '시스템 미리보기에서 기기가 제공하는 적용 대상을 선택해 주세요.'
              : service.errorMessage ?? '배경화면 선택기를 열지 못했어요.',
        ),
      ),
    );
  }
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader();

  @override
  Widget build(BuildContext context) {
    return const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppMark(
          size: 44,
          icon: Icons.wallpaper_rounded,
          semanticsLabel: '잠금화면 단어 설정',
        ),
        SizedBox(width: AppSpacing.lg),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '라이브 배경화면',
                style: TextStyle(
                  color: AppColors.ink,
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(height: AppSpacing.xxs),
              Text(
                '앱의 학습 범위와 별도로 단어 범위를 골라 라이브 배경화면으로 복습해요.',
                style: TextStyle(
                  color: AppColors.body,
                  fontSize: 12,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.service});

  final LiveWallpaperService service;

  @override
  Widget build(BuildContext context) {
    final status = service.status;
    final (icon, title, color) = !service.isReady || service.isBusy
        ? (Icons.sync_rounded, '기능 확인 중', AppColors.mutedBlue)
        : status.active
        ? (Icons.check_circle_rounded, '라이브 배경화면 사용 중', AppColors.success)
        : status.supported
        ? (Icons.auto_awesome_rounded, '이 기기에서 사용할 수 있어요', AppColors.bookmark)
        : (Icons.info_rounded, '현재 기기에서 사용할 수 없어요', AppColors.error);
    final message =
        status.message ??
        (status.active
            ? '표시 설정이나 단어 범위를 바꾸면 자동으로 반영돼요.'
            : status.supported
            ? '아래에서 설정한 뒤 Android 미리보기로 적용하세요.'
            : 'Android 라이브 배경화면 지원 여부를 확인해 주세요.');

    return Container(
      key: const ValueKey('live-wallpaper-status-card'),
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.panel),
        border: Border.all(color: AppColors.cardOutline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  message,
                  style: const TextStyle(
                    color: AppColors.body,
                    fontSize: 11,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.service,
    required this.enabled,
    required this.settings,
  });

  final LiveWallpaperService service;
  final bool enabled;
  final LiveWallpaperSettings settings;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.panel),
        border: Border.all(color: AppColors.cardOutline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile.adaptive(
            key: const ValueKey('live-wallpaper-enabled'),
            contentPadding: EdgeInsets.zero,
            value: settings.enabled,
            onChanged: enabled ? service.setEnabled : null,
            title: const Text(
              '라이브 배경화면 사용',
              style: TextStyle(
                color: AppColors.ink,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
            subtitle: const Text(
              '끄면 배경화면의 단어 표시만 멈추고 위젯은 계속 사용할 수 있어요. 완전히 해제하려면 시스템 설정에서 다른 배경을 선택하세요.',
            ),
          ),
          const Divider(),
          const SizedBox(height: AppSpacing.lg),
          SharedLockscreenWordSettings(
            service: service,
            settings: settings,
            enabled: enabled,
            keyPrefix: 'live-wallpaper',
            rangeTitle: '잠금화면 데모 범위',
            rangeDescription: '오늘·단어장·퀴즈의 범위와 별도이며, 단어 위젯도 이 범위를 함께 사용해요.',
          ),
        ],
      ),
    );
  }
}

/// Shared display and deck options used by both the live-wallpaper and widget
/// settings pages. [LiveWallpaperService] remains the single persistence and
/// native-sync source, so edits on either page are immediately reflected by
/// the other feature.
class SharedLockscreenWordSettings extends StatelessWidget {
  const SharedLockscreenWordSettings({
    super.key,
    required this.service,
    required this.settings,
    required this.enabled,
    required this.keyPrefix,
    required this.rangeTitle,
    required this.rangeDescription,
  });

  final LiveWallpaperService service;
  final LiveWallpaperSettings settings;
  final bool enabled;
  final String keyPrefix;
  final String rangeTitle;
  final String rangeDescription;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          rangeTitle,
          style: const TextStyle(
            color: AppColors.ink,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          rangeDescription,
          style: const TextStyle(
            color: AppColors.subtleText,
            fontSize: 10,
            height: 1.4,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final level in JlptLevel.values)
              _LevelChip(
                controlKey: ValueKey('$keyPrefix-level-${level.name}'),
                level: level,
                selected: settings.levels.contains(level),
                enabled: enabled,
                onChanged: (selected) {
                  final levels = Set<JlptLevel>.of(settings.levels);
                  selected ? levels.add(level) : levels.remove(level);
                  if (levels.isNotEmpty) service.setLevels(levels);
                },
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xxl),
        const Text(
          '표시 옵션',
          style: TextStyle(
            color: AppColors.ink,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            CompactToggle(
              key: ValueKey('$keyPrefix-show-reading'),
              label: '후리가나',
              value: settings.showReading,
              onChanged: enabled ? service.setShowReading : null,
            ),
            CompactToggle(
              key: ValueKey('$keyPrefix-show-meaning'),
              label: '뜻',
              value: settings.showMeaning,
              onChanged: enabled ? service.setShowMeaning : null,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xxl),
        const Text(
          '단어 필터',
          style: TextStyle(
            color: AppColors.ink,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            CompactToggle(
              key: ValueKey('$keyPrefix-exclude-known'),
              label: '외운 단어 제외',
              value: settings.excludeKnown,
              onChanged: enabled ? service.setExcludeKnown : null,
              selectedIcon: Icons.school_rounded,
              unselectedIcon: Icons.school_outlined,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xxl),
        const Text(
          '단어 순서',
          style: TextStyle(
            color: AppColors.ink,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final order in LockscreenWordOrder.values)
              ChoiceChip(
                key: ValueKey('$keyPrefix-order-${order.name}'),
                avatar: Icon(
                  switch (order) {
                    LockscreenWordOrder.basic =>
                      Icons.format_list_numbered_rounded,
                    LockscreenWordOrder.gojuon => Icons.sort_by_alpha_rounded,
                    LockscreenWordOrder.random => Icons.shuffle_rounded,
                  },
                  size: 15,
                  color: settings.order == order
                      ? AppColors.moon
                      : AppColors.subtleText,
                ),
                label: Text(
                  order == LockscreenWordOrder.random &&
                          settings.order == LockscreenWordOrder.random
                      ? '랜덤 · 다시 섞기'
                      : order.label,
                ),
                selected: settings.order == order,
                showCheckmark: false,
                onSelected: enabled ? (_) => service.setOrder(order) : null,
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xxl),
        const Text(
          '자동 교체 간격',
          style: TextStyle(
            color: AppColors.ink,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final interval in LiveWallpaperInterval.values)
              ChoiceChip(
                key: ValueKey('$keyPrefix-interval-${interval.minutes}'),
                label: Text(interval.label),
                selected: settings.interval == interval,
                showCheckmark: true,
                checkmarkColor: AppColors.moon,
                onSelected: enabled
                    ? (selected) {
                        if (selected) service.setInterval(interval);
                      }
                    : null,
              ),
          ],
        ),
      ],
    );
  }
}

class _LevelChip extends StatelessWidget {
  const _LevelChip({
    required this.controlKey,
    required this.level,
    required this.selected,
    required this.enabled,
    required this.onChanged,
  });

  final Key controlKey;
  final JlptLevel level;
  final bool selected;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      key: controlKey,
      label: Text(
        level.label,
        style: TextStyle(
          color: selected ? Colors.white : AppColors.body,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
      selected: selected,
      selectedColor: AppColors.ink,
      backgroundColor: AppColors.toggleSurface,
      checkmarkColor: AppColors.moon,
      side: BorderSide.none,
      onSelected: enabled ? onChanged : null,
    );
  }
}

class _DeckSummaryCard extends StatelessWidget {
  const _DeckSummaryCard({required this.service});

  final LiveWallpaperService service;

  @override
  Widget build(BuildContext context) {
    final levels = [
      for (final level in JlptLevel.values)
        if (service.settings.levels.contains(level)) level.label,
    ].join(' · ');
    return Container(
      key: const ValueKey('live-wallpaper-deck-summary'),
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: AppColors.deepBlue,
        borderRadius: BorderRadius.circular(AppRadii.panel),
      ),
      child: Row(
        children: [
          const Icon(Icons.style_rounded, color: AppColors.moon),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$levels · ${service.syncedWordCount}개 단어 · '
                  '${service.settings.order.label}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  service.availableWordCount > LiveWallpaperService.maxDeckSize
                      ? '선택 범위에서 ${service.settings.order.label}으로 '
                            '최대 ${LiveWallpaperService.maxDeckSize}개를 보내요'
                            '${service.settings.excludeKnown ? '. 외운 단어는 제외해요.' : '.'}'
                      : service.settings.excludeKnown
                      ? '선택 범위에서 외운 단어를 제외해요.'
                      : '선택 범위의 외운 단어도 함께 표시해요.',
                  style: const TextStyle(
                    color: AppColors.onDarkMuted,
                    fontSize: 11,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SamsungGuide extends StatelessWidget {
  const _SamsungGuide({required this.isSamsung});

  final bool isSamsung;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: AppColors.warmSurface,
        borderRadius: BorderRadius.circular(AppRadii.panel),
        border: Border.all(color: AppColors.cardOutline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.phone_android_rounded,
            color: isSamsung ? AppColors.bookmark : AppColors.mutedBlue,
          ),
          const SizedBox(width: AppSpacing.lg),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Samsung Galaxy 안내',
                  style: TextStyle(
                    color: AppColors.ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: AppSpacing.xxs),
                Text(
                  'One UI 버전에 따라 ‘홈 화면’ 또는 ‘홈 화면 및 잠금화면’만 제공될 수 있고 문구도 다를 수 있어요. 잠금화면 단독 적용이 보이지 않으면 ‘홈 화면 및 잠금화면’을 선택하세요. 절전 모드에서는 교체 시점이 조금 늦어질 수 있어요.',
                  style: TextStyle(
                    color: AppColors.body,
                    fontSize: 11,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WallpaperTimerGuide extends StatelessWidget {
  const _WallpaperTimerGuide();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('live-wallpaper-timer-guide'),
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.panel),
        border: Border.all(color: AppColors.cardOutline),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '자동 교체 타이머',
            style: TextStyle(
              color: AppColors.ink,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: AppSpacing.sm),
          Text(
            '라이브 배경화면은 표시 전용이에요. 카드 아래의 진행 표시와 남은 시간으로 다음 단어 교체 시점을 한눈에 확인할 수 있어요. 화면 절전 상태에서는 시스템 정책에 따라 갱신이 조금 늦어질 수 있어요.',
            style: TextStyle(color: AppColors.body, fontSize: 11, height: 1.55),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.errorContainer,
      borderRadius: BorderRadius.circular(AppRadii.control),
      child: Padding(
        padding: const EdgeInsets.only(left: AppSpacing.xl),
        child: Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: AppColors.error),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: AppColors.errorText,
                  fontSize: 11,
                  height: 1.45,
                ),
              ),
            ),
            IconButton(
              tooltip: '오류 안내 닫기',
              onPressed: onDismiss,
              icon: const Icon(Icons.close_rounded, color: AppColors.error),
            ),
          ],
        ),
      ),
    );
  }
}
