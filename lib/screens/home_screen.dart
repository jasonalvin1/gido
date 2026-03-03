import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/memo_model.dart';
import '../services/app_state.dart';
import '../services/backup_service.dart';
import '../utils/app_theme.dart';
import '../main.dart';
import 'memo_list_screen.dart';
import 'memo_detail_screen.dart';
import 'add_category_screen.dart';
import 'lock_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  DateTime? _pausedAt;
  final BackupService _backupService = BackupService();

  // 검색
  final TextEditingController _searchController = TextEditingController();
  List<Memo> _searchResults = [];
  bool _isSearching = false;
  bool _hasSearched = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppState>().loadData();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _pausedAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed && _pausedAt != null) {
      final diff = DateTime.now().difference(_pausedAt!);
      if (diff.inMinutes >= 5) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LockScreen()),
              (route) => false,
        );
      }
      _pausedAt = null;
    }
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _hasSearched = false;
        _isSearching = false;
      });
      return;
    }
    setState(() => _isSearching = true);
    final results = await context.read<AppState>().searchMemos(query);
    if (mounted) {
      setState(() {
        _searchResults = results;
        _hasSearched = true;
        _isSearching = false;
      });
    }
  }

  /// 데이터 로딩 중 표시할 애니메이션 뷰
  Widget _buildLoadingView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 앱 아이콘 펄스 애니메이션
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.85, end: 1.0),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeInOut,
            builder: (context, scale, child) => Transform.scale(
              scale: scale,
              child: child,
            ),
            child: Image.asset('assets/icons/prayer.png', width: 72, height: 72),
            onEnd: () => setState(() {}), // 반복 트리거
          ),
          const SizedBox(height: 24),
          const Text(
            '기억을 불러오는 중...',
            style: TextStyle(fontSize: 18, color: Color(0xFF888888)),
          ),
          const SizedBox(height: 20),
          const SizedBox(
            width: 120,
            child: LinearProgressIndicator(
              borderRadius: BorderRadius.all(Radius.circular(8)),
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _highlightText(String text, String query, TextStyle baseStyle) {
    if (query.isEmpty) return Text(text, style: baseStyle);
    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final spans = <TextSpan>[];
    int start = 0;
    while (true) {
      final index = lowerText.indexOf(lowerQuery, start);
      if (index == -1) {
        spans.add(TextSpan(text: text.substring(start), style: baseStyle));
        break;
      }
      if (index > start) {
        spans.add(TextSpan(text: text.substring(start, index), style: baseStyle));
      }
      spans.add(TextSpan(
        text: text.substring(index, index + query.length),
        style: baseStyle.copyWith(
          color: Colors.orange,
          fontWeight: FontWeight.w800,
          backgroundColor: Colors.orange.withAlpha(30),
        ),
      ));
      start = index + query.length;
    }
    return RichText(text: TextSpan(children: spans));
  }

  // 백업
  Future<void> _handleBackup(BuildContext context) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('백업 파일 생성 중...', style: TextStyle(fontSize: 16))),
    );
    final success = await _backupService.createBackup(context);
    if (!mounted) return;
    if (success) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('💾 백업 완료!',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              textAlign: TextAlign.center),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('백업 파일을 안전하게 보관하세요.',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              SizedBox(height: 16),
              Text('📌 저장 방법 2가지',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              SizedBox(height: 10),
              Text('1️⃣ 카카오톡 저장',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              Text('공유시트에서 카카오톡 선택\n→ 나와의 채팅으로 전송',
                  style: TextStyle(fontSize: 14, height: 1.5)),
              SizedBox(height: 10),
              Text('2️⃣ 구글 드라이브 저장',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              Text('공유시트에서 드라이브 선택\n→ 내 드라이브에 저장',
                  style: TextStyle(fontSize: 14, height: 1.5)),
              SizedBox(height: 16),
              Text('💡 복원 방법',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              Text('저장한 파일을 내 파일앱에 저장 후\n메뉴 > 복원에서 파일 선택',
                  style: TextStyle(fontSize: 14, height: 1.5)),
            ],
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('확인',
                  style: TextStyle(fontSize: 18, color: AppTheme.primaryColor)),
            ),
          ],
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('백업 실패. 다시 시도해주세요', style: TextStyle(fontSize: 16))),
      );
    }
  }

  // 복원
  Future<void> _handleRestore(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('📂 백업 복원',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            textAlign: TextAlign.center),
        content: const Text(
          '복원하면 기존 데이터에 백업 데이터가 추가돼요.\n계속하시겠어요?',
          style: TextStyle(fontSize: 16),
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFFE0E0E0), width: 2),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: const Text('취소', style: TextStyle(fontSize: 16, color: AppTheme.textSecondary)),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: const Text('계속', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    if (!mounted) return;
    final success = await _backupService.restoreBackup(context);
    if (!mounted) return;
    if (success) {
      await context.read<AppState>().loadData();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('복원 완료! ✅', style: TextStyle(fontSize: 16)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('복원 실패. 백업 파일을 확인해주세요', style: TextStyle(fontSize: 16)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // 도움말
  void _showHelpDialog(BuildContext context, bool isDark) {
    final helps = [
      {'icon': '🔐', 'title': '잠금 해제', 'desc': '지문 또는 PIN으로 앱을 열어요'},
      {'icon': '📁', 'title': '카테고리', 'desc': '길게 누르면 수정/순서변경/삭제'},
      {'icon': '📝', 'title': '메모 추가', 'desc': '카테고리 들어가서 + 버튼'},
      {'icon': '🔍', 'title': '검색', 'desc': '상단 검색창에서 바로 실시간 검색'},
      {'icon': '✏️', 'title': '직접입력', 'desc': '카테고리 추가 시 이모지 자유 설정'},
      {'icon': '🔃', 'title': '순서 변경', 'desc': '카테고리 ⋮ 메뉴에서 위/아래 이동'},
      {'icon': '💾', 'title': '백업', 'desc': '메뉴 > 백업 → 카카오톡/구글드라이브에 저장'},
      {'icon': '📂', 'title': '복원', 'desc': '저장한 파일을 내 파일앱에 저장 후 메뉴 > 복원'},
      {'icon': '🌙', 'title': '다크모드', 'desc': '메뉴에서 테마 전환'},
    ];
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('❓ 도움말',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              textAlign: TextAlign.center),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: helps.length,
              separatorBuilder: (_, __) => Divider(
                color: isDark ? const Color(0xFF333333) : const Color(0xFFEEEEEE),
                height: 1,
              ),
              itemBuilder: (_, index) {
                final item = helps[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      Text(item['icon']!, style: const TextStyle(fontSize: 24)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item['title']!,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary,
                                )),
                            Text(item['desc']!,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary,
                                )),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('닫기',
                  style: TextStyle(fontSize: 18, color: AppTheme.primaryColor)),
            ),
          ],
        );
      },
    );
  }

  // 버전 정보
  void _showVersionDialog(BuildContext context, bool isDark) {
    final orange = AppTheme.hexToColor('#FF6B35');
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset('assets/icons/prayer.png', width: 64, height: 64),
              const SizedBox(height: 12),
              RichText(
                text: TextSpan(
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
                  children: [
                    TextSpan(text: '기', style: TextStyle(color: orange)),
                    TextSpan(text: '억 ', style: TextStyle(color: isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary)),
                    TextSpan(text: '도', style: TextStyle(color: orange)),
                    TextSpan(text: '우미', style: TextStyle(color: isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.darkSurface : const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    _versionRow('버전', '1.0.0', isDark),
                    const SizedBox(height: 6),
                    _versionRow('개발사', 'JSK (Jason Soft Korea)', isDark),
                    const SizedBox(height: 6),
                    _versionRow('문의', 'jsk.apps.dev@gmail.com', isDark),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '중요한 기억을 안전하게 정리하는\n기억 도우미',
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary,
                  height: 1.6,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('닫기', style: TextStyle(fontSize: 18, color: orange)),
            ),
          ],
        );
      },
    );
  }

  Widget _versionRow(String label, String value, bool isDark) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: TextStyle(fontSize: 14,
                color: isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary)),
        Flexible(
          child: Text(value,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                  color: isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary),
              textAlign: TextAlign.right),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final maxContentWidth = screenWidth > 600 ? 720.0 : double.infinity;
    final isDark = context.watch<ThemeNotifier>().isDark;
    final orange = AppTheme.hexToColor('#FF6B35');
    final query = _searchController.text.trim();

    return Scaffold(
      appBar: AppBar(
        title: RichText(
          text: TextSpan(
            style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
            children: [
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Image.asset('assets/icons/prayer.png', width: 46, height: 46),
                ),
              ),
              TextSpan(text: '기', style: TextStyle(color: orange, fontWeight: FontWeight.w900)),
              TextSpan(text: '억 ', style: TextStyle(color: isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary)),
              TextSpan(text: '도', style: TextStyle(color: orange, fontWeight: FontWeight.w900)),
              TextSpan(text: '우미', style: TextStyle(color: isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary)),
            ],
          ),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 28),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            onSelected: (value) async {
              switch (value) {
                case 'theme':
                  context.read<ThemeNotifier>().toggle();
                  break;
                case 'backup':
                  await _handleBackup(context);
                  break;
                case 'restore':
                  await _handleRestore(context);
                  break;
                case 'help':
                  _showHelpDialog(context, isDark);
                  break;
                case 'info':
                  _showVersionDialog(context, isDark);
                  break;
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'theme',
                child: Row(children: [
                  Text(isDark ? '☀️' : '🌙', style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: 12),
                  Text(isDark ? '라이트 모드' : '다크 모드', style: const TextStyle(fontSize: 16)),
                ]),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'backup',
                child: Row(children: [
                  Text('💾', style: TextStyle(fontSize: 20)),
                  SizedBox(width: 12),
                  Text('백업', style: TextStyle(fontSize: 16)),
                ]),
              ),
              const PopupMenuItem(
                value: 'restore',
                child: Row(children: [
                  Text('📂', style: TextStyle(fontSize: 20)),
                  SizedBox(width: 12),
                  Text('복원', style: TextStyle(fontSize: 16)),
                ]),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'help',
                child: Row(children: [
                  Text('❓', style: TextStyle(fontSize: 20)),
                  SizedBox(width: 12),
                  Text('도움말', style: TextStyle(fontSize: 16)),
                ]),
              ),
              const PopupMenuItem(
                value: 'info',
                child: Row(children: [
                  Text('ℹ️', style: TextStyle(fontSize: 20)),
                  SizedBox(width: 12),
                  Text('앱 정보', style: TextStyle(fontSize: 16)),
                ]),
              ),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: Consumer<AppState>(
          builder: (context, appState, child) {
            if (appState.isLoading) {
              return _buildLoadingView();
            }
            return Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxContentWidth),
                child: Column(
                  children: [
                    // 검색바
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: isDark
                                ? [const Color(0xFF2A2A2A), const Color(0xFF333333)]
                                : [const Color(0xFFFFF8F5), const Color(0xFFFFEFE8)],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: orange.withAlpha(isDark ? 80 : 60),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: orange.withAlpha(isDark ? 20 : 15),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: orange.withAlpha(isDark ? 40 : 25),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Center(
                                child: Image.asset('assets/icons/magnifier.png', width: 28, height: 28),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller: _searchController,
                                style: TextStyle(
                                  fontSize: 15,
                                  color: isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary,
                                ),
                                decoration: InputDecoration(
                                  hintText: '찾고 싶은 내용을 입력하세요',
                                  hintStyle: TextStyle(
                                    fontSize: 15,
                                    color: isDark ? AppTheme.darkTextSecondary : const Color(0xFF999999),
                                  ),
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                ),
                                onChanged: _search,
                              ),
                            ),
                            if (_isSearching)
                              const SizedBox(
                                width: 20, height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            else if (_searchController.text.isNotEmpty)
                              GestureDetector(
                                onTap: () {
                                  _searchController.clear();
                                  _search('');
                                },
                                child: Icon(Icons.close, size: 20,
                                    color: isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary),
                              ),
                          ],
                        ),
                      ),
                    ),

                    // 검색 결과 개수
                    if (_hasSearched)
                      Padding(
                        padding: const EdgeInsets.only(left: 20, bottom: 6),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            _searchResults.isEmpty
                                ? '검색 결과가 없어요'
                                : '검색 결과 ${_searchResults.length}개',
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),

                    // 본문 - 검색중이면 결과, 아니면 카테고리 목록
                    Expanded(
                      child: _hasSearched
                          ? _buildSearchResults(query, isDark, appState)
                          : _buildCategoryList(appState, isDark, orange),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // 검색 결과
  Widget _buildSearchResults(String query, bool isDark, AppState appState) {
    if (_searchResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('😅', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 16),
            Text(
              '"$query" 검색 결과가 없어요',
              style: TextStyle(
                fontSize: AppTheme.fontSizeMedium,
                color: isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        return _buildResultCard(_searchResults[index], query, isDark, appState);
      },
    );
  }

  Widget _buildResultCard(Memo memo, String query, bool isDark, AppState appState) {
    final cat = appState.getCategoryById(memo.categoryId);
    final color = cat != null ? AppTheme.hexToColor(cat.color) : Colors.grey;
    final previewText = memo.data.entries
        .where((e) => e.value.isNotEmpty && !Category.sensitiveFields.contains(e.key))
        .take(2)
        .map((e) => '${e.key}: ${e.value}')
        .join(' · ');

    return GestureDetector(
      onTap: () {
        if (cat != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => MemoDetailScreen(memo: memo, category: cat),
            ),
          );
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkCard : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border(left: BorderSide(color: color, width: 5)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(10),
              blurRadius: 8,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (cat != null)
              Row(
                children: [
                  CategoryIcon(icon: cat.icon, size: 14),
                  const SizedBox(width: 4),
                  Text(cat.name,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: color)),
                ],
              ),
            const SizedBox(height: 4),
            _highlightText(
              memo.title,
              query,
              TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary,
              ),
            ),
            if (previewText.isNotEmpty) ...[
              const SizedBox(height: 4),
              _highlightText(
                previewText,
                query,
                TextStyle(
                  fontSize: 17,
                  color: isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // 카테고리 목록
  Widget _buildCategoryList(AppState appState, bool isDark, Color orange) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        children: [
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: appState.categories.length + 1,
            itemBuilder: (context, index) {
              if (index == appState.categories.length) {
                return _buildAddCategoryCard(context, isDark, orange);
              }
              final cat = appState.categories[index];
              final count = appState.memoCounts[cat.id] ?? 0;
              final isFirst = index == 0;
              final isLast = index == appState.categories.length - 1;
              return _buildCategoryCard(context, cat, count, isDark, isFirst, isLast);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryCard(BuildContext context, Category cat, int count, bool isDark, bool isFirst, bool isLast) {
    final color = AppTheme.hexToColor(cat.color);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: () async {
          await Navigator.push(context,
              MaterialPageRoute(builder: (_) => MemoListScreen(category: cat)));
          if (mounted) context.read<AppState>().loadData();
        },
        onLongPress: () => _showCategoryOptionsDialog(context, cat, count, isFirst, isLast),
        child: Container(
          height: 88,
          decoration: BoxDecoration(
            color: isDark ? AppTheme.darkCard : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color.withAlpha(isDark ? 80 : 50), width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(isDark ? 30 : 10),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: color.withAlpha(isDark ? 40 : 20),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    bottomLeft: Radius.circular(16),
                  ),
                ),
                child: Center(
                  child: CategoryIcon(icon: cat.icon, size: 64),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cat.name,
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: color),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '$count개 메모',
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () => _showCategoryOptionsDialog(context, cat, count, isFirst, isLast),
                child: Container(
                  width: 40,
                  height: 72,
                  decoration: const BoxDecoration(
                    borderRadius: BorderRadius.only(
                      topRight: Radius.circular(16),
                      bottomRight: Radius.circular(16),
                    ),
                  ),
                  child: Icon(Icons.more_vert, size: 20,
                      color: isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCategoryOptionsDialog(BuildContext context, Category cat, int count, bool isFirst, bool isLast) {
    final color = AppTheme.hexToColor(cat.color);
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CategoryIcon(icon: cat.icon, size: 24),
                const SizedBox(width: 8),
                Text(cat.name,
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
              ],
            ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: OutlinedButton.icon(
                        onPressed: isFirst ? null : () async {
                          Navigator.pop(ctx);
                          await context.read<AppState>().reorderCategory(cat.id, true);
                        },
                        icon: const Icon(Icons.arrow_upward, size: 20),
                        label: const Text('위로', style: TextStyle(fontSize: 16)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: isFirst ? Colors.grey : color,
                          side: BorderSide(color: isFirst ? Colors.grey.shade300 : color, width: 2),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: OutlinedButton.icon(
                        onPressed: isLast ? null : () async {
                          Navigator.pop(ctx);
                          await context.read<AppState>().reorderCategory(cat.id, false);
                        },
                        icon: const Icon(Icons.arrow_downward, size: 20),
                        label: const Text('아래로', style: TextStyle(fontSize: 16)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: isLast ? Colors.grey : color,
                          side: BorderSide(color: isLast ? Colors.grey.shade300 : color, width: 2),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _showRenameCategoryDialog(context, cat);
                  },
                  icon: const Icon(Icons.edit, size: 22),
                  label: const Text('이름 수정', style: TextStyle(fontSize: 18)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: color,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _showDeleteCategoryDialog(context, cat, count);
                  },
                  icon: const Icon(Icons.delete_outline, size: 22, color: Color(0xFFD32F2F)),
                  label: const Text('삭제하기',
                      style: TextStyle(fontSize: 18, color: Color(0xFFD32F2F))),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFD32F2F), width: 2),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('닫기',
                  style: TextStyle(fontSize: 18, color: AppTheme.textSecondary)),
            ),
          ],
        );
      },
    );
  }

  void _showRenameCategoryDialog(BuildContext context, Category cat) {
    final controller = TextEditingController(text: cat.name);
    final color = AppTheme.hexToColor(cat.color);
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CategoryIcon(icon: cat.icon, size: 24),
                const SizedBox(width: 8),
                const Text('이름 수정',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
              ],
            ),
          content: TextField(
            controller: controller,
            autofocus: true,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              hintText: '새 이름을 입력하세요',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: color, width: 2),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: color, width: 2),
              ),
            ),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            SizedBox(
              height: 52,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(ctx),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFE0E0E0), width: 2),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                ),
                child: const Text('취소',
                    style: TextStyle(fontSize: 18, color: AppTheme.textSecondary)),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: () async {
                  final newName = controller.text.trim();
                  if (newName.isEmpty) return;
                  final updated = Category(
                    id: cat.id,
                    name: newName,
                    icon: cat.icon,
                    color: cat.color,
                    fields: cat.fields,
                    isDefault: cat.isDefault,
                    sortOrder: cat.sortOrder,
                  );
                  await context.read<AppState>().updateCategory(updated);
                  if (mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('"$newName"(으)로 변경했어요! ✅',
                            style: const TextStyle(fontSize: 18)),
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: color,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                ),
                child: const Text('저장',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showDeleteCategoryDialog(BuildContext context, Category cat, int count) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CategoryIcon(icon: cat.icon, size: 24),
            const SizedBox(width: 8),
            Text(cat.name,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Text(
              '이 카테고리를 삭제할까요?',
              style: TextStyle(fontSize: 20),
              textAlign: TextAlign.center,
            ),
            if (count > 0) ...[
              const SizedBox(height: 14),
              const Text(
                '카테고리 내의 모든 메모가 사라집니다.',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFD32F2F),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFFE0E0E0), width: 2),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
            ),
            child: const Text('아니요',
                style: TextStyle(fontSize: 18, color: AppTheme.textSecondary)),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await context.read<AppState>().deleteCategory(cat.id);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('"${cat.name}" 삭제했어요',
                      style: const TextStyle(fontSize: 18)),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ));
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD32F2F),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
            ),
            child: const Text('삭제',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _buildAddCategoryCard(BuildContext context, bool isDark, Color orange) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: () async {
          await Navigator.push(context,
              MaterialPageRoute(builder: (_) => const AddCategoryScreen()));
          if (mounted) context.read<AppState>().loadData();
        },
        child: Container(
          height: 72,
          decoration: BoxDecoration(
            color: isDark ? orange.withAlpha(15) : orange.withAlpha(10),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: orange.withAlpha(isDark ? 100 : 80),
              width: 2,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: orange.withAlpha(isDark ? 60 : 40),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(child: Icon(Icons.add, size: 20, color: orange)),
              ),
              const SizedBox(width: 10),
              Text(
                '새 카테고리 만들기',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: orange.withAlpha(isDark ? 200 : 180),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}