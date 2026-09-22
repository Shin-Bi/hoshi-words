import 'package:flutter/material.dart';

import '../../domain/vocabulary.dart';
import '../../services/live_wallpaper_service.dart';
import '../../services/word_widget_service.dart';
import '../../theme/app_theme.dart';
import 'common_widgets.dart';
import 'live_wallpaper_settings_sheet.dart';

Future<void> showWordWidgetSettingsSheet(
  BuildContext context, {
  required LiveWallpaperService liveWallpaperService,
  required WordWidgetService widgetService,
}) async {
  await widgetService.refreshStatus();
  if (!context.mounted) return;
  await Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => _WordWidgetSettingsPage(
        liveWallpaperService: liveWallpaperService,
        widgetService: widgetService,
      ),
      settings: const RouteSettings(name: '/settings/widget'),
    ),
  );
}

class _WordWidgetSettingsPage extends StatelessWidget {
  const _WordWidgetSettingsPage({
    required this.liveWallpaperService,
    required this.widgetService,
  });

  final LiveWallpaperService liveWallpaperService;
  final WordWidgetService widgetService;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('단어 위젯 설정')),
      body: AnimatedBuilder(
        animation: Listenable.merge([liveWallpaperService, widgetService]),
        builder: (context, _) {
          final status = widgetService.status;
          final settings = liveWallpaperService.settings;
          final settingsEnabled =
              liveWallpaperService.isReady &&
              liveWallpaperService.isPlatformAvailable;
          return SafeArea(
            top: false,
            child: SingleChildScrollView(
              key: const ValueKey('word-widget-settings-page'),
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
                  const _WidgetHeader(),
                  const SizedBox(height: AppSpacing.xxl),
                  _WidgetStatusCard(service: widgetService),
                  if (status.exactTimerSupported) ...[
                    const SizedBox(height: AppSpacing.lg),
                    _ExactTimerPermissionCard(service: widgetService),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  _WidgetSettingsCard(
                    service: liveWallpaperService,
                    settings: settings,
                    enabled: settingsEnabled,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _SyncedDeckCard(service: liveWallpaperService),
                  const SizedBox(height: AppSpacing.lg),
                  const _WidgetControlsCard(),
                  const SizedBox(height: AppSpacing.lg),
                  const _WidgetPlacementNotice(),
                  if (widgetService.errorMessage case final error?) ...[
                    const SizedBox(height: AppSpacing.lg),
                    _WidgetError(
                      message: error,
                      onDismiss: widgetService.clearError,
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xxl),
                  FilledButton.icon(
                    key: const ValueKey('word-widget-add-button'),
                    onPressed: !widgetService.isBusy && status.supported
                        ? () => _openPicker(context)
                        : null,
                    icon: widgetService.isBusy
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Icon(
                            status.canOpenPicker
                                ? Icons.add_to_home_screen_rounded
                                : Icons.help_outline_rounded,
                          ),
                    label: Text(
                      !status.canOpenPicker
                          ? '홈 위젯 추가 방법'
                          : status.homeWidgetAdded
                          ? '홈 위젯 더 추가'
                          : '홈 위젯 추가',
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

  Future<void> _openPicker(BuildContext context) async {
    final opened = await widgetService.openPicker();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          opened
              ? '시스템 안내에 따라 ‘별빛 단어 · 홈 화면’ 위젯을 배치해 주세요.'
              : widgetService.errorMessage ?? '위젯 선택기를 열지 못했어요.',
        ),
      ),
    );
  }
}

class _ExactTimerPermissionCard extends StatelessWidget {
  const _ExactTimerPermissionCard({required this.service});

  final WordWidgetService service;

  @override
  Widget build(BuildContext context) {
    final status = service.status;
    final granted = status.exactTimerGranted;
    return Container(
      key: const ValueKey('word-widget-exact-timer-card'),
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: granted ? Colors.white : AppColors.warmSurface,
        borderRadius: BorderRadius.circular(AppRadii.panel),
        border: Border.all(color: AppColors.cardOutline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            granted
                ? Icons.alarm_on_rounded
                : Icons.notification_important_outlined,
            color: granted ? AppColors.success : AppColors.bookmark,
            size: 22,
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  granted ? '정확한 타이머 사용 가능' : '정확한 타이머 권한 필요',
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  granted
                      ? '10초 경고와 제시간 교체를 정확하게 맞출 수 있어요. '
                            '알림·소리·기기 깨우기는 사용하지 않아요.'
                      : '10초 경고와 제시간 교체를 위해 알람 및 리마인더 '
                            '권한이 필요해요. 알림·소리·기기 깨우기는 '
                            '사용하지 않아요.',
                  style: const TextStyle(
                    color: AppColors.body,
                    fontSize: 11,
                    height: 1.5,
                  ),
                ),
                if (!granted) ...[
                  const SizedBox(height: AppSpacing.md),
                  OutlinedButton.icon(
                    key: const ValueKey(
                      'word-widget-exact-timer-settings-button',
                    ),
                    onPressed: service.isBusy
                        ? null
                        : () => _openSettings(context),
                    icon: service.isOpeningExactTimerSettings
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.settings_rounded),
                    label: const Text('알람 및 리마인더 설정 열기'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openSettings(BuildContext context) async {
    final opened = await service.openExactAlarmSettings();
    if (!context.mounted || opened) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(service.errorMessage ?? '설정을 열지 못했어요.')),
    );
  }
}

class _WidgetHeader extends StatelessWidget {
  const _WidgetHeader();

  @override
  Widget build(BuildContext context) {
    return const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppMark(
          size: 44,
          icon: Icons.widgets_rounded,
          semanticsLabel: '단어 위젯 설정',
        ),
        SizedBox(width: AppSpacing.lg),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '단어 위젯',
                style: TextStyle(
                  color: AppColors.ink,
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(height: AppSpacing.xxs),
              Text(
                '단어를 넘기고 학습 상태를 바꿀 수 있는 Android 위젯이에요.',
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

class _WidgetStatusCard extends StatelessWidget {
  const _WidgetStatusCard({required this.service});

  final WordWidgetService service;

  @override
  Widget build(BuildContext context) {
    final status = service.status;
    final (icon, title, color) = service.isBusy
        ? (Icons.sync_rounded, '위젯 확인 중', AppColors.mutedBlue)
        : status.added
        ? (Icons.check_circle_rounded, '위젯 사용 중', AppColors.success)
        : status.supported
        ? (Icons.widgets_rounded, '이 기기에서 추가할 수 있어요', AppColors.bookmark)
        : (Icons.info_rounded, '현재 기기에서 사용할 수 없어요', AppColors.error);
    final countLabel = status.widgetCount > 0
        ? '현재 ${status.widgetCount}개(홈 ${status.homeWidgetCount}개 · '
              '잠금화면 ${status.lockscreenWidgetCount}개)가 배치되어 있어요.'
        : null;
    return Container(
      key: const ValueKey('word-widget-status-card'),
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
                if (status.message ?? countLabel case final message?) ...[
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WidgetSettingsCard extends StatelessWidget {
  const _WidgetSettingsCard({
    required this.service,
    required this.settings,
    required this.enabled,
  });

  final LiveWallpaperService service;
  final LiveWallpaperSettings settings;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('word-widget-display-settings'),
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.panel),
        border: Border.all(color: AppColors.cardOutline),
      ),
      child: SharedLockscreenWordSettings(
        service: service,
        settings: settings,
        enabled: enabled,
        keyPrefix: 'word-widget',
        rangeTitle: '위젯 데모 범위',
        rangeDescription:
            '앱의 오늘·단어장·퀴즈 범위와는 별도예요. 이 설정은 잠금화면 단어와 공유되어 양쪽에 바로 반영돼요.',
      ),
    );
  }
}

class _SyncedDeckCard extends StatelessWidget {
  const _SyncedDeckCard({required this.service});

  final LiveWallpaperService service;

  @override
  Widget build(BuildContext context) {
    final levels = <String>[
      for (final level in JlptLevel.values)
        if (service.settings.levels.contains(level)) level.label,
    ].join(' · ');
    return Container(
      key: const ValueKey('word-widget-deck-summary'),
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: AppColors.deepBlue,
        borderRadius: BorderRadius.circular(AppRadii.panel),
      ),
      child: Row(
        children: [
          const Icon(Icons.sync_rounded, color: AppColors.moon),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$levels · 현재 ${service.syncedWordCount}개 동기화 · '
                  '${service.settings.order.label}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  service.settings.excludeKnown
                      ? '위젯과 잠금화면 단어가 같은 범위·순서·표시 '
                            '옵션·교체 간격을 사용하며, 외운 단어는 제외해요.'
                      : '위젯과 잠금화면 단어가 같은 범위·순서·표시 '
                            '옵션·교체 간격을 사용하며, 외운 단어도 포함해요.',
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

class _WidgetControlsCard extends StatelessWidget {
  const _WidgetControlsCard();

  @override
  Widget build(BuildContext context) {
    return Container(
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
            '위젯에서 할 수 있는 일',
            style: TextStyle(
              color: AppColors.ink,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: AppSpacing.sm),
          Text(
            '이전·다음 단어 이동, 타이머 다시 시작, 북마크, 외웠어요를 사용할 수 있어요. 홈·LockStar 위젯에서 단어를 누르면 잠금 해제 후 앱의 전체 상세로 이동해요.',
            style: TextStyle(color: AppColors.body, fontSize: 11, height: 1.55),
          ),
        ],
      ),
    );
  }
}

class _WidgetPlacementNotice extends StatelessWidget {
  const _WidgetPlacementNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: AppColors.warmSurface,
        borderRadius: BorderRadius.circular(AppRadii.panel),
        border: Border.all(color: AppColors.cardOutline),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.phone_android_rounded, color: AppColors.bookmark),
          SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Text(
              '홈에서는 ‘별빛 단어 · 홈 화면’을, Galaxy 잠금화면의 Good Lock·LockStar에서는 ‘별빛 단어 · 잠금화면’을 선택해 주세요. 두 위젯은 같은 단어·학습 상태를 공유해요. 단어 탭은 홈·LockStar 모두 앱 전체 상세로 연결되며, LockStar에서는 One UI 보안 정책에 따라 잠금 해제 후 화면이 열려요.',
              style: TextStyle(
                color: AppColors.body,
                fontSize: 11,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WidgetError extends StatelessWidget {
  const _WidgetError({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.errorContainer,
      borderRadius: BorderRadius.circular(AppRadii.control),
      child: ListTile(
        leading: const Icon(
          Icons.error_outline_rounded,
          color: AppColors.error,
        ),
        title: Text(
          message,
          style: const TextStyle(color: AppColors.errorText, fontSize: 11),
        ),
        trailing: IconButton(
          tooltip: '오류 안내 닫기',
          onPressed: onDismiss,
          icon: const Icon(Icons.close_rounded, color: AppColors.error),
        ),
      ),
    );
  }
}
