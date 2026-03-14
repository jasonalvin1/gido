import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:lunar/lunar.dart';
import 'package:speech_to_text/speech_to_text.dart';
import '../models/memo_model.dart';
import '../services/app_state.dart';
import '../utils/app_theme.dart';
import '../widgets/lunar_calendar_picker.dart';

// 알람 datetime 저장 형식
const String _alarmDateTimeFormat = 'yyyy년 M월 d일 HH:mm';


class MemoEditScreen extends StatefulWidget {
  final Category category;
  final Memo? memo;

  const MemoEditScreen({super.key, required this.category, this.memo});

  @override
  State<MemoEditScreen> createState() => _MemoEditScreenState();
}

class _MemoEditScreenState extends State<MemoEditScreen> {
  late Map<String, TextEditingController> _fieldControllers;
  // 비밀번호 필드별 가림 여부 관리
  late Map<String, bool> _obscureFields;
  bool _isSaving = false;
  // 중복 감지
  List<Memo> _similarMemos = [];
  Timer? _debounceTimer;
  // 음력 날짜 (필드명 → 음력 문자열)
  final Map<String, String> _lunarDates = {};
  // 음성 입력
  final SpeechToText _speech = SpeechToText();
  bool _speechAvailable = false;
  String? _activeListeningField; // 현재 듣고 있는 필드명
  Timer? _speechTimer;

  bool get _isEditing => widget.memo != null;
  Color get _catColor => AppTheme.hexToColor(widget.category.color);

  // 추가 정보 섹션 펼침 여부
  bool _showExtra = false;

  // 애니메이션 트리거
  int _bellTrigger = 0;      // 알림 벨 흔들림 (증가할 때마다 재실행)
  bool _showSaveCheck = false; // 저장 완료 체크 오버레이
  bool _isPresetAlarm = false; // 추천 세트 선택 시 반복 알림 플래그

  // 카테고리별 우선 표시 필드 (최대 2~3개)
  static const _primaryFieldMap = {
    'bank':     ['은행명', '비밀번호'],
    'site':     ['사이트명', '비밀번호'],
    'birthday': ['이름', '날짜'],
    'church':   ['모임명', '날짜/시간'],
    'todo':     ['할일', '마감일'],
  };

  List<String> _primaryFields() {
    final primary = _primaryFieldMap[widget.category.id];
    if (primary == null) return widget.category.fields; // 커스텀 카테고리: 전체 표시
    return widget.category.fields.where((f) => primary.contains(f)).toList();
  }

  List<String> _secondaryFields() {
    final primary = _primaryFields();
    return widget.category.fields.where((f) => !primary.contains(f)).toList();
  }

  String _eul(String word) {
    if (word.isEmpty) return '$word을(를)';
    final last = word.runes.last;
    if (last >= 44032 && last <= 55203) {
      final offset = (last - 44032) % 28;
      return offset == 0 ? '${word}를' : '${word}을';
    }
    return '$word를';
  }

  // ── 음력 변환 ─────────────────────────────────────────────────────────────

  /// 양력 날짜 문자열(yyyy년 M월 d일) → 음력 표시 문자열
  String _toLunarFromDate(String gregorian) {
    try {
      final date = DateFormat('yyyy년 M월 d일').parse(gregorian);
      final solar = Solar.fromYmd(date.year, date.month, date.day);
      final lunar = solar.getLunar();
      // lunar 1.7.x: getMonth()가 음수이면 윤달
      final m = lunar.getMonth();
      final leap = m < 0 ? '윤' : '';
      return '음력 $leap${m.abs()}월 ${lunar.getDay()}일';
    } catch (_) {
      return '';
    }
  }

  /// 알람 날짜 문자열(yyyy년 M월 d일 HH:mm) → 음력 표시 문자열
  String _toLunarFromAlarm(String alarmDate) {
    try {
      final date = DateFormat(_alarmDateTimeFormat).parse(alarmDate);
      final solar = Solar.fromYmd(date.year, date.month, date.day);
      final lunar = solar.getLunar();
      final m = lunar.getMonth();
      final leap = m < 0 ? '윤' : '';
      return '음력 $leap${m.abs()}월 ${lunar.getDay()}일';
    } catch (_) {
      return '';
    }
  }

