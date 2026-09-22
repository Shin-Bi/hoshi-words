import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Native contract for adding and inspecting the interactive word widget.
abstract interface class WordWidgetPlatformGateway {
  Future<Object?> getWidgetStatus();

  Future<Object?> openWidgetPicker();

  Future<Object?> openExactAlarmSettings();
}

class MethodChannelWordWidgetGateway implements WordWidgetPlatformGateway {
  const MethodChannelWordWidgetGateway();

  static const channel = MethodChannel('app.shinbi.tsuki_words/live_wallpaper');

  @override
  Future<Object?> getWidgetStatus() {
    return channel.invokeMethod<Object?>('getWidgetStatus');
  }

  @override
  Future<Object?> openWidgetPicker() {
    return channel.invokeMethod<Object?>('openWidgetPicker');
  }

  @override
  Future<Object?> openExactAlarmSettings() {
    return channel.invokeMethod<Object?>('openExactAlarmSettings');
  }
}

@immutable
class WordWidgetStatus {
  const WordWidgetStatus({
    required this.supported,
    required this.canOpenPicker,
    required this.added,
    this.widgetCount = 0,
    this.homeWidgetCount = 0,
    this.lockscreenWidgetCount = 0,
    this.exactTimerSupported = false,
    this.exactTimerGranted = true,
    this.message,
  });

  const WordWidgetStatus.loading()
    : supported = false,
      canOpenPicker = false,
      added = false,
      widgetCount = 0,
      homeWidgetCount = 0,
      lockscreenWidgetCount = 0,
      exactTimerSupported = false,
      exactTimerGranted = true,
      message = null;

  final bool supported;
  final bool canOpenPicker;
  final bool added;
  final int widgetCount;
  final int homeWidgetCount;
  final int lockscreenWidgetCount;
  final bool exactTimerSupported;
  final bool exactTimerGranted;
  final String? message;

  bool get homeWidgetAdded => homeWidgetCount > 0;
  bool get lockscreenWidgetAdded => lockscreenWidgetCount > 0;
  bool get needsExactTimerPermission =>
      exactTimerSupported && !exactTimerGranted;

