import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../application/study_controller.dart';
import '../domain/vocabulary.dart';
import '../domain/word_order.dart';

/// The intervals supported by the native live-wallpaper scheduler.
enum LiveWallpaperInterval {
  fiveMinutes(minutes: 5, label: '5분'),
  tenMinutes(minutes: 10, label: '10분'),
  thirtyMinutes(minutes: 30, label: '30분'),
  oneHour(minutes: 60, label: '1시간'),
  threeHours(minutes: 180, label: '3시간'),
  oneDay(minutes: 1440, label: '하루');

  const LiveWallpaperInterval({required this.minutes, required this.label});

  final int minutes;
  final String label;

  static LiveWallpaperInterval fromMinutes(int value) {
    return values.firstWhere(
      (interval) => interval.minutes == value,
      orElse: () => LiveWallpaperInterval.thirtyMinutes,
    );
  }
}

/// Ordering used only by the lock-screen wallpaper and word widgets.
///
/// It intentionally does not reuse the wordbook's sort setting because both
/// native surfaces share one bounded deck and one playback position.
enum LockscreenWordOrder {
  basic(label: '기본순'),
  gojuon(label: '오십음순'),
  random(label: '랜덤');

  const LockscreenWordOrder({required this.label});

  final String label;

  static LockscreenWordOrder fromName(String? value) {
    return values.firstWhere(
      (order) => order.name == value,
      orElse: () => LockscreenWordOrder.basic,
    );
  }
}

@immutable
class LiveWallpaperSettings {
  const LiveWallpaperSettings({
    this.enabled = false,
    this.showReading = true,
    this.showMeaning = true,
    this.excludeKnown = true,
    this.interval = LiveWallpaperInterval.thirtyMinutes,
    this.levels = const <JlptLevel>{JlptLevel.n5},
    this.order = LockscreenWordOrder.basic,
  });

  final bool enabled;
  final bool showReading;
  final bool showMeaning;
  final bool excludeKnown;
  final LiveWallpaperInterval interval;
  final Set<JlptLevel> levels;
  final LockscreenWordOrder order;

  LiveWallpaperSettings copyWith({
    bool? enabled,
    bool? showReading,
    bool? showMeaning,
    bool? excludeKnown,
    LiveWallpaperInterval? interval,
    Set<JlptLevel>? levels,
    LockscreenWordOrder? order,
  }) {
    return LiveWallpaperSettings(
      enabled: enabled ?? this.enabled,
      showReading: showReading ?? this.showReading,
      showMeaning: showMeaning ?? this.showMeaning,
      excludeKnown: excludeKnown ?? this.excludeKnown,
      interval: interval ?? this.interval,
      levels: levels ?? this.levels,
      order: order ?? this.order,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is LiveWallpaperSettings &&
            enabled == other.enabled &&
            showReading == other.showReading &&
            showMeaning == other.showMeaning &&
            excludeKnown == other.excludeKnown &&
            interval == other.interval &&
            order == other.order &&
            setEquals(levels, other.levels);
  }

  @override
  int get hashCode => Object.hash(
    enabled,
    showReading,
    showMeaning,
    excludeKnown,
    interval,
    order,
    Object.hashAll([
      for (final level in JlptLevel.values)
        if (levels.contains(level)) level,
    ]),
  );
}

@immutable
class LiveWallpaperStatus {
  const LiveWallpaperStatus({
    required this.supported,
    required this.active,
    this.isSamsung = false,
    this.message,
  });

  const LiveWallpaperStatus.loading()
    : supported = false,
      active = false,
      isSamsung = false,
      message = null;

  final bool supported;
  final bool active;
  final bool isSamsung;
  final String? message;

  factory LiveWallpaperStatus.fromPlatform(Object? value) {
    if (value is! Map) {
      return const LiveWallpaperStatus(supported: true, active: false);
    }
    final message = value['message'];
    final reportedSupport = value['supported'] ?? value['isSupported'];
    final setAllowed = value['isSetAllowed'];
    return LiveWallpaperStatus(
      supported:
          (reportedSupport is bool ? reportedSupport : true) &&
          (setAllowed is bool ? setAllowed : true),
      active: switch (value['active'] ?? value['isActive']) {
        final bool active => active,
        _ => false,
      },
      isSamsung: value['isSamsung'] is bool
          ? value['isSamsung'] as bool
          : false,
      message: message is String && message.trim().isNotEmpty
          ? message.trim()
          : null,
    );
  }
}

@immutable
class LiveWallpaperDetailRequest {
  const LiveWallpaperDetailRequest._({
    required this.wordId,
    required this.revealExamples,
    required this.actionIds,
    required List<String> actionIdKeys,
  }) : _actionIdKeys = actionIdKeys;

