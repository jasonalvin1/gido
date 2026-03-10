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

  /// 메모의 '마감일' 필드를 파싱해 DateTime 반환 (실패 시 null)
  DateTime? _parseAlarmDateTime(Memo memo) {
    final value = memo.data['마감일'];
    if (value == null || value.isEmpty) return null;
    try {
      return DateFormat(_alarmDateTimeFormat).parse(value);
    } catch (_) {
      return null;
    }
  }

  /// 메모에 알람 예약 (완료되지 않은 할일만)
  Future<void> _scheduleAlarmIfNeeded(Memo memo) async {
    // '할일' 카테고리(id: 'todo')이거나 마감일 필드가 있는 카테고리
    final alarmTime = _parseAlarmDateTime(memo);
    if (alarmTime == null) return;
    if (memo.isDone) return; // 완료된 항목은 알람 없음

    final notifId = NotificationService.memoIdToNotificationId(memo.id);
    // 오전/오후 12시간 형식 (예: 오후 2:48)
    final timeStr = DateFormat('M월 d일 a h:mm', 'ko').format(alarmTime);
    await _notificationService.scheduleNotification(
      id: notifId,
      title: '할 일이 있어요!',
      body: '$timeStr 기억도우미에서 할 일을 확인해보세요',
      scheduledTime: alarmTime,
      payload: memo.id,  // 알림 탭 시 해당 메모로 이동하기 위한 ID
    );
  }

  /// 메모 알람 취소
  Future<void> _cancelAlarm(Memo memo) async {
    final notifId = NotificationService.memoIdToNotificationId(memo.id);
    await _notificationService.cancelNotification(notifId);
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
    await _db.insertMemo(memo);
    _memoCounts[memo.categoryId] = (_memoCounts[memo.categoryId] ?? 0) + 1;
    // 마감일 알람 예약
    await _scheduleAlarmIfNeeded(memo);
    notifyListeners();
  }

  Future<void> updateMemo(Memo memo) async {
    memo.updatedAt = DateTime.now();
    await _db.updateMemo(memo);
    // 기존 알람 취소 후 새 알람 예약
    await _cancelAlarm(memo);
    await _scheduleAlarmIfNeeded(memo);
    notifyListeners();
  }

  Future<void> toggleDone(Memo memo) async {
    memo.isDone = !memo.isDone;
    await _db.toggleMemoDone(memo.id, memo.isDone);
    // 완료 시 알람 취소, 미완료로 되돌리면 재예약
    if (memo.isDone) {
      await _cancelAlarm(memo);
    } else {
      await _scheduleAlarmIfNeeded(memo);
    }
    notifyListeners();
  }

  Future<void> deleteMemo(Memo memo) async {
    // 삭제 전 알람 취소
    await _cancelAlarm(memo);
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
    await _cancelAlarm(memo); // 기존 알람 취소
    await _db.moveMemo(memo.id, newCategoryId, newData);
    // 메모 카운트 업데이트
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