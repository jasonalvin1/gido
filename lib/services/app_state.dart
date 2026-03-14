import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/memo_model.dart';
import '../services/database_service.dart';
import '../services/notification_service.dart';

class AppState extends ChangeNotifier {
  final DatabaseService _db = DatabaseService();
  final NotificationService _notificationService = NotificationService();

  // 알람 datetime 파싱 형식 (memo_edit_screen과 동일)
  static const String _alarmDateTimeFormat = 'yyyy년 M월 d일 HH:mm';

  /// 메모의 알람 필드('마감일' 또는 '날짜/시간')를 파싱해 DateTime 반환 (실패 시 null)
  DateTime? _parseAlarmDateTime(Memo memo) {
    // alarmDateTimeFields 순서대로 확인 (마감일, 날짜/시간)
    for (final field in ['마감일', '날짜/시간']) {
      final value = memo.data[field];
      if (value != null && value.isNotEmpty) {
        try {
          return DateFormat(_alarmDateTimeFormat).parse(value);
        } catch (_) {}
      }
    }
    return null;
  }

  /// 메모에 알람 예약 (일회성 또는 매일 반복)
  Future<void> _scheduleAlarmIfNeeded(Memo memo) async {
    final alarmTime = _parseAlarmDateTime(memo);
    if (alarmTime == null) return;
    if (memo.isDone) return; // 완료된 항목은 알람 없음

    final notifId = NotificationService.memoIdToNotificationId(memo.id);

    // 매일 반복 알림 (약 복용, 생활 루틴 등)
    if (memo.isRepeatingAlarm) {
      await _notificationService.scheduleRepeatingDailyNotification(
        id: notifId,
        title: '💊 기억도우미',
        body: '${memo.title} 시간이에요! 😊',
        hour: alarmTime.hour,
        minute: alarmTime.minute,
        payload: memo.id,
      );
      return;
    }

    // 일회성 알림 (기존 로직)
    final timeStr = DateFormat('M월 d일 a h:mm', 'ko').format(alarmTime);
    final isAppointment = memo.data.containsKey('날짜/시간') &&
        (memo.data['날짜/시간'] ?? '').isNotEmpty;
    final title = isAppointment ? '📅 약속/모임이 있어요!' : '할 일이 있어요!';
    final body = isAppointment
        ? '$timeStr 일정을 확인해보세요'
        : '$timeStr 기억도우미에서 할 일을 확인해보세요';

    await _notificationService.scheduleNotification(
      id: notifId,
      title: title,
      body: body,
      scheduledTime: alarmTime,
      payload: memo.id,
    );
  }

  /// 메모 알람 취소 (실패해도 흐름 중단 없음)
  Future<void> _cancelAlarm(Memo memo) async {
    try {
      final notifId = NotificationService.memoIdToNotificationId(memo.id);
      await _notificationService.cancelNotification(notifId);
    } catch (e) {
      debugPrint('⚠️ _cancelAlarm 실패 (memoId=${memo.id}): $e');
    }
  }

  // 날짜 필드 파싱 형식 (memo_edit_screen과 동일)
  static const String _dateFormat = 'yyyy년 M월 d일';

  /// 메모의 '날짜' 필드를 파싱해 DateTime 반환 (실패 시 null)
  DateTime? _parseDateField(Memo memo) {
    final value = memo.data['날짜'];
    if (value == null || value.isEmpty) return null;
    try {
      return DateFormat(_dateFormat).parse(value);
    } catch (_) {
      return null;
    }
  }

  /// 날짜 필드가 있는 메모에 생일/기념일 알림 예약 (하루 전 오전 9시, 매년 반복)
  Future<void> _scheduleBirthdayAlarmIfNeeded(Memo memo) async {
    final date = _parseDateField(memo);
    if (date == null) return;

    // 하루 전 오전 9시
    final notifyAt = DateTime(date.year, date.month, date.day - 1, 9, 0);
    final notifId = NotificationService.birthdayNotificationId(memo.id);
    final name = memo.title.isNotEmpty ? memo.title : '소중한 날';

    await _notificationService.scheduleBirthdayNotification(
      id: notifId,
      title: '🎂 기억도우미',
      body: '내일은 $name 날이에요! 😊',
      scheduledTime: notifyAt,
      payload: memo.id,
    );
  }