  final String wordId;
  final bool revealExamples;
  final List<String> actionIds;
  final List<String> _actionIdKeys;
}

/// Platform contract used by the Flutter settings UI and Android host.
///
/// Channel: `app.shinbi.tsuki_words/live_wallpaper`
///
/// * `syncConfig` receives `enabled`, `intervalMinutes`, `showReading`,
///   `showMeaning`, `excludeKnown`, `levels`, and a `deck` of at most 128
///   entries.
/// * Every deck entry keeps the legacy `id`, `word`, `reading`, `meaning`,
///   `level`, `bookmark`, `known`, `example`, and `exampleMeaning` fields used
///   by the compact widget. It also includes `partOfSpeech`,
///   `conjugationClass`, all `readings`, `meanings`, `usageNotes`, the word
///   `note`, quiz totals, `forms`, and complete `examples` for the
///   device-protected native detail preview.
/// * `openPicker` opens Android's live-wallpaper preview/picker.
/// * `getStatus` returns `supported`, `active`, optional `isSamsung`, and an
///   optional user-facing `message`.
/// * `drainPendingActions` (alias `drainActions`) returns actions created by
///   the interactive widget: String `id` and `wordId`, `bookmark`/`known`
///   desired state or `openDetails`, plus epoch-millisecond `createdAt`.
///   Flutter persists state, synchronizes the resulting deck, and then calls
///   `ackPendingActions` (alias `ackActions`) with String `actionIds`. Detail
///   actions are acked after navigation starts.
/// * `consumeLaunchWordId` consumes one-shot widget launch details delivered
///   directly to `MainActivity`. New Android hosts return `wordId` and
///   `revealExamples`; the legacy String word id remains accepted.
abstract interface class LiveWallpaperPlatformGateway {
  Future<void> syncConfiguration(Map<String, Object?> configuration);

  Future<void> openPicker();

  Future<Object?> getStatus();

  Future<Object?> drainPendingActions();

  Future<void> acknowledgePendingActions(List<String> actionIds);

  Future<Object?> consumeLaunchWordId();
}

class MethodChannelLiveWallpaperGateway
    implements LiveWallpaperPlatformGateway {
  const MethodChannelLiveWallpaperGateway();

  static const channel = MethodChannel('app.shinbi.tsuki_words/live_wallpaper');

  @override
  Future<Object?> getStatus() => channel.invokeMethod<Object?>('getStatus');

  @override
  Future<Object?> drainPendingActions() async {
    try {
      return await channel.invokeMethod<Object?>('drainPendingActions');
    } on MissingPluginException {
      return channel.invokeMethod<Object?>('drainActions');
    }
  }

  @override
  Future<void> acknowledgePendingActions(List<String> actionIds) async {
    final arguments = <String, Object?>{'actionIds': actionIds};
    try {
      await channel.invokeMethod<void>('ackPendingActions', arguments);
    } on MissingPluginException {
      await channel.invokeMethod<void>('ackActions', arguments);
    }
  }

  @override
  Future<Object?> consumeLaunchWordId() {
    return channel.invokeMethod<Object?>('consumeLaunchWordId');
  }

  @override
  Future<void> openPicker() => channel.invokeMethod<void>('openPicker');

  @override
  Future<void> syncConfiguration(Map<String, Object?> configuration) {
    return channel.invokeMethod<void>('syncConfig', configuration);
  }
}

/// Owns persisted display settings and keeps native wallpaper data in sync.
///
/// The service listens to [StudyController], but compares the complete native
/// payload before scheduling a channel call. Relevant bookmark/known, range,
/// and deck changes stay synchronized for the widget even while the wallpaper
/// is off; unrelated changes such as a card-index move trigger no platform
/// work.
class LiveWallpaperService extends ChangeNotifier {
  LiveWallpaperService({
    LiveWallpaperPlatformGateway? gateway,
    bool? platformAvailable,
    Future<SharedPreferences> Function()? preferencesLoader,
  }) : _gateway = gateway ?? const MethodChannelLiveWallpaperGateway(),
       _platformAvailable =
           platformAvailable ??
           (!kIsWeb && defaultTargetPlatform == TargetPlatform.android),
       _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance;

  static const maxDeckSize = 128;
  static const _prefix = 'kotobaMoon.liveWallpaper.';
  static const _enabledKey = '${_prefix}enabled';
  static const _showReadingKey = '${_prefix}showReading';
  static const _showMeaningKey = '${_prefix}showMeaning';
  static const _excludeKnownKey = '${_prefix}excludeKnown';
  static const _intervalKey = '${_prefix}intervalMinutes';
  static const _levelsKey = '${_prefix}levels';
  static const _levelsMigratedKey = '${_prefix}levelsMigrated';
  static const _orderKey = '${_prefix}order';
  static const _randomSeedKey = '${_prefix}randomSeed';

