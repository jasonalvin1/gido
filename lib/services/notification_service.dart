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

  /// 앱 시작 시 한 번만 호출
  Future<void> initialize() async {
    if (_initialized) return;

    // 타임존 초기화 (한국 시간)
    tz.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Seoul'));

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);

    await _plugin.initialize(initSettings);

    // Android 알림 채널 생성
    const channel = AndroidNotificationChannel(
      'gido_alarm_channel',
      '기억 도우미 알림',
      description: '할일 마감일 알림을 표시합니다',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );

    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    _initialized = true;
  }

  /// Android 13+ 알림 권한 요청
  Future<bool> requestPermissions() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final granted = await android?.requestNotificationsPermission();
    return granted ?? false;
  }

  /// 특정 시각에 알림 예약 (v17 API)
  Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
  }) async {
    if (!_initialized) await initialize();

    // 이미 지난 시각이면 무시
    if (scheduledTime.isBefore(DateTime.now())) return;

    final tzScheduledTime = tz.TZDateTime.from(scheduledTime, tz.local);

    await _plugin.zonedSchedule(
      id,
      title,
      body,
      tzScheduledTime,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'gido_alarm_channel',
          '기억 도우미 알림',
          channelDescription: '할일 마감일 알림을 표시합니다',
          importance: Importance.max,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  /// 특정 메모의 알림 취소
  Future<void> cancelNotification(int id) async {
    await _plugin.cancel(id);
  }

  /// 모든 예약 알림 취소
  Future<void> cancelAllNotifications() async {
    await _plugin.cancelAll();
  }

  /// 메모 ID(String) → 알림 ID(int) 변환
  static int memoIdToNotificationId(String memoId) {
    return memoId.hashCode.abs() % 2147483647;
  }
}
