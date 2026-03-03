import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/memo_model.dart';
import '../services/app_state.dart';
import '../utils/app_theme.dart';
import 'memo_edit_screen.dart';

class MemoDetailScreen extends StatefulWidget {
  final Memo memo;
  final Category category;

  const MemoDetailScreen({super.key, required this.memo, required this.category});

  @override
  State<MemoDetailScreen> createState() => _MemoDetailScreenState();
}

class _MemoDetailScreenState extends State<MemoDetailScreen> {
  late Memo _memo;
  final Map<String, bool> _showPassword = {};

  // 전화번호 필드인지 확인
  bool _isPhoneField(String fieldName) {
    return fieldName.contains('전화') || fieldName.contains('연락처') || fieldName.contains('핸드폰');
  }

  // 전화 걸기
  Future<void> _makeCall(String number) async {
    final cleaned = number.replaceAll(RegExp(r'[^0-9+]'), '');
    final uri = Uri.parse('tel:$cleaned');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  void initState() {
    super.initState();
    _memo = widget.memo;
  }

  Color get _catColor => AppTheme.hexToColor(widget.category.color);

  void _showDeleteDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        contentPadding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🗑️', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 12),
            const Text(
              '정말 지울까요?',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              '"${_memo.title}" 메모를 삭제합니다',
              style: const TextStyle(fontSize: 18, color: AppTheme.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              '아니요, 취소',
              style: TextStyle(fontSize: AppTheme.fontSizeMedium),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              await context.read<AppState>().deleteMemo(_memo);
              if (mounted) {
                // ScaffoldMessenger를 Navigator.pop 전에 미리 캡처
                final messenger = ScaffoldMessenger.of(context);
                Navigator.pop(ctx); // close dialog
                Navigator.pop(context); // back to list
                messenger.showSnackBar(
                  SnackBar(
                    content: const Text('삭제했어요 🗑️', style: TextStyle(fontSize: 18)),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.dangerColor,
              foregroundColor: Colors.white,
            ),
            child: const Text(
              '네, 삭제할게요',
              style: TextStyle(fontSize: AppTheme.fontSizeMedium),
            ),
          ),
        ],
      ),
    );
  }

  /// 카테고리 이동 다이얼로그
  void _showMoveDialog() {
    final appState = context.read<AppState>();
    final categories = appState.categories
        .where((c) => c.id != widget.category.id)
        .toList();

    if (categories.isEmpty) {
      _showSnackbar('이동할 수 있는 카테고리가 없어요');
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text(
          '어디로 이동할까요?',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          textAlign: TextAlign.center,
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: categories.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, index) {
              final cat = categories[index];
              return ListTile(
                leading: CategoryIcon(icon: cat.icon, size: 32),
                title: Text(
                  cat.name,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmMove(cat);
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소', style: TextStyle(fontSize: AppTheme.fontSizeMedium)),
          ),
        ],
      ),
    );
  }