  final LiveWallpaperPlatformGateway _gateway;
  final bool _platformAvailable;
  final Future<SharedPreferences> Function() _preferencesLoader;

  LiveWallpaperSettings _settings = const LiveWallpaperSettings();
  LiveWallpaperStatus _status = const LiveWallpaperStatus.loading();
  StudyController? _controller;
  SharedPreferences? _preferences;
  Future<void> _ready = Future<void>.value();
  Future<void> _pendingSync = Future<void>.value();
  Future<void> _pendingActionDrain = Future<void>.value();
  final List<LiveWallpaperDetailRequest> _detailRequests = [];
  final Set<String> _queuedDetailActionIds = {};
  String? _lastScheduledSignature;
  String? _errorMessage;
  int _generation = 0;
  bool _initialized = false;
  bool _checkingStatus = false;
  bool _drainingActions = false;
  bool _applyingPendingActions = false;
  bool _controllerSyncScheduled = false;
  bool _openingPicker = false;
  bool _disposed = false;
  int _randomSeed = 0;

  LiveWallpaperSettings get settings => _settings;
  LiveWallpaperStatus get status => _status;
  String? get errorMessage => _errorMessage;
  bool get isReady => _initialized;
  bool get isPlatformAvailable => _platformAvailable;
  bool get isBusy => _checkingStatus || _drainingActions || _openingPicker;
  Future<void> get ready => _ready;

  int get availableWordCount => _eligibleWords.length;
  int get syncedWordCount => availableWordCount.clamp(0, maxDeckSize);
  bool get hasPendingDetailRequest => _detailRequests.isNotEmpty;

  LiveWallpaperDetailRequest? takeNextDetailRequest() {
    if (_detailRequests.isEmpty) return null;
    return _detailRequests.removeAt(0);
  }

  Future<bool> acknowledgeDetailRequest(
    LiveWallpaperDetailRequest request,
  ) async {
    if (!_platformAvailable || _disposed) return false;
    try {
      if (request.actionIds.isNotEmpty) {
        await _gateway.acknowledgePendingActions(request.actionIds);
      }
      _queuedDetailActionIds.removeAll(request._actionIdKeys);
      _errorMessage = null;
      _notifySafely();
      return true;
    } on MissingPluginException {
      _queuedDetailActionIds.removeAll(request._actionIdKeys);
    } on PlatformException catch (error) {
      _queuedDetailActionIds.removeAll(request._actionIdKeys);
      _recordPlatformError(error.message ?? '상세 화면 요청을 확인하지 못했어요.');
    } catch (_) {
      _queuedDetailActionIds.removeAll(request._actionIdKeys);
      _recordPlatformError('상세 화면 요청을 확인하지 못했어요.');
    }
    _notifySafely();
    return false;
  }

  Future<void> connect(StudyController controller) {
    if (identical(_controller, controller) && _initialized) return _ready;
    _controller?.removeListener(_handleStudyChange);
    _controller = controller..addListener(_handleStudyChange);
    final generation = ++_generation;
    _initialized = false;
    _ready = _initialize(generation);
    return _ready;
  }

  void disconnect([StudyController? controller]) {
    if (controller != null && !identical(_controller, controller)) return;
    _controller?.removeListener(_handleStudyChange);
    _controller = null;
    _generation += 1;
  }

  Future<void> _initialize(int generation) async {
    final preferences = await _preferencesLoader();
    if (_disposed || generation != _generation) return;
    _preferences = preferences;
    final storedLevels = _parseStoredLevels(
      preferences.getStringList(_levelsKey),
    );
    final hasMigratedLevels = preferences.getBool(_levelsMigratedKey) ?? false;
    final storedRandomSeed = preferences.getInt(_randomSeedKey);
    _randomSeed = storedRandomSeed ?? _newRandomSeed();
    final initialLevels = storedLevels.isNotEmpty
        ? storedLevels
        : !hasMigratedLevels
        ? Set<JlptLevel>.of(
            _controller?.selectedWordLevels ?? const <JlptLevel>{JlptLevel.n5},
          )
        : const <JlptLevel>{JlptLevel.n5};
    _settings = LiveWallpaperSettings(
      enabled: preferences.getBool(_enabledKey) ?? false,
      showReading: preferences.getBool(_showReadingKey) ?? true,
      showMeaning: preferences.getBool(_showMeaningKey) ?? true,
      excludeKnown: preferences.getBool(_excludeKnownKey) ?? true,
      interval: LiveWallpaperInterval.fromMinutes(
        preferences.getInt(_intervalKey) ?? 30,
      ),
      levels: Set<JlptLevel>.unmodifiable(initialLevels),
      order: LockscreenWordOrder.fromName(preferences.getString(_orderKey)),
    );
    if (!hasMigratedLevels ||
        storedLevels.isEmpty ||
        storedRandomSeed == null) {
      await Future.wait(<Future<bool>>[
        if (!hasMigratedLevels || storedLevels.isEmpty) ...[
          preferences.setStringList(
            _levelsKey,
            _orderedLevelNames(initialLevels),
          ),
          preferences.setBool(_levelsMigratedKey, true),
        ],
        if (storedRandomSeed == null)
          preferences.setInt(_randomSeedKey, _randomSeed),
      ]);
      if (_disposed || generation != _generation) return;
    }
    _initialized = true;
    _notifySafely();
    await refreshStatus();
    if (_disposed || generation != _generation) return;
    _scheduleConfiguration();
    await flushPendingSync();
  }