  /// 음력 생일의 올해(또는 내년) 양력 날짜 계산 → "🎂 N일 후" 문자열
  String _getLunarBirthdayThisYear(String gregorian) {
    try {
      final date = DateFormat('yyyy년 M월 d일').parse(gregorian);
      final solar = Solar.fromYmd(date.year, date.month, date.day);
      final lunar = solar.getLunar();
      final lunarMonth = lunar.getMonth().abs();
      final lunarDay = lunar.getDay();
      final today = DateTime.now();

      // 올해 음력 생일 → 양력 변환
      DateTime _toSolarDate(int year) {
        final l = Lunar.fromYmd(year, lunarMonth, lunarDay);
        final s = l.getSolar();
        return DateTime(s.getYear(), s.getMonth(), s.getDay());
      }

      DateTime nextBirthday = _toSolarDate(today.year);
      // 이미 지났으면 내년으로
      if (nextBirthday.isBefore(DateTime(today.year, today.month, today.day))) {
        nextBirthday = _toSolarDate(today.year + 1);
      }
      final days = nextBirthday.difference(DateTime(today.year, today.month, today.day)).inDays;
      if (days == 0) return '🎂 오늘이 음력 생일이에요!';
      final formatted = DateFormat('yyyy년 M월 d일').format(nextBirthday);
      return '🎂 올해 음력 생일 양력: $formatted ($days일 후)';
    } catch (_) {
      return '';
    }
  }

  // ── 음성 입력 ─────────────────────────────────────────────────────────────

  Future<void> _toggleListening(String field) async {
    if (!_speechAvailable) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('이 기기에서 음성 인식을 사용할 수 없어요', style: TextStyle(fontSize: 16)),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    // 같은 필드 다시 누르면 정지
    if (_activeListeningField == field && _speech.isListening) {
      await _speech.stop();
      _speechTimer?.cancel();
      if (mounted) setState(() => _activeListeningField = null);
      return;
    }
    // 다른 필드가 듣고 있으면 먼저 정지
    if (_speech.isListening) {
      await _speech.stop();
      _speechTimer?.cancel();
    }
    if (mounted) setState(() => _activeListeningField = field);

    // 최대 1분 타이머
    _speechTimer?.cancel();
    _speechTimer = Timer(const Duration(minutes: 1), () async {
      await _speech.stop();
      if (mounted) setState(() => _activeListeningField = null);
    });

    await _speech.listen(
      onResult: (result) {
        if (result.finalResult) {
          final text = result.recognizedWords;
          if (text.isNotEmpty) {
            final current = _fieldControllers[field]?.text ?? '';
            _fieldControllers[field]?.text =
                current.isEmpty ? text : '$current $text';
          }
          _speechTimer?.cancel();
          if (mounted) setState(() => _activeListeningField = null);
        }
      },
      listenFor: const Duration(minutes: 1),
      pauseFor: const Duration(seconds: 5),
      localeId: 'ko-KR',
    );
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _fieldControllers = {};
    _obscureFields = {};
    for (final field in widget.category.fields) {
      final initialText = widget.memo?.data[field] ?? '';
      _fieldControllers[field] = TextEditingController(text: initialText);
      // 민감 필드는 초기에 가림 처리
      if (widget.category.isSensitiveField(field)) {
        _obscureFields[field] = true;
      }
      // 중복 감지를 위한 리스너 등록 (민감 필드 제외)
      if (!widget.category.isSensitiveField(field)) {
        _fieldControllers[field]!.addListener(_onFieldChanged);
      }
      // 기존 메모 수정 시: 저장된 날짜의 음력 미리 계산
      if (initialText.isNotEmpty) {
        if (widget.category.isDateField(field)) {
          _lunarDates[field] = _toLunarFromDate(initialText);
        } else if (widget.category.isAlarmDateTimeField(field)) {
          _lunarDates[field] = _toLunarFromAlarm(initialText);
        }
      }
    }
    // 수정 모드: secondary 필드에 값이 있으면 자동 펼침
    if (_isEditing) {
      _showExtra = _secondaryFields().any(
        (f) => (widget.memo?.data[f] ?? '').isNotEmpty,
      );
    }

    // 음성 인식 초기화 (비동기, 실패해도 앱 동작 영향 없음)
    _initSpeech();
  }

  Future<void> _initSpeech() async {
    try {
      _speechAvailable = await _speech.initialize(
        onError: (e) => debugPrint('🎙 Speech error: $e'),
      );
    } catch (_) {
      _speechAvailable = false;
    }
    if (mounted) setState(() {});
  }