  /// 생일/기념일 알림 취소 (실패해도 흐름 중단 없음)
  Future<void> _cancelBirthdayAlarm(Memo memo) async {
    try {
      final notifId = NotificationService.birthdayNotificationId(memo.id);
      await _notificationService.cancelNotification(notifId);
    } catch (e) {
      debugPrint('⚠️ _cancelBirthdayAlarm 실패 (memoId=${memo.id}): $e');
    }
  }

  List<Category> _categories = [];
  List<Memo> _memos = [];
  Map<String, int> _memoCounts = {};
  bool _isLoading = true;

  List<Category> get categories => _categories;
  List<Memo> get memos => _memos;
  Map<String, int> get memoCounts => _memoCounts;
  bool get isLoading => _isLoading;

  Future<void> loadData() async {
    _isLoading = true;
    notifyListeners();

    try {
      // 8초 안에 완료되지 않으면 타임아웃 → 빈 상태로 진행 (무한 로딩 차단)
      await _loadDataInternal().timeout(
        const Duration(seconds: 8),
        onTimeout: () => debugPrint('⚠️ loadData 타임아웃: DB 초기화 지연'),
      );
    } catch (e) {
      debugPrint('⚠️ loadData 오류: $e');
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> _loadDataInternal() async {
    _categories = await _db.getCategories();
    _memoCounts = {};
    for (final cat in _categories) {
      _memoCounts[cat.id] = await _db.getMemoCount(cat.id);
    }
    // 앱 실행 시 생일/기념일 알림 자동 갱신 (일회성 알림이므로 매년 재예약 필요)
    await _rescheduleBirthdayAlarms();
  }

  /// 모든 메모의 날짜 필드를 확인하여 지난 알림을 다음 해로 재예약
  Future<void> _rescheduleBirthdayAlarms() async {
    try {
      final allMemos = await _db.getAllMemos();
      for (final memo in allMemos) {
        if (_parseDateField(memo) != null) {
          await _scheduleBirthdayAlarmIfNeeded(memo);
        }
      }
    } catch (e) {
      debugPrint('⚠️ 생일 알림 재예약 오류: $e');
    }
  }

  Future<List<Memo>> loadMemosByCategory(String categoryId) async {
    return await _db.getMemosByCategory(categoryId);
  }

  /// 알림 탭 딥링크용: 메모 ID로 메모와 카테고리 동시 조회
  Future<({Memo memo, Category category})?> getMemoAndCategoryById(String memoId) async {
    final memo = await _db.getMemoById(memoId);
    if (memo == null) return null;
    try {
      final category = _categories.firstWhere((c) => c.id == memo.categoryId);
      return (memo: memo, category: category);
    } catch (_) {
      return null;
    }
  }

  Future<List<Memo>> searchMemos(String query) async {
    if (query.trim().isEmpty) return [];
    return await _db.searchMemos(query);
  }

  Future<void> addCategory(Category category) async {
    await _db.insertCategory(category);
    await loadData();
  }

  Future<void> deleteCategory(String id) async {
    await _db.deleteCategory(id);
    await loadData();
  }

  Future<void> updateCategory(Category category) async {
    await _db.updateCategory(category);
    await loadData();
  }

  // 카테고리 순서 변경 - sortOrder를 인덱스 기반으로 재정렬
  Future<void> reorderCategory(String id, bool moveUp) async {
    final index = _categories.indexWhere((c) => c.id == id);
    if (index == -1) return;
    if (moveUp && index == 0) return;
    if (!moveUp && index == _categories.length - 1) return;

    final swapIndex = moveUp ? index - 1 : index + 1;

    // 리스트에서 직접 순서 교환
    final list = List<Category>.from(_categories);
    final temp = list[index];
    list[index] = list[swapIndex];
    list[swapIndex] = temp;

    // 전체 순서를 인덱스 기반으로 다시 저장 (중복 방지)
    for (int i = 0; i < list.length; i++) {
      final updated = Category(
        id: list[i].id,
        name: list[i].name,
        icon: list[i].icon,
        color: list[i].color,
        fields: list[i].fields,
        isDefault: list[i].isDefault,
        sortOrder: i,
      );
      await _db.updateCategory(updated);
    }

    await loadData();
  }

  Future<void> addMemo(Memo memo) async {
    // 1단계: DB 저장 (반드시 완료 후 진행)
    await _db.insertMemo(memo);
    _memoCounts[memo.categoryId] = (_memoCounts[memo.categoryId] ?? 0) + 1;

    // 2단계: 알림 예약 (실패해도 저장 결과에 영향 없음)
    try {
      await _scheduleAlarmIfNeeded(memo);
    } catch (e) {
      debugPrint('⚠️ addMemo - 알림 예약 실패 (memoId=${memo.id}): $e');
    }
    try {
      await _scheduleBirthdayAlarmIfNeeded(memo);
    } catch (e) {
      debugPrint('⚠️ addMemo - 생일 알림 예약 실패 (memoId=${memo.id}): $e');
    }

    notifyListeners();
  }

  /// 여러 메모를 한 번에 추가 (약 복용 추천 세트 등)
  Future<void> addMemos(List<Memo> memos) async {
    for (final memo in memos) {
      // 1단계: DB 저장 (반드시 완료)
      await _db.insertMemo(memo);
      _memoCounts[memo.categoryId] = (_memoCounts[memo.categoryId] ?? 0) + 1;

      // 2단계: 알림 예약 (한 항목 실패해도 다음 항목 계속 진행)
      try {
        await _scheduleAlarmIfNeeded(memo);
      } catch (e) {
        debugPrint('⚠️ addMemos - 알림 예약 실패 (memoId=${memo.id}): $e');
      }
    }
    notifyListeners();
  }

  Future<void> updateMemo(Memo memo) async {
    // 1단계: DB 저장 (반드시 완료 후 진행)
    memo.updatedAt = DateTime.now();
    await _db.updateMemo(memo);

    // 2단계: 알림 갱신 (실패해도 저장 성공 결과에 영향 없음)
    try {
      await _cancelAlarm(memo);
      await _scheduleAlarmIfNeeded(memo);
    } catch (e) {
      debugPrint('⚠️ updateMemo - 알림 갱신 실패 (memoId=${memo.id}): $e');
    }
    try {
      await _cancelBirthdayAlarm(memo);
      await _scheduleBirthdayAlarmIfNeeded(memo);
    } catch (e) {
      debugPrint('⚠️ updateMemo - 생일 알림 갱신 실패 (memoId=${memo.id}): $e');
    }

    notifyListeners();
  }

  Future<void> toggleDone(Memo memo) async {
    // 1단계: DB 상태 변경 (반드시 완료)
    memo.isDone = !memo.isDone;
    await _db.toggleMemoDone(memo.id, memo.isDone);

    // 2단계: 알림 처리 (실패해도 완료 상태 변경에 영향 없음)
    try {
      if (memo.isDone) {
        await _cancelAlarm(memo);
      } else {
        await _scheduleAlarmIfNeeded(memo);
      }
    } catch (e) {
      debugPrint('⚠️ toggleDone - 알림 처리 실패 (memoId=${memo.id}): $e');
    }

    notifyListeners();
  }

  Future<void> deleteMemo(Memo memo) async {
    // 1단계: 알림 취소 시도 (실패해도 DB 삭제는 반드시 진행)
    await _cancelAlarm(memo);
    await _cancelBirthdayAlarm(memo);

    // 2단계: DB 삭제 (알림 취소 성공 여부와 무관하게 무조건 실행)
    await _db.deleteMemo(memo.id);
    _memoCounts[memo.categoryId] = (_memoCounts[memo.categoryId] ?? 1) - 1;
    notifyListeners();
  }

  Category? getCategoryById(String id) {
    try {
      return _categories.firstWhere((c) => c.id == id);
    } catch (e) {
      return null;
    }
  }

  /// 카테고리 간 메모 이동 (ID 기반, 필드 매핑 적용)
  Future<void> moveMemo(Memo memo, String newCategoryId, Map<String, String> newData) async {
    // 1단계: 기존 알림 취소 시도 (실패해도 이동은 진행)
    await _cancelAlarm(memo);

    // 2단계: DB 이동 (반드시 완료)
    await _db.moveMemo(memo.id, newCategoryId, newData);
    _memoCounts[memo.categoryId] = (_memoCounts[memo.categoryId] ?? 1) - 1;
    _memoCounts[newCategoryId] = (_memoCounts[newCategoryId] ?? 0) + 1;
    notifyListeners();
  }

  /// 유사 메모 검색 (중복 입력 방지용)
  Future<List<Memo>> getSimilarMemos(String categoryId, String query, {String? excludeId}) async {
    if (query.trim().length < 2) return [];
    return await _db.getSimilarMemos(categoryId, query, excludeId: excludeId);
  }
}