  Future<void> setEnabled(bool value) {
    return _updateSettings(_settings.copyWith(enabled: value));
  }

  Future<void> setShowReading(bool value) {
    return _updateSettings(_settings.copyWith(showReading: value));
  }

  Future<void> setShowMeaning(bool value) {
    return _updateSettings(_settings.copyWith(showMeaning: value));
  }

  Future<void> setExcludeKnown(bool value) {
    return _updateSettings(_settings.copyWith(excludeKnown: value));
  }

  Future<void> setInterval(LiveWallpaperInterval value) {
    return _updateSettings(_settings.copyWith(interval: value));
  }

  /// Changes the shared lock-screen/widget ordering. Selecting random again
  /// creates a new persistent seed; every other synchronization keeps it.
  Future<void> setOrder(LockscreenWordOrder value) async {
    if (!_initialized || !_platformAvailable) return;
    if (value != _settings.order) {
      await _updateSettings(_settings.copyWith(order: value));
      return;
    }
    if (value != LockscreenWordOrder.random) return;
    _randomSeed = _newRandomSeed();
    _errorMessage = null;
    _notifySafely();
    await _preferences?.setInt(_randomSeedKey, _randomSeed);
    _scheduleConfiguration();
    await flushPendingSync();
  }

  /// Changes only the lock-screen/widget range. The app's study range is
  /// intentionally independent and is never mutated here.
  Future<void> setLevels(Set<JlptLevel> levels) {
    if (levels.isEmpty) return Future<void>.value();
    return _updateSettings(
      _settings.copyWith(levels: Set<JlptLevel>.unmodifiable(levels)),
    );
  }

  Future<void> _updateSettings(LiveWallpaperSettings next) async {
    if (!_initialized || !_platformAvailable || _settings == next) return;
    _settings = next;
    _errorMessage = null;
    _notifySafely();
    final preferences = _preferences;
    if (preferences != null) {
      await Future.wait([
        preferences.setBool(_enabledKey, next.enabled),
        preferences.setBool(_showReadingKey, next.showReading),
        preferences.setBool(_showMeaningKey, next.showMeaning),
        preferences.setBool(_excludeKnownKey, next.excludeKnown),
        preferences.setInt(_intervalKey, next.interval.minutes),
        preferences.setStringList(_levelsKey, _orderedLevelNames(next.levels)),
        preferences.setBool(_levelsMigratedKey, true),
        preferences.setString(_orderKey, next.order.name),
        preferences.setInt(_randomSeedKey, _randomSeed),
      ]);
    }
    // The interactive widget reuses this deck even while the live wallpaper
    // is off, so every relevant display/range change remains synchronized.
    _scheduleConfiguration();
    await flushPendingSync();
  }

  Future<void> refreshStatus() async {
    if (!_platformAvailable) {
      _status = const LiveWallpaperStatus(
        supported: false,
        active: false,
        message: '라이브 배경화면은 Android 기기에서 사용할 수 있어요.',
      );
      _notifySafely();
      return;
    }
    _checkingStatus = true;
    _notifySafely();
    try {
      _status = LiveWallpaperStatus.fromPlatform(await _gateway.getStatus());
      _errorMessage = null;
    } on MissingPluginException {
      _status = const LiveWallpaperStatus(
        supported: false,
        active: false,
        message: '이 빌드에서는 라이브 배경화면 기능을 사용할 수 없어요.',
      );
    } on PlatformException catch (error) {
      _recordPlatformError(error.message ?? '배경화면 상태를 확인하지 못했어요.');
    } catch (_) {
      _recordPlatformError('배경화면 상태를 확인하지 못했어요.');
    } finally {
      _checkingStatus = false;
      _notifySafely();
    }
    await drainPendingActions();
    await _consumeLaunchWordId();
  }

