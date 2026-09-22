import 'package:flutter/material.dart';

import '../../application/study_controller.dart';
import '../../services/live_wallpaper_service.dart';
import '../../services/word_widget_service.dart';
import '../../theme/app_theme.dart';
import '../pages/sentence_analysis_page.dart';
import 'common_widgets.dart';
import 'linked_aozora_ruby_text.dart';
import 'live_wallpaper_settings_sheet.dart';
import 'source_info_sheet.dart';
import 'word_detail_sheet.dart';
import 'word_widget_settings_sheet.dart';

const _appVersion = String.fromEnvironment(
  'FLUTTER_BUILD_NAME',
  defaultValue: '0.1.0',
);

/// Opens settings as a normal page. The legacy name keeps existing callers
/// compatible while the presentation no longer uses nested bottom sheets.
Future<void> showSettingsHub(
  BuildContext context, {
  required StudyController controller,
  required LiveWallpaperService liveWallpaperService,
  required WordWidgetService widgetService,
  required ExampleWordLinkIndex linkIndex,
}) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => _SettingsHubPage(
        controller: controller,
        liveWallpaperService: liveWallpaperService,
        widgetService: widgetService,
        linkIndex: linkIndex,
      ),
      settings: const RouteSettings(name: '/settings'),
    ),
  );
}

class _SettingsHubPage extends StatelessWidget {
  const _SettingsHubPage({
    required this.controller,
    required this.liveWallpaperService,
    required this.widgetService,
    required this.linkIndex,
  });

  final StudyController controller;
  final LiveWallpaperService liveWallpaperService;
  final WordWidgetService widgetService;
  final ExampleWordLinkIndex linkIndex;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('설정')),
      body: ListView(
        key: const ValueKey('settings-hub-scroll'),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenHorizontal,
          AppSpacing.xl,
          AppSpacing.screenHorizontal,
          AppSpacing.screenBottom,
        ),
        children: [
          const _SettingsIntroduction(),
          const SizedBox(height: AppSpacing.xl),
          _SettingsDestinationCard(
            key: const ValueKey('settings-live-wallpaper'),
            icon: Icons.wallpaper_rounded,
            title: '잠금화면 단어',
            description: '라이브 배경화면의 단어 범위·표시·교체 간격을 설정해요.',
            onTap: () => showLiveWallpaperSettingsSheet(
              context,
              service: liveWallpaperService,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          _SettingsDestinationCard(
            key: const ValueKey('settings-widget'),
            icon: Icons.widgets_rounded,
            title: '단어 위젯',
            description: '공유 단어 범위와 표시 방법을 정하고 위젯을 추가해요.',
            onTap: () => showWordWidgetSettingsSheet(
              context,
              liveWallpaperService: liveWallpaperService,
              widgetService: widgetService,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          _SettingsDestinationCard(
            key: const ValueKey('settings-sentence-analysis'),
            icon: Icons.manage_search_rounded,
            title: '문장 분석',
            description: '작성한 일본어 문장에서 단어장 표현과 후리가나를 찾아요.',
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => _SentenceAnalysisSettingsPage(
                  controller: controller,
                  linkIndex: linkIndex,
                ),
                settings: const RouteSettings(
                  name: '/settings/sentence-analysis',
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          _SettingsDestinationCard(
            key: const ValueKey('settings-source-info'),
            icon: Icons.info_outline_rounded,
            title: '데이터 출처와 이용 안내',
            description: '데모 데이터의 구성과 소프트웨어 라이선스를 확인해요.',
            onTap: () => showSourceInfoSheet(
              context,
              totalWords: controller.words.length,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          _SettingsDestinationCard(
            key: const ValueKey('settings-other-information'),
            icon: Icons.tune_rounded,
            title: '기타 안내',
            description: '오프라인 학습과 앱 버전을 확인해요.',
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => const _OtherInformationPage(),
                settings: const RouteSettings(name: '/settings/more'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsIntroduction extends StatelessWidget {
  const _SettingsIntroduction();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: AppColors.deepBlue,
        borderRadius: BorderRadius.circular(AppRadii.panel),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppMark(size: 42, icon: Icons.settings_rounded, semanticsLabel: '설정'),
          SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '별빛 단어 설정',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: AppSpacing.xxs),
                Text(
                  '학습 도구·잠금화면·위젯과 앱 이용 정보를 한곳에서 관리해요.',
                  style: TextStyle(
                    color: AppColors.onDarkMuted,
                    fontSize: 12,
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

class _SettingsDestinationCard extends StatelessWidget {
  const _SettingsDestinationCard({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.panel),
        side: const BorderSide(color: AppColors.cardOutline),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.warmSurface,
                  borderRadius: BorderRadius.circular(AppRadii.control),
                ),
                alignment: Alignment.center,
                child: Icon(icon, color: AppColors.bookmark, size: 22),
              ),
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
                      description,
                      style: const TextStyle(
                        color: AppColors.body,
                        fontSize: 11,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.subtleText,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SentenceAnalysisSettingsPage extends StatelessWidget {
  const _SentenceAnalysisSettingsPage({
    required this.controller,
    required this.linkIndex,
  });

  final StudyController controller;
  final ExampleWordLinkIndex linkIndex;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const ValueKey('settings-sentence-analysis-page'),
      appBar: AppBar(title: const Text('문장 분석')),
      body: SentenceAnalysisPage(
        linkIndex: linkIndex,
        active: true,
        onOpenWord: (word) => showWordDetailPage(
          context,
          word: word,
          controller: controller,
          linkIndex: linkIndex,
        ),
      ),
    );
  }
}

class _OtherInformationPage extends StatelessWidget {
  const _OtherInformationPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('기타 안내')),
      body: ListView(
        key: const ValueKey('settings-other-information-page'),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenHorizontal,
          AppSpacing.xl,
          AppSpacing.screenHorizontal,
          AppSpacing.screenBottom,
        ),
        children: const [_OtherInformationCard()],
      ),
    );
  }
}

class _OtherInformationCard extends StatelessWidget {
  const _OtherInformationCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: AppColors.deepBlue,
        borderRadius: BorderRadius.circular(AppRadii.panel),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.tune_rounded, color: AppColors.moon, size: 20),
              SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  '기타 안내',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: AppSpacing.xl),
          _OtherInformationRow(
            icon: Icons.offline_bolt_rounded,
            title: '오프라인 학습',
            description: '단어·뜻·예문·활용형 카탈로그는 앱에 포함되어 있어요.',
          ),
          SizedBox(height: AppSpacing.xl),
          _OtherInformationRow(
            icon: Icons.apps_rounded,
            title: '앱 버전',
            description: _appVersion,
          ),
        ],
      ),
    );
  }
}

class _OtherInformationRow extends StatelessWidget {
  const _OtherInformationRow({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppColors.onDarkMuted, size: 18),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                description,
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
    );
  }
}
