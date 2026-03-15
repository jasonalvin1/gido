import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lunar/lunar.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 네이버 달력 스타일 달력 피커
/// [반환값] 항상 양력 DateTime.
/// 음력 입력 모드(스위치 ON)에서는 내부에서 음력→양력 변환 후 반환하므로
/// 호출부(memo_edit_screen)의 저장 로직 변경 불필요 — 하위 호환성 유지.
Future<DateTime?> showLunarCalendarPicker({
  required BuildContext context,
  required Color themeColor,
  DateTime? initialDate,
}) {
  return showDialog<DateTime>(
    context: context,
    builder: (_) => _LunarCalendarDialog(
      initialDate: initialDate ?? DateTime.now(),
      themeColor: themeColor,
    ),
  );
}

/// 음력 모드 달력 셀에 표시할 날짜 쌍 (음력 일 + 대응 양력)
class _LunarDayInfo {
  final int lunarDay;
  final DateTime solarDate;
  const _LunarDayInfo({required this.lunarDay, required this.solarDate});
}

// ── 달력 다이얼로그 ─────────────────────────────────────────────────────────
class _LunarCalendarDialog extends StatefulWidget {
  final DateTime initialDate;
  final Color themeColor;

  const _LunarCalendarDialog({
    required this.initialDate,
    required this.themeColor,
  });

  @override
  State<_LunarCalendarDialog> createState() => _LunarCalendarDialogState();
}

class _LunarCalendarDialogState extends State<_LunarCalendarDialog> {
  // 양력 모드: 현재 보고 있는 양력 월
  late DateTime _focusedMonth;

  // 공통: 현재 선택된 날짜 (항상 양력으로 관리)
  late DateTime _selectedSolar;
  bool _showYearMonth = false;

  // 입력 모드 (false=양력 입력, true=음력 입력)
  bool _isLunarMode = false;

  // 음력 모드: 현재 탐색 중인 음력 연/월/윤달
  late int _lunarYear;
  late int _lunarMonth;
  bool _isLeapMonth = false;

  // 기존 pref 키 유지 → 앱 재시작 후에도 마지막 선택 모드 복원 (하위 호환)
  static const _prefKey = 'calendar_show_lunar';
  static const _weekdays = ['일', '월', '화', '수', '목', '금', '토'];

  @override
  void initState() {
    super.initState();
    _selectedSolar = widget.initialDate;
    _focusedMonth = DateTime(widget.initialDate.year, widget.initialDate.month);

    // 음력 초기 위치: initialDate(양력)에 해당하는 음력 연/월로 설정
    try {
      final s = Solar.fromYmd(
          widget.initialDate.year,
          widget.initialDate.month,
          widget.initialDate.day);
      final l = s.getLunar();
      _lunarYear = l.getYear();
      _lunarMonth = l.getMonth().abs();
    } catch (_) {
      _lunarYear = widget.initialDate.year;
      _lunarMonth = widget.initialDate.month;
    }

    _loadPref();
  }