  Future<void> _consumeLaunchWordId() async {
    final controller = _controller;
    if (!_initialized ||
        !_platformAvailable ||
        controller == null ||
        _disposed) {
      return;
    }
    try {
      final source = await _gateway.consumeLaunchWordId();
      final launch = _parseLaunchDetails(source);
      final wordId = launch.wordId;
      if (wordId.isEmpty || controller.wordById(wordId) == null || _disposed) {
        return;
      }
      _detailRequests.add(
        LiveWallpaperDetailRequest._(
          wordId: wordId,
          revealExamples: launch.revealExamples,
          actionIds: const <String>[],
          actionIdKeys: const <String>[],
        ),
      );
      _errorMessage = null;
      _notifySafely();
    } on MissingPluginException {
      // Older builds do not support direct home-widget navigation.
    } on PlatformException catch (error) {
      _recordPlatformError(error.message ?? '홈 위젯 상세 화면을 열지 못했어요.');
    } catch (_) {
      _recordPlatformError('홈 위젯 상세 화면을 열지 못했어요.');
    }
  }

  ({String wordId, bool revealExamples}) _parseLaunchDetails(Object? source) {
    if (source is String) {
      return (wordId: source.trim(), revealExamples: false);
    }
    if (source is Map<Object?, Object?>) {
      final wordId = source['wordId'];
      return (
        wordId: wordId is String ? wordId.trim() : '',
        revealExamples: source['revealExamples'] == true,
      );
    }
    return (wordId: '', revealExamples: false);
  }

  /// Applies widget actions in desired-state form, then syncs and acks.
  ///
  /// Native keeps actions pending until the acknowledgement. Re-delivery is
  /// therefore safe: Flutter compares each desired value with the current
  /// controller state instead of toggling blindly.
  Future<void> drainPendingActions() {
    final generation = _generation;
    _pendingActionDrain = _pendingActionDrain.then(
      (_) => _drainPendingActionsNow(generation),
    );
    return _pendingActionDrain;
  }

  Future<void> _drainPendingActionsNow(int generation) async {
    final controller = _controller;
    if (!_initialized ||
        !_platformAvailable ||
        controller == null ||
        _disposed ||
        generation != _generation) {
      return;
    }

    _drainingActions = true;
    _notifySafely();
    try {
      final source = await _gateway.drainPendingActions();
      if (_disposed ||
          generation != _generation ||
          !identical(controller, _controller)) {
        return;
      }
      final actions = _parsePendingActions(source);
      if (actions.isEmpty) return;

      final actionById = <String, _PendingWallpaperAction>{};
      for (final action in actions) {
        final existing = actionById[action.idKey];
        if (existing == null || action.compareChronology(existing) >= 0) {
          actionById[action.idKey] = action;
        }
      }
      final ordered = actionById.values.toList()..sort(_comparePendingActions);
      final effectiveByTarget = <String, _PendingWallpaperAction>{};
      final detailActions = <_PendingWallpaperAction>[];
      for (final action in ordered) {
        if (action.action == _WallpaperActionType.openDetails) {
          detailActions.add(action);
          continue;
        }
        effectiveByTarget[action.targetKey] = action;
      }

      // A user-visible detail request is independent from bookmark/known
      // persistence and from the 128-word configuration sync. Queue it as
      // soon as its word id is valid so an unrelated native sync failure can
      // never swallow an explicit widget tap.
      final validDetails = detailActions
          .where((action) => controller.wordById(action.wordId) != null)
          .toList(growable: false);
      if (validDetails.isNotEmpty) {
        final unqueued = validDetails
            .where((action) => !_queuedDetailActionIds.contains(action.idKey))
            .toList(growable: false);
        if (unqueued.isNotEmpty) {
          final latest = unqueued.last;
          _queuedDetailActionIds.addAll(unqueued.map((action) => action.idKey));
          _detailRequests.add(
            LiveWallpaperDetailRequest._(
              wordId: latest.wordId,
              revealExamples: false,
              actionIds: unqueued
                  .map((action) => action.id)
                  .toList(growable: false),
              actionIdKeys: unqueued
                  .map((action) => action.idKey)
                  .toList(growable: false),
            ),
          );
        }
      }

      _applyingPendingActions = true;
      try {
        for (final action in effectiveByTarget.values) {
          if (controller.wordById(action.wordId) == null) continue;
          switch (action.action) {
            case _WallpaperActionType.bookmark:
              controller.setBookmarked(
                action.wordId,
                action.value,
                changedAt: action.occurredAt,
              );
              break;
            case _WallpaperActionType.known:
              controller.setKnown(
                action.wordId,
                action.value,
                changedAt: action.occurredAt,
              );
              break;
            case _WallpaperActionType.openDetails:
              break;
          }
        }
      } finally {
        _applyingPendingActions = false;
      }
      // Re-delivered desired-state actions may already match in-memory state
      // after an earlier failed write. Always use a strict flush when at least
      // one state action is pending so dirty state is retried before ACK.
      final stateActionIds = <String>[
        for (final action in ordered)
          if (action.action != _WallpaperActionType.openDetails) action.id,
      ];
      if (stateActionIds.isNotEmpty) {
        await controller.flushPendingWrites(throwOnError: true);
        if (_disposed || generation != _generation) return;
        final synchronized = await _scheduleConfiguration(force: true);
        if (!synchronized || _disposed || generation != _generation) return;
        await _gateway.acknowledgePendingActions(stateActionIds);
      }

      final invalidDetailIds = <String>[
        for (final action in detailActions)
          if (controller.wordById(action.wordId) == null) action.id,
      ];
      if (invalidDetailIds.isNotEmpty) {
        await _gateway.acknowledgePendingActions(invalidDetailIds);
      }
      _errorMessage = null;
    } on MissingPluginException {
      // Older builds have no action queue. Status/configuration still work.
    } on PlatformException catch (error) {
      _recordPlatformError(error.message ?? '위젯 조작을 앱에 반영하지 못했어요.');
    } catch (_) {
      _recordPlatformError('위젯 조작을 앱에 반영하지 못했어요.');
    } finally {
      _drainingActions = false;
      _notifySafely();
    }
  }