  void _onFieldChanged() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 600), _checkDuplicates);
  }

  Future<void> _checkDuplicates() async {
    String query = '';
    for (final field in widget.category.fields) {
      if (widget.category.isSensitiveField(field)) continue;
      final text = _fieldControllers[field]?.text.trim() ?? '';
      if (text.length >= 2) {
        query = text;
        break;
      }
    }
    if (query.isEmpty) {
      if (mounted) setState(() => _similarMemos = []);
      return;
    }
    final similar = await context.read<AppState>().getSimilarMemos(
      widget.category.id,
      query,
      excludeId: widget.memo?.id,
    );
    if (mounted) setState(() => _similarMemos = similar);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _speechTimer?.cancel();
    if (_speech.isListening) _speech.stop();
    for (final c in _fieldControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  // ── 날짜 선택: 네이버 스타일 양(음)력 달력 ──────────────────────────────
  Future<void> _pickDate(String field) async {
    DateTime initialDate = DateTime.now();
    final currentText = _fieldControllers[field]?.text ?? '';
    if (currentText.isNotEmpty) {
      try {
        initialDate = DateFormat('yyyy년 M월 d일').parse(currentText);
      } catch (_) {}
    }
    if (!mounted) return;

    final picked = await showLunarCalendarPicker(
      context: context,
      themeColor: _catColor,
      initialDate: initialDate,
    );

    if (picked != null && mounted) {
      final formatted = DateFormat('yyyy년 M월 d일').format(picked);
      _fieldControllers[field]?.text = formatted;
      setState(() => _lunarDates[field] = _toLunarFromDate(formatted));
    }
  }

  /// 마감일 필드용: 날짜 + 시간을 선택하고 알람 형식으로 저장
  Future<void> _pickAlarmDateTime(String field) async {
    // 1) 기존 값 파싱 시도
    DateTime initialDate = DateTime.now().add(const Duration(hours: 1));
    final currentText = _fieldControllers[field]?.text ?? '';
    if (currentText.isNotEmpty) {
      try {
        initialDate = DateFormat(_alarmDateTimeFormat).parse(currentText);
      } catch (_) {}
    }

    // 2) 날짜 선택
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime(2100),
      locale: const Locale('ko', 'KR'),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: _catColor,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: AppTheme.textPrimary,
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: _catColor,
                textStyle: const TextStyle(fontSize: 18),
              ),
            ),
            datePickerTheme: DatePickerThemeData(
              headerHelpStyle: const TextStyle(fontSize: 18),
              dayStyle: const TextStyle(fontSize: 16),
              yearStyle: const TextStyle(fontSize: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
          child: child!,
        );
      },
    );

    if (pickedDate == null || !mounted) return;

    // 3) 시간 선택 (input 방식 - dial 전환 가능)
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initialDate.hour, minute: initialDate.minute),
      initialEntryMode: TimePickerEntryMode.input,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).brightness == Brightness.dark
                ? ColorScheme.dark(
                    primary: _catColor,
                    onPrimary: Colors.white,
                    surface: const Color(0xFF2C2C2E),
                  )
                : ColorScheme.light(
                    primary: _catColor,
                    onPrimary: Colors.white,
                  ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(foregroundColor: _catColor),
            ),
          ),
          child: child!,
        );
      },
    );

    if (pickedTime == null) return;

    // 4) 합쳐서 저장
    final combined = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );
    final formatted = DateFormat(_alarmDateTimeFormat).format(combined);
    _fieldControllers[field]?.text = formatted;
    setState(() {
      _lunarDates[field] = _toLunarFromAlarm(formatted);
      _bellTrigger++;  // 벨 흔들림 애니메이션 트리거
    });
  }

  Future<void> _pickDateTime(String field) async {
    final dayOfWeek = await _pickDayOfWeek();
    if (dayOfWeek == null) return;

    final time = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 10, minute: 0),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: _catColor,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: AppTheme.textPrimary,
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: _catColor,
                textStyle: const TextStyle(fontSize: 18),
              ),
            ),
          ),
          child: child!,
        );
      },
    );

    if (time != null) {
      final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
      final period = time.period == DayPeriod.am ? '오전' : '오후';
      final minute = time.minute > 0 ? ' ${time.minute}분' : '';
      final formatted = '$dayOfWeek $period $hour시$minute';
      _fieldControllers[field]?.text = formatted;
      setState(() {});
    }
  }


  Future<String?> _pickDayOfWeek() async {
    const days = ['월요일', '화요일', '수요일', '목요일', '금요일', '토요일', '일요일'];
    const shortDays = ['월', '화', '수', '목', '금', '토', '일'];

    return await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text(
            '요일을 선택하세요',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            textAlign: TextAlign.center,
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: List.generate(7, (i) {
                final isWeekend = i >= 5;
                return GestureDetector(
                  onTap: () => Navigator.pop(ctx, days[i]),
                  child: Container(
                    width: 72,
                    height: 56,
                    decoration: BoxDecoration(
                      color: isWeekend
                          ? const Color(0xFFFFF3E0)
                          : const Color(0xFFE8EAF6),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isWeekend
                            ? const Color(0xFFFF9800)
                            : AppTheme.primaryColor,
                        width: 2,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        shortDays[i],
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: isWeekend
                              ? const Color(0xFFFF9800)
                              : AppTheme.primaryColor,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        );
      },
    );
  }

  /// 알람 필드에 값이 있으면 "⏰ 2월 28일 오후 2:48에 알림을 드릴게요!" 반환
  String _alarmConfirmMessage() {
    for (final field in widget.category.fields) {
      if (!widget.category.isAlarmDateTimeField(field)) continue;
      final val = _fieldControllers[field]?.text ?? '';
      if (val.isEmpty) break;
      try {
        final dt = DateFormat(_alarmDateTimeFormat).parse(val);
        final timeStr = DateFormat('M월 d일 a h:mm', 'ko').format(dt);
        return '⏰ $timeStr에 알림을 드릴게요!';
      } catch (_) {
        break;
      }
    }
    return '';
  }

  Future<void> _save() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      final data = <String, String>{};
      for (final entry in _fieldControllers.entries) {
        data[entry.key] = entry.value.text.trim();
      }

      final title = data.values.firstWhere((v) => v.isNotEmpty, orElse: () => '새 메모');
      final appState = context.read<AppState>();

      if (_isEditing) {
        final updatedMemo = widget.memo!;
        updatedMemo.title = title;
        updatedMemo.data = data;
        await appState.updateMemo(updatedMemo);
        if (mounted) {
          // 저장 완료 체크 애니메이션
          setState(() => _showSaveCheck = true);
          await Future.delayed(const Duration(milliseconds: 850));
          if (!mounted) return;
          final alarmMsg = _alarmConfirmMessage();
          _showSnackbar(alarmMsg.isNotEmpty ? alarmMsg : '저장했어요! ✅');
          Navigator.pop(context, updatedMemo);
        }
      } else {
        final newMemo = Memo(
          categoryId: widget.category.id,
          title: title,
          data: data,
          isRepeatingAlarm: _isPresetAlarm,
        );
        await appState.addMemo(newMemo);
        if (mounted) {
          // 저장 완료 체크 애니메이션
          setState(() => _showSaveCheck = true);
          await Future.delayed(const Duration(milliseconds: 850));
          if (!mounted) return;
          final alarmMsg = _alarmConfirmMessage();
          _showSnackbar(alarmMsg.isNotEmpty ? alarmMsg : '새 메모를 저장했어요! ✅');
          Navigator.pop(context, newMemo);
        }
      }
    } catch (e) {
      debugPrint('⚠️ _save 오류: $e');
      if (mounted) {
        _showSnackbar('저장 중 오류가 발생했어요. 다시 시도해 주세요 😥');
      }
    } finally {
      // 예외 발생 여부와 상관없이 반드시 저장 상태 해제
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontSize: 18)),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────────────
  // 추천 세트 (할일 카테고리 전용)
  // ────────────────────────────────────────────────────────────────────────

  /// 추천 세트 선택 버튼
  Widget _buildPresetSetButton() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: _showPresetBottomSheet,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFFFF8EE),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _catColor.withOpacity(0.4),
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.auto_awesome, color: _catColor, size: 22),
            const SizedBox(width: 10),
            Text(
              '추천 알림 세트에서 선택하기',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: _catColor,
              ),
            ),
            const Spacer(),
            Icon(Icons.keyboard_arrow_down_rounded, color: _catColor, size: 24),
          ],
        ),
      ),
    );
  }

  /// 추천 세트 바텀 시트 (매일 반복 알림을 위한 시간 설정 포함)
  void _showPresetBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _PresetBottomSheet(
        catColor: _catColor,
        onPresetSelected: (title, pickedTime) {
          // 1) 시간 포맷팅 (오늘 날짜 + 선택한 시간)
          final now = DateTime.now();
          final dt = DateTime(now.year, now.month, now.day, pickedTime.hour, pickedTime.minute);
          final formatted = DateFormat(_alarmDateTimeFormat).format(dt);

          // 2) 할일 필드에 제목 넣고, 마감일 필드에 선택한 시간 바로 입력
          setState(() {
            _fieldControllers['할일']?.text = title;
            _fieldControllers['마감일']?.text = formatted;
            _bellTrigger++; // 종 흔들림 애니메이션 실행
            _isPresetAlarm = true; // 반복 알림 플래그 설정
          });

          Navigator.pop(ctx);
        },
        onMedicineSelected: (medicineName, selectedTimes) {
          Navigator.pop(ctx);
          _createMedicineMemos(medicineName, selectedTimes);
        },
      ),
    );
  }

  /// 약 복용 메모 자동 생성 (아침/점심/저녁 각각)
  Future<void> _createMedicineMemos(
      String medicineName, List<_MealTime> selectedTimes) async {
    if (selectedTimes.isEmpty) return;

    final appState = context.read<AppState>();
    final now = DateTime.now();
    final memos = selectedTimes.map((mealTime) {
      // 파싱 가능한 형식으로 저장 (알림 예약에 사용됨)
      final alarmDt = DateTime(now.year, now.month, now.day, mealTime.hour, mealTime.minute);
      final formatted = DateFormat(_alarmDateTimeFormat).format(alarmDt);
      // 라벨: "아침 (08:00)" → "아침" 만 추출
      final shortLabel = mealTime.label.split(' ').first;

      return Memo(
        categoryId: 'todo',
        title: '$medicineName ($shortLabel)',
        data: {
          '할일': '$medicineName ($shortLabel)',
          '마감일': formatted, // 파싱 가능한 datetime — 알림 예약에 사용됨
        },
        isRepeatingAlarm: true,
      );
    }).toList();

    await appState.addMemos(memos);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '💊 ${selectedTimes.map((t) => t.label).join(', ')} 알림이 등록됐어요!',
            style: const TextStyle(fontSize: 17),
          ),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          duration: const Duration(seconds: 3),
        ),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = _primaryFields();
    final secondary = _secondaryFields();
    final hasHiddenValues = !_showExtra &&
        secondary.any((f) => (widget.memo?.data[f] ?? _fieldControllers[f]?.text ?? '').isNotEmpty);

    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      children: [
      Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: Text(_isEditing ? '메모 수정' : '새 메모'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, size: 28),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isSaving ? null : _save,
        backgroundColor: _isSaving ? Colors.grey[400] : _catColor,
        elevation: 6,
        icon: const Icon(Icons.check_rounded, size: 28, color: Colors.white),
        label: Text(
          _isSaving
              ? '저장 중...'
              : (_isEditing ? '수정 완료' : '저장하기'),
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 추천 세트 버튼 (할일 카테고리, 새 메모 작성 시만 표시) ──
            if (widget.category.id == 'todo' && !_isEditing) ...[
              _buildPresetSetButton(),
              const SizedBox(height: 16),
            ],
            // ── 주요 필드 ──────────────────────────────────────────────
            for (int i = 0; i < primary.length; i++) ...[
              _buildFieldWidget(primary[i]),
              // 첫 번째 필드 바로 아래: 유사 메모 경고 배너
              if (i == 0 && _similarMemos.isNotEmpty)
                _buildDuplicateBanner(),
            ],

            // ── 추가 정보 토글 (secondary 필드가 있을 때만) ────────────
            if (secondary.isNotEmpty) ...[
              const SizedBox(height: 4),
              GestureDetector(
                onTap: () => setState(() => _showExtra = !_showExtra),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: _showExtra
                        ? _catColor.withOpacity(0.08)
                        : (Theme.of(context).brightness == Brightness.dark
                            ? const Color(0xFF2C2C2E)
                            : const Color(0xFFF5F5F5)),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _showExtra
                          ? _catColor.withOpacity(0.4)
                          : (Theme.of(context).brightness == Brightness.dark
                              ? Colors.grey[700]!
                              : const Color(0xFFE0E0E0)),
                      width: 1.2,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _showExtra
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        color: _catColor,
                        size: 26,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _showExtra ? '추가 정보 접기' : '추가 정보 입력하기',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: _catColor,
                        ),
                      ),
                      // 숨겨진 값이 있을 때 알림 점
                      if (hasHiddenValues) ...[
                        const SizedBox(width: 6),
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: Colors.orange[600],
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // ── secondary 필드 (펼쳤을 때) ──────────────────────────
              if (_showExtra)
                for (final field in secondary) _buildFieldWidget(field),
            ],
          ],
        ),
      ),
    ),  // Scaffold 닫기
    // ── 저장 완료 체크 오버레이 ──────────────────────────────────
    if (_showSaveCheck)
      Positioned.fill(
        child: Container(
          color: Colors.black.withOpacity(0.35),
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
              decoration: BoxDecoration(
                color: isDarkMode ? const Color(0xFF1C1C1E) : Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 24, offset: Offset(0, 8)),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle_rounded, color: Colors.green[600], size: 80)
                      .animate()
                      .scale(
                        begin: const Offset(0.3, 0.3),
                        end: const Offset(1.0, 1.0),
                        duration: const Duration(milliseconds: 450),
                        curve: Curves.elasticOut,
                      )
                      .fadeIn(duration: const Duration(milliseconds: 300)),
                  const SizedBox(height: 14),
                  Text(
                    '저장됐어요!',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: isDarkMode ? Colors.white : const Color(0xFF222222),
                    ),
                  ).animate().fadeIn(
                        delay: const Duration(milliseconds: 200),
                        duration: const Duration(milliseconds: 300),
                      ),
                ],
              ),
            ),
          ),
        ),
      ),
    ],  // Stack children 닫기
  );  // Stack 닫기
  }

  Widget _buildAlarmDateTimeButton(String field) {
    final hasValue = (_fieldControllers[field]?.text ?? '').isNotEmpty;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => _pickAlarmDateTime(field),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: hasValue
                  ? _catColor.withOpacity(isDark ? 0.12 : 0.06)
                  : (isDark ? const Color(0xFF2C2C2E) : Colors.white),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: hasValue
                    ? _catColor.withOpacity(0.5)
                    : (isDark ? Colors.grey[700]! : const Color(0xFFE0E0E0)),
                width: hasValue ? 1.5 : 1.2,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: _catColor.withOpacity(isDark ? 0.25 : 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: _bellTrigger > 0
                      ? Icon(Icons.alarm, color: _catColor, size: 20)
                          .animate(key: ValueKey(_bellTrigger))
                          .shake(
                            duration: const Duration(milliseconds: 700),
                            hz: 3,
                            rotation: 0.12,
                            offset: const Offset(0, 0),
                          )
                      : Icon(Icons.alarm, color: _catColor, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    hasValue
                        ? _fieldControllers[field]!.text
                        : '날짜와 시간을 선택하세요',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: hasValue ? FontWeight.w600 : FontWeight.w400,
                      color: hasValue
                          ? (isDark ? Colors.grey[100] : const Color(0xFF222222))
                          : (isDark ? Colors.grey[600] : const Color(0xFFBBBBBB)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        // 음력 표시는 생일/기념일 카테고리에만
        if (widget.category.id == 'birthday' && (_lunarDates[field] ?? '').isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4, left: 4),
            child: Row(
              children: [
                Icon(Icons.brightness_3,
                    size: 12,
                    color: isDark ? Colors.indigo[200] : Colors.indigo[300]),
                const SizedBox(width: 4),
                Text(
                  _lunarDates[field]!,
                  style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.indigo[200] : Colors.indigo[400]),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Text(
            '🔔 시간을 설정하면 지정한 시각에 알림을 보내드려요',
            style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.grey[500] : Colors.grey[500]),
          ),
        ),
      ],
    );
  }

  /// '날짜' 필드에 날짜가 입력됐을 때 알림 예약 안내 문구 반환
  /// ex) "🔔 2025년 5월 14일 오전 9시에 알림이 발송됩니다"
  String _birthdayNoticeText(String dateValue) {
    try {
      final date = DateFormat('yyyy년 M월 d일').parse(dateValue);
      // 하루 전 날짜
      final notifyDate = date.subtract(const Duration(days: 1));
      final formatted = DateFormat('M월 d일').format(notifyDate);
      return '🔔 $formatted 오전 9시에 알림이 발송됩니다';
    } catch (_) {
      return '🔔 날짜를 설정하면 하루 전 오전 9시에 알림을 드려요';
    }
  }

  Widget _buildDateButton(String field) {
    final value = _fieldControllers[field]?.text ?? '';
    final hasValue = value.isNotEmpty;
    final lunarText = _lunarDates[field] ?? '';
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // '날짜' 필드만 알림 안내 표시 (생일/기념일, 약속/모임 등)
    final showNoticeHint = field == '날짜';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => _pickDate(field),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: hasValue
                  ? _catColor.withOpacity(isDark ? 0.12 : 0.06)
                  : (isDark ? const Color(0xFF2C2C2E) : Colors.white),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: hasValue
                    ? _catColor.withOpacity(0.5)
                    : (isDark ? Colors.grey[700]! : const Color(0xFFE0E0E0)),
                width: hasValue ? 1.5 : 1.2,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: _catColor.withOpacity(isDark ? 0.25 : 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.calendar_today, color: _catColor, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hasValue ? value : '날짜를 선택하세요',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: hasValue ? FontWeight.w600 : FontWeight.w400,
                          color: hasValue
                              ? (isDark ? Colors.grey[100] : const Color(0xFF222222))
                              : (isDark ? Colors.grey[600] : const Color(0xFFBBBBBB)),
                        ),
                      ),
                      // 음력 표시는 생일/기념일 카테고리에만
                      if (widget.category.id == 'birthday' && lunarText.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Icon(Icons.brightness_3,
                                size: 12,
                                color: isDark ? Colors.indigo[200] : Colors.indigo[300]),
                            const SizedBox(width: 4),
                            Text(
                              lunarText,
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark ? Colors.indigo[200] : Colors.indigo[400],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        // 알림 예약 안내 (날짜 필드에만 표시)
        if (showNoticeHint) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              hasValue
                  ? _birthdayNoticeText(value)
                  : '🔔 날짜를 설정하면 하루 전 오전 9시에 알림을 드려요',
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.grey[500] : Colors.grey[500],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildDateTimeButton(String field) {
    final hasValue = (_fieldControllers[field]?.text ?? '').isNotEmpty;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: () => _pickDateTime(field),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: hasValue
              ? _catColor.withOpacity(isDark ? 0.12 : 0.06)
              : (isDark ? const Color(0xFF2C2C2E) : Colors.white),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: hasValue
                ? _catColor.withOpacity(0.5)
                : (isDark ? Colors.grey[700]! : const Color(0xFFE0E0E0)),
            width: hasValue ? 1.5 : 1.2,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: _catColor.withOpacity(isDark ? 0.25 : 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.access_time, color: _catColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                hasValue ? _fieldControllers[field]!.text : '요일과 시간을 선택하세요',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: hasValue ? FontWeight.w600 : FontWeight.w400,
                  color: hasValue
                      ? (isDark ? Colors.grey[100] : const Color(0xFF222222))
                      : (isDark ? Colors.grey[600] : const Color(0xFFBBBBBB)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 개별 필드 위젯 (라벨 + 입력 컨트롤)
  Widget _buildFieldWidget(String field) {
    final isSensitive = widget.category.isSensitiveField(field);
    final isNumeric = widget.category.isNumericField(field);
    final isDate = widget.category.isDateField(field);
    final isDateTime = widget.category.isDateTimeField(field);
    final isAlarmDateTime = widget.category.isAlarmDateTimeField(field);
    final isObscure = _obscureFields[field] ?? false;

    // 반복 알림 메모 편집 시 '마감일' 라벨 숨기기 (알림 시간 버튼만 표시)
    bool hideLabel = field == '마감일' && (widget.memo?.isRepeatingAlarm == true);

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 매일 반복 알림일 때는 라벨을 숨김 (깔끔한 UI)
          if (!hideLabel) ...[
            _buildFieldLabel(
              '${field == '마감일' ? '알림 시작' : field} ${isSensitive ? "🔒" : ""}${isDate ? "📅" : ""}${isDateTime ? "🕐" : ""}${isAlarmDateTime ? "⏰" : ""}',
            ),
            const SizedBox(height: 8),
          ],
          if (isDate)
            _buildDateButton(field)
          else if (isAlarmDateTime)
            _buildAlarmDateTimeButton(field)
          else if (isDateTime)
              _buildDateTimeButton(field)
            else
              Builder(builder: (context) {
                final isDark = Theme.of(context).brightness == Brightness.dark;
                return TextField(
                  controller: _fieldControllers[field],
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.grey[100] : const Color(0xFF222222),
                  ),
                  obscureText: isSensitive ? isObscure : false,
                  keyboardType: isNumeric
                      ? TextInputType.number
                      : field == '메모'
                      ? TextInputType.multiline
                      : TextInputType.text,
                  maxLines: isSensitive ? 1 : (field == '메모' ? 3 : 1),
                  decoration: InputDecoration(
                    hintText: '${_eul(field)} 입력하세요',
                    hintStyle: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w400,
                      color: isDark ? Colors.grey[600] : const Color(0xFFBBBBBB),
                    ),
                    filled: true,
                    fillColor: isDark ? const Color(0xFF2C2C2E) : Colors.white,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: isDark ? Colors.grey[700]! : const Color(0xFFE0E0E0),
                        width: 1.2,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: _catColor, width: 2),
                    ),
                    suffixIcon: isSensitive
                        ? IconButton(
                      icon: Icon(
                        isObscure ? Icons.visibility_off : Icons.visibility,
                        color: _catColor,
                        size: 24,
                      ),
                      onPressed: () => setState(() => _obscureFields[field] = !isObscure),
                    )
                        : IconButton(
                      icon: Icon(
                        Icons.mic_none,
                        color: _catColor.withAlpha(160),
                      ),
                      onPressed: () => _toggleListening(field),
                    ),
                  ),
                );
              }),
        ],
      ),
    );
  }
  /// 유사 메모 경고 배너 (첫 번째 필드 아래에 표시)
  Widget _buildDuplicateBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFB300), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '⚠️ 비슷한 메모가 있어요!',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Color(0xFFE65100),
            ),
          ),
          const SizedBox(height: 6),
          ..._similarMemos.take(2).map(
                (m) => Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    '• ${m.title}',
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF6D4C41),
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildFieldLabel(String label) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 4,
          height: 18,
          margin: const EdgeInsets.only(right: 8),
          decoration: BoxDecoration(
            color: _catColor,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.grey[200] : const Color(0xFF444444),
          ),
        ),
      ],
    );
  }
}
// --- 여기서부터 파일 맨 끝까지 '기존에 우리가 추가했던 클래스들'을 전부 덮어쓰기 하세요 ---