  factory WordWidgetStatus.fromPlatform(Object? source) {
    if (source is bool) {
      return WordWidgetStatus(
        supported: source,
        canOpenPicker: source,
        added: false,
      );
    }
    if (source is! Map) {
      return const WordWidgetStatus(
        supported: true,
        canOpenPicker: true,
        added: false,
      );
    }
    final supported = _firstBool(source, const [
      'supported',
      'isSupported',
      'widgetSupported',
    ]);
    final canOpenPicker = _firstBool(source, const [
      'canOpenPicker',
      'pickerSupported',
      'pinRequestSupported',
      'isPinSupported',
      'canPin',
    ]);
    final reportedExactTimerSupported = _firstBool(source, const [
      'exactTimerSupported',
      'exactAlarmSupported',
      'exactAlarmSettingsSupported',
      'requiresExactAlarmPermission',
    ]);
    final reportedExactTimerGranted = _firstBool(source, const [
      'exactTimerGranted',
      'canScheduleExactAlarms',
      'canScheduleExactAlarm',
      'exactAlarmGranted',
    ]);
    final exactTimerSupported =
        reportedExactTimerSupported ?? reportedExactTimerGranted != null;
    // Older native builds and Android versions below 12 do not report this
    // special access. Treat absence as "not required" instead of alarming the
    // user with a settings action the platform cannot handle.
    final exactTimerGranted = reportedExactTimerGranted ?? !exactTimerSupported;
    final reportedCount = _firstInt(source, const [
      'widgetCount',
      'count',
      'activeWidgetCount',
    ]);
    final reportedHomeCount = _firstInt(source, const [
      'homeWidgetCount',
      'homeCount',
    ]);
    final reportedLockscreenCount = _firstInt(source, const [
      'lockscreenWidgetCount',
      'keyguardWidgetCount',
      'lockWidgetCount',
    ]);
    final homePinned =
        _firstBool(source, const ['homeWidgetPinned', 'homeWidgetAdded']) ??
        false;
    final lockscreenPinned =
        _firstBool(source, const [
          'lockscreenWidgetPinned',
          'keyguardWidgetPinned',
          'lockscreenWidgetAdded',
        ]) ??
        false;
    final separatedCountsReported =
        reportedHomeCount != null ||
        reportedLockscreenCount != null ||
        source.containsKey('homeWidgetPinned') ||
        source.containsKey('lockscreenWidgetPinned');
    final homeCount = (reportedHomeCount ?? (homePinned ? 1 : 0)).clamp(
      0,
      1 << 30,
    );
    // Older native builds exposed only one aggregate component. Preserve its
    // count compatibility, but prefer explicit dual-provider counts whenever
    // available.
    final lockscreenCount =
        (reportedLockscreenCount ??
                (lockscreenPinned
                    ? 1
                    : separatedCountsReported
                    ? 0
                    : reportedCount ?? 0))
            .clamp(0, 1 << 30);
    final count = (reportedCount ?? (homeCount + lockscreenCount)).clamp(
      0,
      1 << 30,
    );
    final added =
        _firstBool(source, const [
          'added',
          'isAdded',
          'widgetPinned',
          'active',
          'isActive',
          'configured',
          'isConfigured',
        ]) ??
        count > 0;
    final messageValue =
        source['message'] ?? source['widgetMessage'] ?? source['description'];
    final message = messageValue is String && messageValue.trim().isNotEmpty
        ? messageValue.trim()
        : null;
    final resolvedSupport = supported ?? true;
    return WordWidgetStatus(
      supported: resolvedSupport,
      canOpenPicker: resolvedSupport && (canOpenPicker ?? true),
      added: added,
      widgetCount: count > 0 ? count : (added ? 1 : 0),
      homeWidgetCount: homeCount,
      lockscreenWidgetCount: lockscreenCount,
      exactTimerSupported: exactTimerSupported,
      exactTimerGranted: exactTimerGranted,
      message: message,
    );
  }
}

