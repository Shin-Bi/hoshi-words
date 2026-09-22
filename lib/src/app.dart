import 'package:flutter/material.dart';

import 'application/study_controller.dart';
import 'data/vocabulary_repository.dart';
import 'presentation/vocabulary_shell.dart';
import 'presentation/widgets/common_widgets.dart';
import 'services/live_wallpaper_service.dart';
import 'services/word_widget_service.dart';
import 'theme/app_theme.dart';

class VocabularyApp extends StatelessWidget {
  const VocabularyApp({
    super.key,
    this.controller,
    this.liveWallpaperService,
    this.wordWidgetService,
  });

  final StudyController? controller;
  final LiveWallpaperService? liveWallpaperService;
  final WordWidgetService? wordWidgetService;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '별빛 단어 · 공개 데모',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: controller == null
          ? _VocabularyAppLoader(
              liveWallpaperService: liveWallpaperService,
              wordWidgetService: wordWidgetService,
            )
          : VocabularyShell(
              controller: controller!,
              liveWallpaperService: liveWallpaperService,
              wordWidgetService: wordWidgetService,
            ),
    );
  }
}

class _VocabularyAppLoader extends StatefulWidget {
  const _VocabularyAppLoader({
    this.liveWallpaperService,
    this.wordWidgetService,
  });

  final LiveWallpaperService? liveWallpaperService;
  final WordWidgetService? wordWidgetService;

  @override
  State<_VocabularyAppLoader> createState() => _VocabularyAppLoaderState();
}

class _VocabularyAppLoaderState extends State<_VocabularyAppLoader> {
  late Future<StudyController> _future;
  StudyController? _loadedController;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<StudyController> _load() async {
    final words = await const VocabularyRepository().loadAll();
    final controller = await StudyController.create(words);
    if (_disposed) {
      controller.dispose();
    } else {
      _loadedController = controller;
    }
    return controller;
  }

  @override
  void dispose() {
    _disposed = true;
    _loadedController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<StudyController>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return VocabularyShell(
            controller: snapshot.data!,
            liveWallpaperService: widget.liveWallpaperService,
            wordWidgetService: widget.wordWidgetService,
          );
        }
        if (snapshot.hasError) {
          return _LoadError(
            message: snapshot.error.toString(),
            onRetry: () => setState(() => _future = _load()),
          );
        }
        return const _LoadingScreen();
      },
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.ink,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              StarMark(),
              SizedBox(height: 24),
              Text(
                '별빛 단어',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 25,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.6,
                ),
              ),
              SizedBox(height: 8),
              Text(
                '오늘의 일본어를 준비하고 있어요',
                style: TextStyle(color: AppColors.onDarkMuted, fontSize: 12),
              ),
              SizedBox(height: 24),
              SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.moon,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: EmptyState(
            icon: Icons.cloud_off_rounded,
            title: '단어장을 불러오지 못했어요',
            message: message,
            action: FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('다시 시도'),
            ),
          ),
        ),
      ),
    );
  }
}