  /// 이동 확인 및 필드 매핑 적용
  void _confirmMove(Category targetCategory) {
    final newData = _mapFields(widget.category, targetCategory, _memo);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        contentPadding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('📦', style: TextStyle(fontSize: 40)),
            const SizedBox(height: 12),
            Text(
              '"${_memo.title}"',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CategoryIcon(icon: widget.category.icon, size: 20),
                const SizedBox(width: 6),
                Text(widget.category.name,
                    style: const TextStyle(fontSize: 16, color: AppTheme.textSecondary)),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.arrow_forward, size: 18, color: AppTheme.textSecondary),
                ),
                CategoryIcon(icon: targetCategory.icon, size: 20),
                const SizedBox(width: 6),
                Text(targetCategory.name,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '이동하면 필드가 자동으로 매핑돼요',
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소', style: TextStyle(fontSize: AppTheme.fontSizeMedium)),
          ),
          ElevatedButton(
            onPressed: () async {
              await context.read<AppState>().moveMemo(_memo, targetCategory.id, newData);
              if (mounted) {
                Navigator.pop(ctx);
                Navigator.pop(context);
                _showSnackbar('${targetCategory.name}으로 이동했어요! ✅');
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.hexToColor(targetCategory.color),
              foregroundColor: Colors.white,
            ),
            child: const Text('이동', style: TextStyle(fontSize: AppTheme.fontSizeMedium)),
          ),
        ],
      ),
    );
  }

  /// 필드 매핑 로직:
  /// - 다중→단일: 비민감 필드 값 합치기
  /// - 단일→다중 또는 다중→다중: 이름 매칭 우선, 나머지는 순서대로 배정
  Map<String, String> _mapFields(Category source, Category target, Memo memo) {
    final newData = <String, String>{};

    if (target.fields.length == 1) {
      // 단일 필드로 이동: 모든 비민감 필드 내용을 하나로 합침
      final merged = source.fields
          .where((f) => (memo.data[f] ?? '').isNotEmpty && !Category.sensitiveFields.contains(f))
          .map((f) => '${f}: ${memo.data[f]}')
          .join('\n');
      newData[target.fields.first] = merged.isNotEmpty ? merged : memo.title;
    } else {
      // 이름 매칭 우선
      final unmatchedValues = <String>[];
      for (final sf in source.fields) {
        final value = memo.data[sf] ?? '';
        if (value.isEmpty) continue;
        if (target.fields.contains(sf)) {
          newData[sf] = value;
        } else {
          unmatchedValues.add(value);
        }
      }
      // 남은 값은 비어있는 타겟 필드에 순서대로 배정
      final emptyFields = target.fields.where((f) => !newData.containsKey(f)).toList();
      for (int i = 0; i < unmatchedValues.length && i < emptyFields.length; i++) {
        newData[emptyFields[i]] = unmatchedValues[i];
      }
      // 타겟 필드 중 누락된 것은 빈 문자열로 초기화
      for (final f in target.fields) {
        newData.putIfAbsent(f, () => '');
      }
    }
    return newData;
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
        title: Text(
          _memo.title,
          style: const TextStyle(fontSize: 22),
          overflow: TextOverflow.ellipsis,
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, size: 28),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.drive_file_move_outline, size: 26),
            tooltip: '카테고리 이동',
            onPressed: _showMoveDialog,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 28),
            onPressed: _showDeleteDialog,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // 각 필드 표시
            ...widget.category.fields.map((field) {
              final value = _memo.data[field];
              if (value == null || value.isEmpty) return const SizedBox.shrink();

              final isSensitive = widget.category.isSensitiveField(field);
              final isVisible = _showPassword[field] == true;

              return Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.03),
                      blurRadius: 6,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 필드 라벨
                    Text(
                      field,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),

                    // 필드 값 + 버튼
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            isSensitive && !isVisible
                                ? '●' * value.length
                                : value,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ),

                        // 비밀번호 보기/숨기기 버튼
                        if (isSensitive)
                          IconButton(
                            onPressed: () {
                              setState(() {
                                _showPassword[field] = !isVisible;
                              });
                              // 3초 후 자동 숨기기
                              if (!isVisible) {
                                Future.delayed(const Duration(seconds: 3), () {
                                  if (mounted) {
                                    setState(() {
                                      _showPassword[field] = false;
                                    });
                                  }
                                });
                              }
                            },
                            icon: Text(
                              isVisible ? '🙈' : '👁️',
                              style: const TextStyle(fontSize: 22),
                            ),
                            iconSize: 32,
                          ),

                        // 복사 버튼
                        TextButton.icon(
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: value));
                            _showSnackbar('복사했어요! 📋');
                          },
                          icon: const Icon(Icons.copy, size: 20),
                          label: const Text(
                            '복사',
                            style: TextStyle(fontSize: 16),
                          ),
                          style: TextButton.styleFrom(
                            backgroundColor: const Color(0xFFF0F0F0),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                        ),

                        // 전화 걸기 버튼 (전화번호 필드일 때만)
                        if (_isPhoneField(field)) ...[
                          const SizedBox(width: 8),
                          TextButton.icon(
                            onPressed: () => _makeCall(value),
                            icon: const Icon(Icons.phone, size: 20, color: Colors.white),
                            label: const Text(
                              '전화',
                              style: TextStyle(fontSize: 16, color: Colors.white),
                            ),
                            style: TextButton.styleFrom(
                              backgroundColor: const Color(0xFF4CAF50),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              );
            }),

            const SizedBox(height: 16),

            // 수정 버튼
            SizedBox(
              width: double.infinity,
              height: AppTheme.minTouchTarget,
              child: ElevatedButton.icon(
                onPressed: () async {
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MemoEditScreen(
                        category: widget.category,
                        memo: _memo,
                      ),
                    ),
                  );
                  if (result is Memo && mounted) {
                    setState(() {
                      _memo = result;
                    });
                  }
                },
                icon: const Text('✏️', style: TextStyle(fontSize: 22)),
                label: const Text('수정하기'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _catColor,
                  foregroundColor: Colors.white,
                ),
              ),
            ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