  Future<void> _loadPref() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() => _isLunarMode = prefs.getBool(_prefKey) ?? false);
    }
  }

  Future<void> _toggleLunarMode() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isLunarMode = !_isLunarMode;
      _isLeapMonth = false;
    });
    await prefs.setBool(_prefKey, _isLunarMode);
  }

  // ── 양력 모드용 음력 라벨 (네이버 스타일) ──────────────────────────────
  // 음력 1일 → "M월 1" (월 정보 포함), 나머지 → 숫자만
  String _lunarLabel(DateTime date) {
    try {
      final s = Solar.fromYmd(date.year, date.month, date.day);
      final l = s.getLunar();
      final d = l.getDay();
      final m = l.getMonth().abs();
      return d == 1 ? '$m월 1' : '$d';
    } catch (_) {
      return '';
    }
  }

  // 해당 음력 연/월에 윤달이 있는지 확인
  // 6tail/lunar 패키지: 음수 월 = 윤달. throw 없이 생성되면 윤달 존재.
  bool _hasLeapMonth(int year, int month) {
    try {
      Lunar.fromYmd(year, -month, 1);
      return true;
    } catch (_) {
      return false;
    }
  }

  // 현재 음력 연/월/윤달 설정에 해당하는 날짜 목록 생성 (최대 30일)
  // 각 항목: 음력 일(1~30) + 대응하는 양력 DateTime
  List<_LunarDayInfo> _buildLunarDays() {
    final result = <_LunarDayInfo>[];
    // 윤달이면 음수 월로 생성 (6tail/lunar 패키지 규칙)
    final effectiveMonth = _isLeapMonth ? -_lunarMonth : _lunarMonth;
    for (int d = 1; d <= 30; d++) {
      try {
        final l = Lunar.fromYmd(_lunarYear, effectiveMonth, d);
        final s = l.getSolar();
        result.add(_LunarDayInfo(
          lunarDay: d,
          solarDate: DateTime(s.getYear(), s.getMonth(), s.getDay()),
        ));
      } catch (_) {
        break; // 해당 음력 월의 마지막 날 이후
      }
    }
    return result;
  }

  // 양력 달력 날짜 목록 (앞쪽 빈칸 null 포함, 일요일 시작)
  List<DateTime?> _buildSolarDays() {
    final first = DateTime(_focusedMonth.year, _focusedMonth.month, 1);
    final last = DateTime(_focusedMonth.year, _focusedMonth.month + 1, 0);
    final offset = first.weekday % 7; // 일요일=0

    final days = <DateTime?>[];
    for (int i = 0; i < offset; i++) days.add(null);
    for (int d = 1; d <= last.day; d++) {
      days.add(DateTime(_focusedMonth.year, _focusedMonth.month, d));
    }
    while (days.length % 7 != 0) days.add(null);
    return days;
  }

  void _prevMonth() {
    setState(() {
      if (_isLunarMode) {
        _lunarMonth--;
        if (_lunarMonth < 1) {
          _lunarMonth = 12;
          _lunarYear--;
        }
        _isLeapMonth = false;
      } else {
        _focusedMonth =
            DateTime(_focusedMonth.year, _focusedMonth.month - 1);
      }
    });
  }

  void _nextMonth() {
    setState(() {
      if (_isLunarMode) {
        _lunarMonth++;
        if (_lunarMonth > 12) {
          _lunarMonth = 1;
          _lunarYear++;
        }
        _isLeapMonth = false;
      } else {
        _focusedMonth =
            DateTime(_focusedMonth.year, _focusedMonth.month + 1);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasLeap = _isLunarMode && _hasLeapMonth(_lunarYear, _lunarMonth);

    return Dialog(
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── 헤더: 이전/다음 + 연월 표시 + 음력 스위치 ───────────────
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: _showYearMonth ? null : _prevMonth,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 36, minHeight: 36),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () =>
                        setState(() => _showYearMonth = !_showYearMonth),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // FittedBox로 감싸 텍스트가 길어져도 overflow 방지
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              _isLunarMode
                                  ? '음력 $_lunarYear년 $_lunarMonth월'
                                      '${_isLeapMonth ? ' (윤달)' : ''}'
                                  : DateFormat('yyyy년 M월')
                                      .format(_focusedMonth),
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        Icon(
                          _showYearMonth
                              ? Icons.arrow_drop_up
                              : Icons.arrow_drop_down,
                          size: 22,
                        ),
                      ],
                    ),
                  ),
                ),
                // 음력 입력 모드 토글
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '음력',
                      style: TextStyle(
                        fontSize: 12,
                        color: _isLunarMode
                            ? widget.themeColor
                            : Colors.grey[400],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Transform.scale(
                      scale: 0.72,
                      child: Switch(
                        value: _isLunarMode,
                        onChanged: (_) => _toggleLunarMode(),
                        activeColor: widget.themeColor,
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: _showYearMonth ? null : _nextMonth,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 36, minHeight: 36),
                ),
              ],
            ),

            // ── 연도/월 선택기 (헤더 탭 시 표시) ────────────────────────
            if (_showYearMonth)
              _YearMonthPicker(
                focusedYear:
                    _isLunarMode ? _lunarYear : _focusedMonth.year,
                focusedMonth:
                    _isLunarMode ? _lunarMonth : _focusedMonth.month,
                themeColor: widget.themeColor,
                isLunar: _isLunarMode,
                onSelected: (year, month) {
                  setState(() {
                    if (_isLunarMode) {
                      _lunarYear = year;
                      _lunarMonth = month;
                      _isLeapMonth = false;
                    } else {
                      _focusedMonth = DateTime(year, month);
                    }
                    _showYearMonth = false;
                  });
                },
              )
            else ...[
              const SizedBox(height: 8),

              // ── 윤달 토글 (음력 모드 + 해당 월에 윤달 존재할 때만) ────
              if (hasLeap)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '윤달 입력',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _isLeapMonth
                              ? widget.themeColor
                              : Colors.grey[600],
                        ),
                      ),
                      const SizedBox(width: 2),
                      Transform.scale(
                        scale: 0.72,
                        child: Switch(
                          value: _isLeapMonth,
                          onChanged: (v) =>
                              setState(() => _isLeapMonth = v),
                          activeColor: widget.themeColor,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ],
                  ),
                ),

              // ── 요일 헤더 ─────────────────────────────────────────────
              Row(
                children: List.generate(
                  7,
                  (i) => Expanded(
                    child: Center(
                      child: Text(
                        _weekdays[i],
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: i == 0
                              ? Colors.red[400]
                              : i == 6
                                  ? Colors.blue[400]
                                  : isDark
                                      ? Colors.grey[300]
                                      : Colors.grey[700],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),

              // ── 날짜 그리드 (음력/양력 모드에 따라 분기) ─────────────
              if (_isLunarMode)
                _buildLunarGrid(isDark)
              else
                _buildSolarGrid(isDark),
            ],

            // ── 취소 버튼 ─────────────────────────────────────────────
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                    '취소', style: TextStyle(color: Colors.grey[600])),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 음력 모드 달력 그리드 ─────────────────────────────────────────────────
  // 셀 상단: 음력 일(크게) / 셀 하단: 대응 양력 월/일(작게, 참고용)
  // 탭 시 양력 DateTime 반환 → 음력→양력 변환은 여기서 완결
  Widget _buildLunarGrid(bool isDark) {
    final lunarDays = _buildLunarDays();

    if (lunarDays.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Text(
          '해당 음력 날짜를 찾을 수 없어요',
          style: TextStyle(color: Colors.grey),
          textAlign: TextAlign.center,
        ),
      );
    }

    // 첫 번째 음력 날의 요일 오프셋으로 그리드 정렬 (일요일=0)
    final offset = lunarDays.first.solarDate.weekday % 7;
    final cells = <_LunarDayInfo?>[
      ...List<_LunarDayInfo?>.filled(offset, null),
      ...lunarDays,
    ];
    while (cells.length % 7 != 0) cells.add(null);

    final today = DateTime.now();

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        childAspectRatio: 0.75,
      ),
      itemCount: cells.length,
      itemBuilder: (_, i) {
        final cell = cells[i];
        if (cell == null) return const SizedBox.shrink();

        final isSelected = cell.solarDate.year == _selectedSolar.year &&
            cell.solarDate.month == _selectedSolar.month &&
            cell.solarDate.day == _selectedSolar.day;
        final isToday = cell.solarDate.year == today.year &&
            cell.solarDate.month == today.month &&
            cell.solarDate.day == today.day;
        final isSunday = cell.solarDate.weekday == 7;
        final isSaturday = cell.solarDate.weekday == 6;

        final Color dayColor = isSelected
            ? Colors.white
            : isToday
                ? widget.themeColor
                : isSunday
                    ? Colors.red[600]!
                    : isSaturday
                        ? Colors.blue[600]!
                        : isDark
                            ? Colors.grey[200]!
                            : Colors.black87;

        return GestureDetector(
          onTap: () {
            setState(() => _selectedSolar = cell.solarDate);
            Navigator.pop(context, cell.solarDate);
          },
          child: Container(
            margin: const EdgeInsets.all(1.5),
            decoration: BoxDecoration(
              color: isSelected
                  ? widget.themeColor
                  : isToday
                      ? widget.themeColor.withOpacity(0.12)
                      : null,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 음력 일 (크게)
                Text(
                  '${cell.lunarDay}',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: isSelected || isToday
                        ? FontWeight.bold
                        : FontWeight.normal,
                    color: dayColor,
                  ),
                ),
                // 대응 양력 날짜 (작게 — 참고용)
                Text(
                  '${cell.solarDate.month}/${cell.solarDate.day}',
                  style: TextStyle(
                    fontSize: 10,
                    color: isSelected
                        ? Colors.white.withOpacity(0.85)
                        : isDark
                            ? Colors.grey[400]
                            : Colors.grey[500],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── 양력 모드 달력 그리드 ─────────────────────────────────────────────────
  // 음력 라벨 항상 표시 (스위치 없이 자동)
  // 음력 1일 → "M월 1" (테마색), 나머지 → 숫자만 (회색)
  Widget _buildSolarGrid(bool isDark) {
    final days = _buildSolarDays();
    final today = DateTime.now();

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        childAspectRatio: 0.75,
      ),
      itemCount: days.length,
      itemBuilder: (_, i) {
        final date = days[i];
        if (date == null) return const SizedBox.shrink();

        final isToday = date.year == today.year &&
            date.month == today.month &&
            date.day == today.day;
        final isSelected = date.year == _selectedSolar.year &&
            date.month == _selectedSolar.month &&
            date.day == _selectedSolar.day;
        final isSunday = date.weekday == 7;
        final isSaturday = date.weekday == 6;
        final lunar = _lunarLabel(date);
        final isNewLunarMonth = lunar.contains('월');

        final Color dayColor = isSelected
            ? Colors.white
            : isToday
                ? widget.themeColor
                : isSunday
                    ? Colors.red[600]!
                    : isSaturday
                        ? Colors.blue[600]!
                        : isDark
                            ? Colors.grey[200]!
                            : Colors.black87;

        return GestureDetector(
          onTap: () => Navigator.pop(context, date),
          child: Container(
            margin: const EdgeInsets.all(1.5),
            decoration: BoxDecoration(
              color: isSelected
                  ? widget.themeColor
                  : isToday
                      ? widget.themeColor.withOpacity(0.12)
                      : null,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 양력 날짜 (크게)
                Text(
                  '${date.day}',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: isSelected || isToday
                        ? FontWeight.bold
                        : FontWeight.normal,
                    color: dayColor,
                  ),
                ),
                // 음력 라벨 (작게 — 항상 표시)
                if (lunar.isNotEmpty)
                  Text(
                    lunar,
                    style: TextStyle(
                      fontSize: 11,
                      color: isSelected
                          ? Colors.white.withOpacity(0.9)
                          : isNewLunarMonth
                              ? widget.themeColor
                              : isDark
                                  ? Colors.grey[400]
                                  : Colors.grey[600],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ── 연도/월 선택기 ───────────────────────────────────────────────────────────
class _YearMonthPicker extends StatefulWidget {
  final int focusedYear;
  final int focusedMonth;
  final Color themeColor;
  final bool isLunar; // true이면 월 버튼에 "음력 " 접두어 표시
  final void Function(int year, int month) onSelected;

  const _YearMonthPicker({
    required this.focusedYear,
    required this.focusedMonth,
    required this.themeColor,
    required this.isLunar,
    required this.onSelected,
  });

  @override
  State<_YearMonthPicker> createState() => _YearMonthPickerState();
}

class _YearMonthPickerState extends State<_YearMonthPicker> {
  late int _year;
  late ScrollController _scrollController;

  static const _firstYear = 1920;
  static const _lastYear = 2060;

  @override
  void initState() {
    super.initState();
    _year = widget.focusedYear;
    // 선택된 연도가 보이도록 스크롤 위치 초기화 (4열 기준 행 높이 ~36)
    final row = (_year - _firstYear) ~/ 4;
    _scrollController =
        ScrollController(initialScrollOffset: (row * 36.0).clamp(0, 9999));
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final years =
        List.generate(_lastYear - _firstYear + 1, (i) => _firstYear + i);

    return SizedBox(
      height: 220,
      child: Column(
        children: [
          const Divider(height: 12),

          // ── 연도 그리드 ─────────────────────────────────────────────
          Expanded(
            child: GridView.builder(
              controller: _scrollController,
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                childAspectRatio: 2.4,
                mainAxisSpacing: 2,
                crossAxisSpacing: 2,
              ),
              itemCount: years.length,
              itemBuilder: (_, i) {
                final y = years[i];
                final isSel = y == _year;
                return GestureDetector(
                  onTap: () => setState(() => _year = y),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isSel ? widget.themeColor : null,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '$y',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isSel
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: isSel ? Colors.white : Colors.black87,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          const Divider(height: 8),

          // ── 월 버튼 ─────────────────────────────────────────────────
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: List.generate(12, (i) {
              final m = i + 1;
              final isCur =
                  m == widget.focusedMonth && _year == widget.focusedYear;
              return GestureDetector(
                onTap: () => widget.onSelected(_year, m),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isCur ? widget.themeColor : Colors.grey[100],
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    // 음력 모드: "음력 1월" 형식으로 표시
                    '${widget.isLunar ? "음력 " : ""}$m월',
                    style: TextStyle(
                      fontSize: 13,
                      color: isCur ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