  /// Enables the feature, synchronizes the latest deck, and opens the picker.
  Future<bool> applyWallpaper() async {
    if (!_initialized || !_platformAvailable || !_status.supported) {
      _errorMessage = _status.message ?? '이 기기에서는 적용할 수 없어요.';
      _notifySafely();
      return false;
    }
    if (availableWordCount == 0) {
      _errorMessage = '현재 범위에 표시할 단어가 없어요.';
      _notifySafely();
      return false;
    }
    if (!_settings.enabled) await setEnabled(true);
    _scheduleConfiguration(force: true);
    await flushPendingSync();
    if (_errorMessage != null) return false;

    _openingPicker = true;
    _notifySafely();
    try {
      await _gateway.openPicker();
      await refreshStatus();
      return true;
    } on MissingPluginException {
      _recordPlatformError('이 빌드에서는 배경화면 선택기를 열 수 없어요.');
    } on PlatformException catch (error) {
      _recordPlatformError(error.message ?? '배경화면 선택기를 열지 못했어요.');
    } catch (_) {
      _recordPlatformError('배경화면 선택기를 열지 못했어요.');
    } finally {
      _openingPicker = false;
      _notifySafely();
    }
    return false;
  }

  void clearError() {
    if (_errorMessage == null) return;
    _errorMessage = null;
    _notifySafely();
  }

  void _handleStudyChange() {
    if (!_initialized || _applyingPendingActions || _controllerSyncScheduled) {
      return;
    }
    _controllerSyncScheduled = true;
    scheduleMicrotask(() {
      if (_controllerSyncScheduled) _flushScheduledControllerSync();
    });
  }

  void _flushScheduledControllerSync() {
    _controllerSyncScheduled = false;
    if (_disposed || !_initialized || _applyingPendingActions) {
      return;
    }
    _scheduleConfiguration();
  }

  Future<bool> _scheduleConfiguration({bool force = false}) {
    final configuration = _buildConfiguration();
    if (configuration == null) return Future<bool>.value(false);
    final signature = _configurationSignature(configuration);
    if (!force && signature == _lastScheduledSignature) {
      return Future<bool>.value(true);
    }
    _lastScheduledSignature = signature;
    final completion = Completer<bool>();
    _pendingSync = _pendingSync.then((_) async {
      if (!_platformAvailable || _disposed) {
        completion.complete(false);
        return;
      }
      var synchronized = false;
      try {
        await _gateway.syncConfiguration(configuration);
        _errorMessage = null;
        synchronized = true;
      } on MissingPluginException {
        _status = const LiveWallpaperStatus(
          supported: false,
          active: false,
          message: '이 빌드에서는 라이브 배경화면 기능을 사용할 수 없어요.',
        );
      } on PlatformException catch (error) {
        _recordPlatformError(error.message ?? '배경화면 단어를 동기화하지 못했어요.');
      } catch (_) {
        _recordPlatformError('배경화면 단어를 동기화하지 못했어요.');
      } finally {
        if (!synchronized && _lastScheduledSignature == signature) {
          _lastScheduledSignature = null;
        }
        completion.complete(synchronized);
        _notifySafely();
      }
    });
    return completion.future;
  }

