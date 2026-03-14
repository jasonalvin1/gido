import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  /// 알림 탭으로 진입 시 이동할 메모 ID (HomeScreen에서 읽고 null 처리)
  static String? pendingMemoId;

  /// 앱이 실행 중일 때 알림 탭 → 즉시 호출되는 콜백 (HomeScreen에서 등록)
  static void Function(String memoId)? onNotificationTap;

  /// 알림 방식: 0=무음, 1=진동, 2=소리(기본)
  static int notificationMode = 2;

  /// 앱 시작 시 한 번만 호출
  Future<void> initialize() async {
    if (_initialized) return;

    // 타임존 초기화 (한국 시간)
    tz.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Seoul'));

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);

    await _plugin.initialize(
      initSettings,
      // 앱 실행 중 알림 탭 (warm start / foreground)
      onDidReceiveNotificationResponse: (details) {
        final payload = details.payload;
        if (payload != null && payload.isNotEmpty) {
          // 콜백이 등록되어 있으면 즉시 이동, 없으면 pendingMemoId에 저장
          if (NotificationService.onNotificationTap != null) {
            NotificationService.onNotificationTap!(payload);
          } else {
            NotificationService.pendingMemoId = payload;
          }
        }
      },
    );

    // 알림으로 앱이 시작된 경우 (cold start)
    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp == true) {
      final payload = launchDetails?.notificationResponse?.payload;
      if (payload != null && payload.isNotEmpty) {
        NotificationService.pendingMemoId = payload;
      }
    }

    // Android 알림 채널 3종 생성 (무음 / 진동 / 소리)
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        'gido_silent',
        '기억 도우미 (무음)',
        description: '소리·진동 없이 알림만 표시합니다',
        importance: Importance.low,
        playSound: false,
        enableVibration: false,
      ),
    );
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        'gido_vibrate',
        '기억 도우미 (진동)',
        description: '진동으로 알림을 전달합니다',
        importance: Importance.defaultImportance,
        playSound: false,
        enableVibration: true,
      ),
    );
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        'gido_sound',
        '기억 도우미 (소리)',
        description: '소리와 진동으로 알림을 전달합니다',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      ),
    );

    _initialized = true;
  }

  /// Android 13+ 알림 권한 요청
  Future<bool> requestPermissions() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final granted = await android?.requestNotificationsPermission();
    return granted ?? false;
  }

  /// 정확한 알람 예약 권한 확인 (Samsung 등 배터리 최적화 기기 대응)
  Future<bool> _canUseExactAlarm() async {
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      return await android?.canScheduleExactNotifications() ?? true;
    } catch (_) {
      return true; // 확인 실패 시 일단 시도
    }
  }

  /// 현재 notificationMode에 맞는 NotificationDetails 반환
  NotificationDetails _getNotifDetails() {
    switch (notificationMode) {
      case 0: // 무음
        return const NotificationDetails(
          android: AndroidNotificationDetails(
            'gido_silent', '기억 도우미 (무음)',
            channelDescription: '소리·진동 없이 알림만 표시합니다',
            importance: Importance.low,
            priority: Priority.low,
            playSound: false,
            enableVibration: false,
            icon: '@mipmap/ic_launcher',
          ),
        );
      case 1: // 진동
        return const NotificationDetails(
          android: AndroidNotificationDetails(
            'gido_vibrate', '기억 도우미 (진동)',
            channelDescription: '진동으로 알림을 전달합니다',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
            playSound: false,
            enableVibration: true,
            icon: '@mipmap/ic_launcher',
          ),
        );
      default: // 2: 소리 (기본)
        return const NotificationDetails(
          android: AndroidNotificationDetails(
            'gido_sound', '기억 도우미 (소리)',
            channelDescription: '소리와 진동으로 알림을 전달합니다',
            importance: Importance.high,
            priority: Priority.high,
            playSound: true,
            enableVibration: true,
            icon: '@mipmap/ic_launcher',
          ),
        );
    }
  }

  /// 특정 시각에 알림 예약 (v17 API)
  /// Samsung One UI 배터리 최적화로 exactAllowWhileIdle이 거부될 경우 inexact로 폴백
  Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
    String? payload,  // 탭 시 이동할 메모 ID
  }) async {
    if (!_initialized) await initialize();

    // 이미 지난 시각이면 무시
    if (scheduledTime.isBefore(DateTime.now())) return;

    final tzScheduledTime = tz.TZDateTime.from(scheduledTime, tz.local);

    // 정확한 알람 권한 확인 → Samsung 배터리 최적화 대응
    final canExact = await _canUseExactAlarm();
    final scheduleMode = canExact
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexact;

    debugPrint('🔔 알람 예약: $scheduleMode / ${scheduledTime.toString()}');

    await _plugin.zonedSchedule(
      id,
      title,
      body,
      tzScheduledTime,
      _getNotifDetails(),
      androidScheduleMode: scheduleMode,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: payload,
    );
  }

  /// 날짜 기념일 알림 예약 (매년 자동 반복)
  /// scheduledTime: 알림을 보낼 시각 (하루 전 오전 9시)
  Future<void> scheduleBirthdayNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
    String? payload,
  }) async {
    if (!_initialized) await initialize();

    // 날짜가 과거면 미래가 될 때까지 매년 반복해서 올림 (예: 1964년생도 올해/내년으로 조정)
    DateTime target = scheduledTime;
    final now = DateTime.now();
    while (target.isBefore(now)) {
      target = DateTime(target.year + 1, target.month, target.day,
          target.hour, target.minute);
    }

    final tzScheduledTime = tz.TZDateTime.from(target, tz.local);
    final canExact = await _canUseExactAlarm();
    final scheduleMode = canExact
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexact;

    debugPrint('🎂 생일 알림 예약(매년): $scheduleMode / ${target.toString()}');

    await _plugin.zonedSchedule(
      id,
      title,
      body,
      tzScheduledTime,
      _getNotifDetails(),
      androidScheduleMode: scheduleMode,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: payload,
    );
  }

  /// 매일 정해진 시각에 반복 알림 예약 (약 복용, 생활 루틴 등)
  /// scheduledTime의 날짜는 무시되고 시(hour)·분(minute)만 사용됩니다.
  Future<void> scheduleRepeatingDailyNotification({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
    String? payload,
  }) async {
    if (!_initialized) await initialize();

    // 오늘 해당 시각으로 설정; 이미 지났으면 내일부터 시작
    final now = DateTime.now();
    var target = DateTime(now.year, now.month, now.day, hour, minute);
    if (target.isBefore(now)) {
      target = target.add(const Duration(days: 1));
    }

    final tzTarget = tz.TZDateTime.from(target, tz.local);
    final canExact = await _canUseExactAlarm();
    final scheduleMode = canExact
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexact;

    debugPrint('🔁 반복 알림 예약: $scheduleMode / 매일 $hour:$minute');

    await _plugin.zonedSchedule(
      id,
      title,
      body,
      tzTarget,
      _getNotifDetails(),
      androidScheduleMode: scheduleMode,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time, // ← 매일 같은 시각 반복
      payload: payload,
    );
  }

  /// 특정 메모의 알림 취소
  /// 기기 호환성 문제로 PlatformException이 발생해도 무시 (삭제 흐름 차단 방지)
  Future<void> cancelNotification(int id) async {
    try {
      await _plugin.cancel(id);
    } catch (e) {
      debugPrint('⚠️ cancelNotification 실패 (id=$id): $e');
    }
  }

  /// 모든 예약 알림 취소
  Future<void> cancelAllNotifications() async {
    try {
      await _plugin.cancelAll();
    } catch (e) {
      debugPrint('⚠️ cancelAllNotifications 실패: $e');
    }
  }

  /// 메모 ID(String) → 할일 알림 ID(int) 변환
  static int memoIdToNotificationId(String memoId) {
    return memoId.hashCode.abs() % 2147483647;
  }

  /// 메모 ID(String) → 생일/기념일 알림 ID(int) 변환 (할일 알림과 충돌 방지)
  static int birthdayNotificationId(String memoId) {
    return (memoId.hashCode.abs() + 999983) % 2147483647;
  }
}
