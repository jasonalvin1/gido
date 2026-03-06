import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lunar/lunar.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 네이버 달력 스타일 — 양력(크게) + 음력(작게 아래) 동시 표시
/// 양력/음력 선택 없이 달력 하나로 직관적으로 날짜 선택
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
  late DateTime _focusedMonth;
  late DateTime _selected;
  bool _showYearMonth = false;
  bool _showLunar = true; // 음력 표시 여부 (SharedPreferences로 저장)

  static const _lunarPrefKey = 'calendar_show_lunar';
  static const _weekdays = ['일', '월', '화', '수', '목', '금', '토'];

  @override
  void initState() {
    super.initState();
    _selected = widget.initialDate;
    _focusedMonth =
        DateTime(widget.initialDate.year, widget.initialDate.month);
    _loadLunarPref();
  }

  Future<void> _loadLunarPref() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() => _showLunar = prefs.getBool(_lunarPrefKey) ?? true);
    }
  }

  Future<void> _toggleLunar() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _showLunar = !_showLunar);
    await prefs.setBool(_lunarPrefKey, _showLunar);
  }

  // 네이버 스타일 음력 라벨: 초하루는 "M월", 나머지는 숫자만
  String _lunarLabel(DateTime date) {
    try {
      final s = Solar.fromYmd(date.year, date.month, date.day);
      final l = s.getLunar();
      final d = l.getDay();
      final m = l.getMonth().abs();
      return d == 1 ? '$m월' : '$d';
    } catch (_) {
      return '';
    }
  }

  // 해당 월의 날짜 목록 (앞 빈칸 null 포함)
  List<DateTime?> _buildDays() {
    final first = DateTime(_focusedMonth.year, _focusedMonth.month, 1);
    final last =
        DateTime(_focusedMonth.year, _focusedMonth.month + 1, 0);
    final offset = first.weekday % 7; // 일요일=0

    final days = <DateTime?>[];
    for (int i = 0; i < offset; i++) days.add(null);
    for (int d = 1; d <= last.day; d++) {
      days.add(DateTime(_focusedMonth.year, _focusedMonth.month, d));
    }
    while (days.length % 7 != 0) days.add(null);
    return days;
  }

  @override
  Widget build(BuildContext context) {
    final days = _buildDays();
    final today = DateTime.now();

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
            // ── 헤더 ──────────────────────────────────────────────────────
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => setState(() {
                    _focusedMonth = DateTime(
                        _focusedMonth.year, _focusedMonth.month - 1);
                  }),
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
                      children: [
                        Text(
                          DateFormat('yyyy년 M월').format(_focusedMonth),
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
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
                // 음력 토글
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '음력',
                      style: TextStyle(
                        fontSize: 12,
                        color: _showLunar
                            ? widget.themeColor
                            : Colors.grey[400],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Transform.scale(
                      scale: 0.72,
                      child: Switch(
                        value: _showLunar,
                        onChanged: (_) => _toggleLunar(),
                        activeColor: widget.themeColor,
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => setState(() {
                    _focusedMonth = DateTime(
                        _focusedMonth.year, _focusedMonth.month + 1);
                  }),
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 36, minHeight: 36),
                ),
              ],
            ),

            // ── 연도/월 선택기 (헤더 탭 시 표시) ────────────────────────
            if (_showYearMonth)
              _YearMonthPicker(
                focusedYear: _focusedMonth.year,
                focusedMonth: _focusedMonth.month,
                themeColor: widget.themeColor,
                onSelected: (year, month) {
                  setState(() {
                    _focusedMonth = DateTime(year, month);
                    _showYearMonth = false;
                  });
                },
              )
            else ...[
              const SizedBox(height: 8),

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
                                  : Theme.of(context).brightness == Brightness.dark
                                      ? Colors.grey[300]
                                      : Colors.grey[700],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),

              // ── 날짜 그리드 ───────────────────────────────────────────
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  // 음력 OFF 시 셀 높이 줄임 (1.0 = 정사각형)
                  childAspectRatio: _showLunar ? 0.75 : 1.1,
                ),
                itemCount: days.length,
                itemBuilder: (_, i) {
                  final date = days[i];
                  if (date == null) return const SizedBox.shrink();

                  final isToday = date.year == today.year &&
                      date.month == today.month &&
                      date.day == today.day;
                  final isSelected = date.year == _selected.year &&
                      date.month == _selected.month &&
                      date.day == _selected.day;
                  final isSunday = date.weekday == 7;
                  final isSaturday = date.weekday == 6;
                  final lunar = _lunarLabel(date);
                  final isNewLunarMonth = lunar.contains('월');

                  final isDark = Theme.of(context).brightness == Brightness.dark;
                  final Color dayColor = isSelected
                      ? Colors.white
                      : isToday
                          ? widget.themeColor
                          : isSunday
                              ? Colors.red[600]!
                              : isSaturday
                                  ? Colors.blue[600]!
                                  : isDark ? Colors.grey[200]! : Colors.black87;

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
                          // 음력 날짜 (작게 — 크기 11, 대비 강화)
                          if (_showLunar && lunar.isNotEmpty)
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
              ),
            ],

            // ── 취소 버튼 ─────────────────────────────────────────────
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child:
                    Text('취소', style: TextStyle(color: Colors.grey[600])),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 연도/월 선택기 ───────────────────────────────────────────────────────────
class _YearMonthPicker extends StatefulWidget {
  final int focusedYear;
  final int focusedMonth;
  final Color themeColor;
  final void Function(int year, int month) onSelected;

  const _YearMonthPicker({
    required this.focusedYear,
    required this.focusedMonth,
    required this.themeColor,
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
    // 선택된 연도가 보이도록 스크롤 위치 초기화 (4열 기준 행 높이 ~40)
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
    final years = List.generate(_lastYear - _firstYear + 1, (i) => _firstYear + i);

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
                    '$m월',
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