  Map<String, Object?>? _buildConfiguration() {
    final controller = _controller;
    if (!_initialized || controller == null) return null;
    final levels = _orderedLevelNames(_settings.levels);
    final deck = <Map<String, Object?>>[
      for (final word in _syncedDeckWords)
        {
          'id': word.id,
          'word': word.lemma,
          'reading': word.readings.join('・'),
          'readings': word.readings,
          'alternativeReadings': word.alternativeReadings,
          'meaning': word.primaryMeaning,
          'partOfSpeech': word.partOfSpeech.labelKo,
          'conjugationClass': word.conjugationClass.labelKo,
          'meanings': word.meanings,
          'usageNotes': word.usageNotes,
          'note': word.note,
          'quizAttempts': controller.quizAttemptsFor(word.id),
          'quizCorrect': controller.quizCorrectFor(word.id),
          'forms': <Map<String, Object?>>[
            for (final form in word.forms)
              <String, Object?>{
                'label': form.kind.labelKo,
                'surface': form.surface,
                'reading': form.reading,
                'note': form.note,
              },
          ],
          'examples': <Map<String, Object?>>[
            for (final example in word.examples)
              <String, Object?>{
                'original': example.original,
                'ruby': example.ruby,
                'literalTranslation': example.literalTranslation,
                'naturalTranslation': example.naturalTranslation,
                'focusSurface': example.focusSurface,
                'formKind': example.formKind?.labelKo ?? '',
                'note': example.note,
              },
          ],
          'level': word.level.name,
          'bookmark': controller.isBookmarked(word.id),
          'known': controller.isKnown(word.id),
          'example': word.examples.isEmpty ? '' : word.examples.first.original,
          'exampleMeaning': word.examples.isEmpty
              ? ''
              : word.examples.first.naturalTranslation.trim().isNotEmpty
              ? word.examples.first.naturalTranslation
              : word.examples.first.literalTranslation,
        },
    ];
    return <String, Object?>{
      'enabled': _settings.enabled,
      'intervalMinutes': _settings.interval.minutes,
      'showReading': _settings.showReading,
      'showMeaning': _settings.showMeaning,
      'excludeKnown': _settings.excludeKnown,
      'levels': levels,
      'deck': deck,
    };
  }

  List<JapaneseWord> get _eligibleWords {
    final controller = _controller;
    if (controller == null) return const <JapaneseWord>[];
    return <JapaneseWord>[
      for (final word in controller.words)
        if (_settings.levels.contains(word.level) &&
            (!_settings.excludeKnown || !controller.isKnown(word.id)))
          word,
    ];
  }

  List<JapaneseWord> get _syncedDeckWords {
    final controller = _controller;
    if (controller == null) return const <JapaneseWord>[];
    final selectedLevels = <JlptLevel>[
      for (final level in JlptLevel.values)
        if (_settings.levels.contains(level)) level,
    ];
    final wordsByLevel = <JlptLevel, List<JapaneseWord>>{
      for (final level in selectedLevels) level: <JapaneseWord>[],
    };
    final catalogOrder = <String, int>{
      for (var index = 0; index < controller.words.length; index++)
        controller.words[index].id: index,
    };
    for (final word in _eligibleWords) {
      wordsByLevel[word.level]!.add(word);
    }
    final comparator = _orderComparator(catalogOrder);
    if (_settings.order != LockscreenWordOrder.basic) {
      for (final bucket in wordsByLevel.values) {
        bucket.sort(comparator);
      }
    }

    // Select each level fairly before applying a global presentation order.
    // Basic intentionally remains the exact legacy round-robin sequence.
    final result = <JapaneseWord>[];
    for (var index = 0; result.length < maxDeckSize; index++) {
      var added = false;
      for (final level in selectedLevels) {
        final bucket = wordsByLevel[level]!;
        if (index < bucket.length) {
          result.add(bucket[index]);
          added = true;
          if (result.length == maxDeckSize) break;
        }
      }
      if (!added) break;
    }
    if (_settings.order != LockscreenWordOrder.basic) {
      result.sort(comparator);
    }
    return result;
  }

  Comparator<JapaneseWord> _orderComparator(Map<String, int> catalogOrder) {
    final readingKeys = <String, String>{};
    final randomKeys = <String, int>{};

    int catalogTieBreak(JapaneseWord left, JapaneseWord right) {
      final order = (catalogOrder[left.id] ?? 0).compareTo(
        catalogOrder[right.id] ?? 0,
      );
      return order != 0 ? order : left.id.compareTo(right.id);
    }

    return switch (_settings.order) {
      LockscreenWordOrder.basic => catalogTieBreak,
      LockscreenWordOrder.gojuon => (left, right) {
        final leftKey = readingKeys.putIfAbsent(
          left.id,
          () => gojuonSortKey(left.reading),
        );
        final rightKey = readingKeys.putIfAbsent(
          right.id,
          () => gojuonSortKey(right.reading),
        );
        final readingOrder = leftKey.compareTo(rightKey);
        if (readingOrder != 0) return readingOrder;
        final exactReadingOrder = left.reading.compareTo(right.reading);
        if (exactReadingOrder != 0) return exactReadingOrder;
        final lemmaOrder = left.lemma.compareTo(right.lemma);
        return lemmaOrder != 0 ? lemmaOrder : catalogTieBreak(left, right);
      },
      LockscreenWordOrder.random => (left, right) {
        final leftKey = randomKeys.putIfAbsent(
          left.id,
          () => stableWordOrderKey(left.id, _randomSeed),
        );
        final rightKey = randomKeys.putIfAbsent(
          right.id,
          () => stableWordOrderKey(right.id, _randomSeed),
        );
        final order = leftKey.compareTo(rightKey);
        return order != 0 ? order : left.id.compareTo(right.id);
      },
    };
  }