/// 약 복용 및 추천 할 일 시간대를 정의하는 모델 클래스
class _MealTime {
  final String label;
  final int hour;
  final int minute;
  bool isSelected;

  _MealTime({
    required this.label,
    required this.hour,
    this.minute = 0,
    this.isSelected = false,
  });
}

/// 추천 알림 세트 선택을 위한 바텀 시트 위젯 (최종 통합본)
class _PresetBottomSheet extends StatefulWidget {
  final Color catColor;
  final Function(String, TimeOfDay) onPresetSelected;
  final Function(String, List<_MealTime>) onMedicineSelected;

  const _PresetBottomSheet({
    super.key,
    required this.catColor,
    required this.onPresetSelected,
    required this.onMedicineSelected,
  });

  @override
  State<_PresetBottomSheet> createState() => _PresetBottomSheetState();
}

class _PresetBottomSheetState extends State<_PresetBottomSheet> {
  final TextEditingController _medicineController = TextEditingController(text: '💊 약 먹기');

  // 추천 세트 목록
  final List<String> _generalPresets = [
    '🐶 애완동물 밥주기', '⏰ 기상 알림', '🧘 스트레칭', '🪟 환기하기', '🏃 산책', '💪 운동'
  ];

  // 약 복용 시간대 (시간 표시 포함)
  final List<_MealTime> _mealTimes = [
    _MealTime(label: '아침 (08:00)', hour: 8),
    _MealTime(label: '점심 (12:00)', hour: 12),
    _MealTime(label: '저녁 (19:00)', hour: 19),
  ];