class WordWidgetService extends ChangeNotifier {
  WordWidgetService({
    WordWidgetPlatformGateway? gateway,
    bool? platformAvailable,
  }) : _gateway = gateway ?? const MethodChannelWordWidgetGateway(),
       _platformAvailable =
           platformAvailable ??
           (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

  final WordWidgetPlatformGateway _gateway;
  final bool _platformAvailable;

  WordWidgetStatus _status = const WordWidgetStatus.loading();
  String? _errorMessage;
  bool _checking = false;
  bool _opening = false;
  bool _openingExactTimerSettings = false;
  bool _disposed = false;

  WordWidgetStatus get status => _status;
  String? get errorMessage => _errorMessage;
  bool get isPlatformAvailable => _platformAvailable;
  bool get isBusy => _checking || _opening || _openingExactTimerSettings;
  bool get isOpeningExactTimerSettings => _openingExactTimerSettings;

  Future<void> refreshStatus() async {
    if (!_platformAvailable) {
      _status = const WordWidgetStatus(
        supported: false,
        canOpenPicker: false,
        added: false,
        message: '단어 위젯은 Android 기기에서 사용할 수 있어요.',
      );
      _notifySafely();
      return;
    }
    _checking = true;
    _notifySafely();
    try {
      _status = WordWidgetStatus.fromPlatform(await _gateway.getWidgetStatus());
      _errorMessage = null;
    } on MissingPluginException {
      _status = const WordWidgetStatus(
        supported: false,
        canOpenPicker: false,
        added: false,
        message: '이 빌드에서는 단어 위젯을 사용할 수 없어요.',
      );
    } on PlatformException catch (error) {
      _errorMessage = error.message ?? '위젯 상태를 확인하지 못했어요.';
    } catch (_) {
      _errorMessage = '위젯 상태를 확인하지 못했어요.';
    } finally {
      _checking = false;
      _notifySafely();
    }
  }

  Future<bool> openPicker() async {
    if (!_platformAvailable || !_status.supported) {
      _errorMessage = _status.message ?? '이 기기에서는 위젯을 추가할 수 없어요.';
      _notifySafely();
      return false;
    }
    _opening = true;
    _errorMessage = null;
    _notifySafely();
    try {
      final result = await _gateway.openWidgetPicker();
      final opened = _pickerResultSucceeded(result);
      await refreshStatus();
      if (!opened) {
        _errorMessage = _pickerResultMessage(result) ?? '위젯 선택기를 열지 못했어요.';
        _notifySafely();
      }
      return opened;
    } on MissingPluginException {
      _errorMessage = '이 빌드에서는 위젯 선택기를 열 수 없어요.';
    } on PlatformException catch (error) {
      _errorMessage = error.message ?? '위젯 선택기를 열지 못했어요.';
    } catch (_) {
      _errorMessage = '위젯 선택기를 열지 못했어요.';
    } finally {
      _opening = false;
      _notifySafely();
    }
    return false;
  }

  Future<bool> openExactAlarmSettings() async {
    if (!_platformAvailable || !_status.exactTimerSupported) {
      _errorMessage = '이 기기에서는 알람 및 리마인더 설정이 필요하지 않아요.';
      _notifySafely();
      return false;
    }
    _openingExactTimerSettings = true;
    _errorMessage = null;
    _notifySafely();
    try {
      final result = await _gateway.openExactAlarmSettings();
      final opened = _settingsResultSucceeded(result);
      if (!opened) {
        _errorMessage =
            _settingsResultMessage(result) ?? '알람 및 리마인더 설정을 열지 못했어요.';
        _notifySafely();
      }
      return opened;
    } on MissingPluginException {
      _errorMessage = '이 빌드에서는 알람 및 리마인더 설정을 열 수 없어요.';
    } on PlatformException catch (error) {
      _errorMessage = error.message ?? '알람 및 리마인더 설정을 열지 못했어요.';
    } catch (_) {
      _errorMessage = '알람 및 리마인더 설정을 열지 못했어요.';
    } finally {
      _openingExactTimerSettings = false;
      _notifySafely();
    }
    return false;
  }

  void clearError() {
    if (_errorMessage == null) return;
    _errorMessage = null;
    _notifySafely();
  }

  void _notifySafely() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

bool? _firstBool(Map<dynamic, dynamic> source, List<String> keys) {
  for (final key in keys) {
    final value = source[key];
    if (value is bool) return value;
    if (value is num && (value == 0 || value == 1)) return value == 1;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == 'true' || normalized == '1') return true;
      if (normalized == 'false' || normalized == '0') return false;
    }
  }
  return null;
}

int? _firstInt(Map<dynamic, dynamic> source, List<String> keys) {
  for (final key in keys) {
    final value = source[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) {
      final parsed = int.tryParse(value);
      if (parsed != null) return parsed;
    }
  }
  return null;
}

bool _pickerResultSucceeded(Object? result) {
  if (result == null) return true;
  if (result is bool) return result;
  if (result is! Map) return true;
  return _firstBool(result, const [
        'opened',
        'success',
        'requested',
        'pinRequestLaunched',
        'pickerOpened',
      ]) ??
      true;
}

String? _pickerResultMessage(Object? result) {
  if (result is! Map) return null;
  final message = result['message'] ?? result['widgetMessage'];
  return message is String && message.trim().isNotEmpty ? message.trim() : null;
}

bool _settingsResultSucceeded(Object? result) {
  if (result == null) return true;
  if (result is bool) return result;
  if (result is! Map) return true;
  return _firstBool(result, const ['opened', 'success', 'settingsOpened']) ??
      true;
}

String? _settingsResultMessage(Object? result) {
  if (result is! Map) return null;
  final message = result['message'] ?? result['description'];
  return message is String && message.trim().isNotEmpty ? message.trim() : null;
}
