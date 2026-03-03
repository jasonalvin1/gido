import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/memo_model.dart';
import '../services/app_state.dart';
import '../utils/app_theme.dart';
import 'memo_detail_screen.dart';
import 'memo_edit_screen.dart';

enum SortOrder { newest, oldest, alphabetical }

class MemoListScreen extends StatefulWidget {
  final Category category;

  const MemoListScreen({super.key, required this.category});

  @override
  State<MemoListScreen> createState() => _MemoListScreenState();
}

class _MemoListScreenState extends State<MemoListScreen> {
  List<Memo> _memos = [];
  bool _isLoading = true;
  SortOrder _sortOrder = SortOrder.newest;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadMemos();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadMemos() async {
    setState(() => _isLoading = true);
    final memos = await context.read<AppState>().loadMemosByCategory(widget.category.id);
    if (mounted) {
      setState(() {
        _memos = memos;
        _isLoading = false;
      });
    }
  }

  List<Memo> get _sortedMemos {
    final list = List<Memo>.from(_memos);
    switch (_sortOrder) {
      case SortOrder.newest:
        list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        break;
      case SortOrder.oldest:
        list.sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
        break;
      case SortOrder.alphabetical:
        list.sort((a, b) => a.title.compareTo(b.title));
        break;
    }
    return list;
  }

  bool get _isTodoCategory => widget.category.id == 'todo';
  Color get _catColor => AppTheme.hexToColor(widget.category.color);

  void _showSortDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        return SimpleDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('정렬 방식',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              textAlign: TextAlign.center),
          children: [
            _sortOption(ctx, SortOrder.newest, '최신순', Icons.arrow_downward),
            _sortOption(ctx, SortOrder.oldest, '오래된순', Icons.arrow_upward),
            _sortOption(ctx, SortOrder.alphabetical, '가나다순', Icons.sort_by_alpha),
          ],
        );
      },
    );
  }

  Widget _sortOption(BuildContext ctx, SortOrder order, String label, IconData icon) {
    final isSelected = _sortOrder == order;
    return SimpleDialogOption(
      onPressed: () {
        setState(() => _sortOrder = order);
        Navigator.pop(ctx);
      },
      child: Row(
        children: [
          Icon(icon, size: 24, color: isSelected ? _catColor : AppTheme.textSecondary),
          const SizedBox(width: 12),
          Text(label,
              style: TextStyle(
                fontSize: 18,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? _catColor : AppTheme.textPrimary,
              )),
          const Spacer(),
          if (isSelected) Icon(Icons.check, color: _catColor, size: 22),
        ],
      ),
    );
  }

  String get _sortLabel {
    switch (_sortOrder) {
      case SortOrder.newest: return '최신순';
      case SortOrder.oldest: return '오래된순';
      case SortOrder.alphabetical: return '가나다순';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CategoryIcon(icon: widget.category.icon, size: 24),
            const SizedBox(width: 8),
            Text(widget.category.name),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, size: 28),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_memos.isNotEmpty)
            TextButton.icon(
              onPressed: _showSortDialog,
              icon: const Icon(Icons.sort, size: 20),
              label: Text(_sortLabel, style: const TextStyle(fontSize: 14)),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _memos.isEmpty
          ? _buildEmptyState()
          : _isTodoCategory
          ? _buildTodoList()
          : Scrollbar(
        controller: _scrollController,
        thumbVisibility: true,
        thickness: 6,
        radius: const Radius.circular(4),
        child: ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.all(16),
          itemCount: _sortedMemos.length,
          itemBuilder: (context, index) {
            return _buildMemoCard(_sortedMemos[index]);
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => MemoEditScreen(category: widget.category),
            ),
          );
          _loadMemos();
        },
        backgroundColor: _catColor,
        child: const Icon(Icons.add, color: Colors.white, size: 32),
      ),
    );
  }

  Widget _buildTodoList() {
    final sorted = _sortedMemos;
    final undone = sorted.where((m) => !m.isDone).toList();
    final done = sorted.where((m) => m.isDone).toList();

    return Scrollbar(
      controller: _scrollController,
      thumbVisibility: true,
      thickness: 6,
      radius: const Radius.circular(4),
      child: ListView(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      children: [
        if (undone.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8, left: 4),
            child: Text(
              '📋 할 일 (${undone.length})',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: _catColor,
              ),
            ),
          ),
          ...undone.map((m) => _buildMemoCard(m)),
        ],
        if (done.isNotEmpty) ...[
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.only(bottom: 8, left: 4),
            child: Text(
              '✅ 완료 (${done.length})',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
          ...done.map((m) => _buildMemoCard(m)),
        ],
      ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CategoryIcon(icon: widget.category.icon, size: 64),
          const SizedBox(height: 16),
          const Text(
            '아직 메모가 없어요',
            style: TextStyle(
              fontSize: AppTheme.fontSizeMedium,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '아래 + 버튼을 눌러 추가하세요',
            style: TextStyle(
              fontSize: 17,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMemoCard(Memo memo) {
    return GestureDetector(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MemoDetailScreen(memo: memo, category: widget.category),
          ),
        );
        _loadMemos();
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border(
            left: BorderSide(color: _catColor, width: 5),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          children: [
            if (_isTodoCategory) ...[
              GestureDetector(
                onTap: () async {
                  await context.read<AppState>().toggleDone(memo);
                  _loadMemos();
                },
                child: Container(
                  width: 36,
                  height: 36,
                  margin: const EdgeInsets.only(right: 16),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: memo.isDone ? _catColor : Colors.transparent,
                    border: Border.all(
                      color: memo.isDone ? _catColor : const Color(0xFFCCCCCC),
                      width: 3,
                    ),
                  ),
                  child: memo.isDone
                      ? const Icon(Icons.check, color: Colors.white, size: 22)
                      : null,
                ),
              ),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    memo.title,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: memo.isDone
                          ? AppTheme.textSecondary
                          : AppTheme.textPrimary,
                      decoration: memo.isDone ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _getPreviewText(memo),
                    style: const TextStyle(
                      fontSize: 17,
                      color: AppTheme.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatDate(memo.createdAt),
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFFBBBBBB),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Color(0xFFCCCCCC), size: 28),
          ],
        ),
      ),
    );
  }

  String _getPreviewText(Memo memo) {
    final previews = memo.data.entries
        .where((e) => e.value.isNotEmpty && !Category.sensitiveFields.contains(e.key))
        .take(2)
        .map((e) => '${e.key}: ${e.value}')
        .toList();
    return previews.join(' · ');
  }

  /// 생성일 표시: 오늘/어제/N일 전/날짜
  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) return '오늘';
    if (diff.inDays == 1) return '어제';
    if (diff.inDays < 7) return '${diff.inDays}일 전';
    return DateFormat('yyyy.MM.dd').format(dt);
  }
}