  @override
  void dispose() {
    _medicineController.dispose();
    super.dispose();
  }

  // 추천 항목 클릭 시 시간을 선택하게 하는 함수
  Future<void> _handlePresetClick(String title) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 9, minute: 0),
      helpText: '매일 알림을 받을 시간을 선택하세요',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(primary: widget.catColor),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      widget.onPresetSelected(title, picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        top: 20, left: 20, right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 30,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[400], borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 20),
            const Text('💡 추천 할 일 세트', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange.withOpacity(0.45), width: 1.2),
              ),
              child: const Row(
                children: [
                  Icon(Icons.notifications_active, size: 18, color: Colors.deepOrange),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '추천세트와 시간을 설정하면 매일 한번씩 알림을 드려요',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.deepOrange,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // 일반 추천 칩
            Wrap(
              spacing: 8, runSpacing: 8,
              children: _generalPresets.map((preset) => ActionChip(
                label: Text(preset, style: const TextStyle(fontSize: 15)),
                backgroundColor: isDark ? Colors.grey[800] : Colors.grey[100],
                onPressed: () => _handlePresetClick(preset),
              )).toList(),
            ),

            const Divider(height: 40, thickness: 1),

            const Text('💊 약 먹기 (매일 반복)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),
            TextField(
              controller: _medicineController,
              decoration: InputDecoration(
                labelText: '약 이름',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: isDark ? Colors.grey[900] : Colors.grey[50],
              ),
            ),
            const SizedBox(height: 15),

            // [오버플로우 방지] Row 대신 Wrap 사용
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: _mealTimes.map((mt) => FilterChip(
                label: Text(mt.label, style: const TextStyle(fontSize: 13)),
                selected: mt.isSelected,
                selectedColor: widget.catColor.withOpacity(0.2),
                checkmarkColor: widget.catColor,
                onSelected: (val) => setState(() => mt.isSelected = val),
              )).toList(),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: widget.catColor,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: () {
                  final selected = _mealTimes.where((t) => t.isSelected).toList();
                  if (selected.isNotEmpty) widget.onMedicineSelected(_medicineController.text, selected);
                },
                child: const Text('매일 알림 등록', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}