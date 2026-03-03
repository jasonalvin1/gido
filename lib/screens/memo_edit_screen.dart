import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:lunar/lunar.dart';
import 'package:speech_to_text/speech_to_text.dart';
import '../models/memo_model.dart';
import '../services/app_state.dart';
import '../utils/app_theme.dart';

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

  Future<void> _pickDate(String field) async {
    DateTime initialDate = DateTime.now();
    final currentText = _fieldControllers[field]?.text ?? '';
    if (currentText.isNotEmpty) {
      try {
        initialDate = DateFormat('yyyy년 M월 d일').parse(currentText);
      } catch (_) {}
    }

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(1920),
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

    if (picked != null) {
      final formatted = DateFormat('yyyy년 M월 d일').format(picked);
      _fieldControllers[field]?.text = formatted;
      setState(() {
        _lunarDates[field] = _toLunarFromDate(formatted);
      });
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

    // 3) 시간 선택
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initialDate.hour, minute: initialDate.minute),
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
        final alarmMsg = _alarmConfirmMessage();
        _showSnackbar(alarmMsg.isNotEmpty ? alarmMsg : '저장했어요! ✅');
        Navigator.pop(context, updatedMemo);
      }
    } else {
      final newMemo = Memo(
        categoryId: widget.category.id,
        title: title,
        data: data,
      );
      await appState.addMemo(newMemo);
      if (mounted) {
        final alarmMsg = _alarmConfirmMessage();
        _showSnackbar(alarmMsg.isNotEmpty ? alarmMsg : '새 메모를 저장했어요! ✅');
        Navigator.pop(context, newMemo);
      }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? '메모 수정' : '새 메모'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, size: 28),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 필드를 index와 함께 순회하여 첫 번째 필드 뒤에 중복 배너 삽입
            for (int i = 0; i < widget.category.fields.length; i++) ...[
              _buildFieldWidget(widget.category.fields[i]),

              // ▼ 첫 번째 필드 바로 아래: 유사 메모 경고 배너
              if (i == 0 && _similarMemos.isNotEmpty)
                _buildDuplicateBanner(),
            ],

            const SizedBox(height: 8),

            SizedBox(
              width: double.infinity,
              height: AppTheme.minTouchTarget,
              child: ElevatedButton.icon(
                onPressed: _isSaving ? null : _save,
                icon: Image.asset('assets/icons/save.png', width: 28, height: 28),
                label: Text(_isSaving ? '저장 중...' : '저장하기'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _catColor,
                  foregroundColor: Colors.white,
                ),
              ),
            ),

            const SizedBox(height: 8),

            SizedBox(
              width: double.infinity,
              height: AppTheme.minTouchTarget,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFE0E0E0), width: 2),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text(
                  '취소',
                  style: TextStyle(
                    fontSize: AppTheme.fontSizeMedium,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildAlarmDateTimeButton(String field) {
    final hasValue = (_fieldControllers[field]?.text ?? '').isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => _pickAlarmDateTime(field),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: hasValue ? _catColor : const Color(0xFFE0E0E0),
                width: 2,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    hasValue
                        ? _fieldControllers[field]!.text
                        : '⏰ 날짜와 시간을 선택하세요',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: hasValue ? FontWeight.w500 : FontWeight.w400,
                      color: hasValue
                          ? AppTheme.textPrimary
                          : const Color(0xFFBBBBBB),
                    ),
                  ),
                ),
                Icon(Icons.alarm, color: _catColor, size: 28),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        // 음력 날짜 표시 (할일 마감일)
        if ((_lunarDates[field] ?? '').isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4, left: 4),
            child: Row(
              children: [
                Icon(Icons.brightness_3, size: 14, color: Colors.indigo[300]),
                const SizedBox(width: 4),
                Text(
                  _lunarDates[field]!,
                  style: TextStyle(fontSize: 14, color: Colors.indigo[300]),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Text(
            '🔔 시간을 설정하면 지정한 시각에 알림을 보내드려요',
            style: TextStyle(fontSize: 15, color: Colors.grey[500]),
          ),
        ),
      ],
    );
  }

  Widget _buildDateButton(String field) {
    final value = _fieldControllers[field]?.text ?? '';
    final hasValue = value.isNotEmpty;
    final lunarText = _lunarDates[field] ?? '';
    // 생일 카테고리: 음력 생일의 올해 양력 계산
    final birthdayText = (widget.category.id == 'birthday' && hasValue)
        ? _getLunarBirthdayThisYear(value)
        : '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => _pickDate(field),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: hasValue ? _catColor : const Color(0xFFE0E0E0),
                width: 2,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    hasValue ? value : '📅 날짜를 선택하세요',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: hasValue ? FontWeight.w500 : FontWeight.w400,
                      color: hasValue ? AppTheme.textPrimary : const Color(0xFFBBBBBB),
                    ),
                  ),
                ),
                Icon(Icons.calendar_today, color: _catColor, size: 28),
              ],
            ),
          ),
        ),
        // 음력 날짜 표시
        if (lunarText.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Row(
              children: [
                Icon(Icons.brightness_3, size: 14, color: Colors.indigo[300]),
                const SizedBox(width: 4),
                Text(
                  lunarText,
                  style: TextStyle(fontSize: 14, color: Colors.indigo[300]),
                ),
              ],
            ),
          ),
        // 생일 카테고리: 올해 음력 생일 양력 D-day
        if (birthdayText.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 4),
            child: Text(
              birthdayText,
              style: const TextStyle(fontSize: 13, color: Color(0xFFE91E63)),
            ),
          ),
      ],
    );
  }

  Widget _buildDateTimeButton(String field) {
    final hasValue = (_fieldControllers[field]?.text ?? '').isNotEmpty;
    return GestureDetector(
      onTap: () => _pickDateTime(field),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: hasValue ? _catColor : const Color(0xFFE0E0E0),
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                hasValue ? _fieldControllers[field]!.text : '🕐 요일과 시간을 선택하세요',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: hasValue ? FontWeight.w500 : FontWeight.w400,
                  color: hasValue ? AppTheme.textPrimary : const Color(0xFFBBBBBB),
                ),
              ),
            ),
            Icon(Icons.access_time, color: _catColor, size: 28),
          ],
        ),
      ),
    );
  }

  /// 개별 필드 위젯 (라벨 + 입력 컨트롤)
  Widget _buildFieldWidget(String field) {
    final isSensitive = widget.category.isSensitiveField(field);
    final isNumeric   = widget.category.isNumericField(field);
    final isDate      = widget.category.isDateField(field);
    final isDateTime  = widget.category.isDateTimeField(field);
    final isAlarmDateTime = widget.category.isAlarmDateTimeField(field);
    final isObscure   = _obscureFields[field] ?? false;

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFieldLabel(
            '$field ${isSensitive ? "🔒" : ""}${isDate ? "📅" : ""}${isDateTime ? "🕐" : ""}${isAlarmDateTime ? "⏰" : ""}',
          ),
          const SizedBox(height: 8),

          if (isDate)
            _buildDateButton(field)
          else if (isAlarmDateTime)
            _buildAlarmDateTimeButton(field)
          else if (isDateTime)
            _buildDateTimeButton(field)
          else
            TextField(
              controller: _fieldControllers[field],
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w500),
              obscureText: isSensitive ? isObscure : false,
              keyboardType: isNumeric
                  ? TextInputType.number
                  : field == '메모'
                      ? TextInputType.multiline
                      : TextInputType.text,
              maxLines: isSensitive ? 1 : (field == '메모' ? 3 : 1),
              decoration: InputDecoration(
                hintText: '${_eul(field)} 입력하세요',
                suffixIcon: isSensitive
                    // 민감 필드: 눈 아이콘만
                    ? IconButton(
                        icon: Icon(
                          isObscure ? Icons.visibility_off : Icons.visibility,
                          color: _catColor,
                          size: 26,
                        ),
                        onPressed: () =>
                            setState(() => _obscureFields[field] = !isObscure),
                      )
                    // 일반 필드: 마이크 아이콘
                    : IconButton(
                        icon: Icon(
                          _activeListeningField == field
                              ? Icons.mic
                              : Icons.mic_none,
                          color: _activeListeningField == field
                              ? Colors.red
                              : _catColor.withAlpha(160),
                          size: 26,
                        ),
                        tooltip: _activeListeningField == field
                            ? '녹음 중 (탭하면 중지)'
                            : '음성으로 입력',
                        onPressed: () => _toggleListening(field),
                      ),
              ),
            ),
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
    return Text(
      label,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: Color(0xFF555555),
      ),
    );
  }
}