  int _newRandomSeed() {
    var next = DateTime.now().microsecondsSinceEpoch & 0x7fffffff;
    if (next == 0) next = 1;
    if (next == _randomSeed) {
      next = (next + 1) & 0x7fffffff;
      if (next == 0) next = 1;
    }
    return next;
  }

  String _configurationSignature(Map<String, Object?> configuration) {
    // The configuration contains only JSON-compatible ordered maps/lists.
    // Encoding the complete payload keeps preview-only meanings, forms and
    // examples in the deduplication signature as well as the compact fields.
    return jsonEncode(configuration);
  }

  @visibleForTesting
  String debugConfigurationSignature(Map<String, Object?> configuration) =>
      _configurationSignature(configuration);

  Future<void> flushPendingSync() async {
    if (_controllerSyncScheduled) _flushScheduledControllerSync();
    await _pendingSync;
  }

  void _recordPlatformError(String message) {
    _errorMessage = message;
  }

  void _notifySafely() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    disconnect();
    super.dispose();
  }
}

Set<JlptLevel> _parseStoredLevels(List<String>? names) {
  if (names == null) return const <JlptLevel>{};
  return <JlptLevel>{
    for (final level in JlptLevel.values)
      if (names.contains(level.name)) level,
  };
}

List<String> _orderedLevelNames(Set<JlptLevel> levels) => <String>[
  for (final level in JlptLevel.values)
    if (levels.contains(level)) level.name,
];

enum _WallpaperActionType { bookmark, known, openDetails }

@immutable
class _PendingWallpaperAction {
  const _PendingWallpaperAction({
    required this.id,
    required this.wordId,
    required this.action,
    required this.value,
    required this.createdAt,
    required this.sourceIndex,
  });

  final String id;
  final String wordId;
  final _WallpaperActionType action;
  final bool value;
  final int createdAt;
  final int sourceIndex;

  String get idKey => id;
  String get targetKey => '${action.name}:$wordId';
  DateTime? get occurredAt {
    if (createdAt <= 0 || createdAt > 8640000000000000) return null;
    return DateTime.fromMillisecondsSinceEpoch(createdAt);
  }

  int compareChronology(_PendingWallpaperAction other) {
    final byTime = createdAt.compareTo(other.createdAt);
    return byTime != 0 ? byTime : sourceIndex.compareTo(other.sourceIndex);
  }
}

List<_PendingWallpaperAction> _parsePendingActions(Object? source) {
  if (source is! List) return const <_PendingWallpaperAction>[];
  final actions = <_PendingWallpaperAction>[];
  for (var index = 0; index < source.length; index++) {
    final entry = source[index];
    if (entry is! Map) continue;
    final id = entry['id'];
    if (id is! String || id.trim().isEmpty) continue;
    final wordId = entry['wordId'];
    final actionName = entry['action'] ?? entry['type'];
    if (wordId is! String || wordId.isEmpty) continue;
    final action = switch (actionName) {
      'bookmark' => _WallpaperActionType.bookmark,
      'known' => _WallpaperActionType.known,
      'openDetails' => _WallpaperActionType.openDetails,
      _ => null,
    };
    if (action == null) continue;
    final requestedValue = entry['value'];
    if (action != _WallpaperActionType.openDetails && requestedValue is! bool) {
      continue;
    }
    final createdAtValue = entry['createdAt'];
    final createdAt = switch (createdAtValue) {
      final int value => value,
      final num value => value.toInt(),
      final String value =>
        int.tryParse(value) ?? DateTime.tryParse(value)?.millisecondsSinceEpoch,
      _ => null,
    };
    actions.add(
      _PendingWallpaperAction(
        id: id,
        wordId: wordId,
        action: action,
        value: requestedValue is bool ? requestedValue : false,
        createdAt: createdAt ?? index,
        sourceIndex: index,
      ),
    );
  }
  return actions;
}

int _comparePendingActions(
  _PendingWallpaperAction left,
  _PendingWallpaperAction right,
) => left.compareChronology(right);
