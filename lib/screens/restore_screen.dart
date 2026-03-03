import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import '../services/backup_service.dart';
import '../services/database_service.dart';
import '../utils/app_theme.dart';

/// 백업 파일 복원 화면
///
/// 진입 경로:
///   1. 카카오톡에서 .gido 파일 탭 → 자동으로 열림 (initialFilePath 제공)
///   2. 홈 화면 "복원" 버튼 탭 → 수동으로 파일 선택
class RestoreScreen extends StatefulWidget {
  /// 카카오톡 등 외부에서 받아온 파일 경로 (없으면 null)
  final String? initialFilePath;

  const RestoreScreen({super.key, this.initialFilePath});

  @override
  State<RestoreScreen> createState() => _RestoreScreenState();
}

class _RestoreScreenState extends State<RestoreScreen> {
  final _backupService = BackupService(DatabaseService());

  BackupInfo? _selectedBackup;   // 현재 선택된 파일
  List<BackupInfo> _foundFiles = []; // 자동 검색 결과
  bool _isSearching = false;
  bool _isRestoring = false;
  String _statusMessage = '';

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    // 1) 외부(카카오톡)에서 파일 경로가 넘어온 경우
    if (widget.initialFilePath != null) {
      final info = await _backupService.getBackupInfo(widget.initialFilePath!);
      if (mounted) {
        setState(() => _selectedBackup = info);
        if (info == null) {
          _showError('올바른 백업 파일이 아닙니다.\n(.gido 파일만 복원할 수 있어요)');
        }
      }
    }

    // 2) 다운로드 폴더 자동 검색 (Android 12 이하에서 권한 있을 때만 동작)
    _searchDownloads();
  }

  Future<void> _searchDownloads() async {
    if (!mounted) return;
    setState(() => _isSearching = true);

    final files = await _backupService.findGidoFiles();

    if (!mounted) return;
    setState(() {
      _foundFiles = files;
      _isSearching = false;
    });
  }

  // ─────────────────────────────────────────────
  //  파일 직접 선택
  // ─────────────────────────────────────────────
  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,   // .gido는 커스텀 확장자라 any로 받아야 합니다
        dialogTitle: '백업 파일(.gido) 선택',
        allowMultiple: false,
      );

      if (result == null || result.files.single.path == null) return;

      final path = result.files.single.path!;

      // 확장자 체크
      if (!path.toLowerCase().endsWith('.gido')) {
        _showError('.gido 파일만 복원할 수 있어요.\n선택한 파일: ${path.split('/').last}');
        return;
      }

      final info = await _backupService.getBackupInfo(path);
      if (!mounted) return;

      if (info == null) {
        _showError('올바른 백업 파일이 아닙니다.');
        return;
      }

      setState(() => _selectedBackup = info);
    } catch (e) {
      if (!mounted) return;
      _showError('파일 선택 중 오류가 발생했어요.\n$e');
    }
  }

  // ─────────────────────────────────────────────
  //  복원 실행
  // ─────────────────────────────────────────────
  Future<void> _startRestore(BackupInfo backup) async {
    final confirmed = await _showConfirmDialog(backup);
    if (!confirmed || !mounted) return;

    setState(() {
      _isRestoring = true;
      _statusMessage = '복원 중입니다...\n잠시만 기다려주세요';
    });

    try {
      await _backupService.importBackup(backup.filePath, merge: false);

      if (mounted) await context.read<AppState>().loadData();
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ 복원이 완료됐어요!'),
          backgroundColor: Color(0xFF4CAF50),
          duration: Duration(seconds: 3),
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isRestoring = false;
        _statusMessage = '';
      });
      _showError('복원 중 오류가 발생했어요.\n$e');
    }
  }

  // ─────────────────────────────────────────────
  //  다이얼로그
  // ─────────────────────────────────────────────
  Future<bool> _showConfirmDialog(BackupInfo backup) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20)),
            title: const Text('복원하시겠어요?',
                style: TextStyle(fontWeight: FontWeight.w800)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _infoRow('📦', '카테고리', '${backup.categoryCount}개'),
                const SizedBox(height: 6),
                _infoRow('📝', '메모', '${backup.memoCount}개'),
                const SizedBox(height: 6),
                _infoRow('🕐', '백업 날짜', backup.dateStr),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFEBEE),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('⚠️', style: TextStyle(fontSize: 18)),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '현재 저장된 데이터가\n모두 백업 파일로 교체됩니다.',
                          style: TextStyle(
                            fontSize: 15,
                            color: Color(0xFFD32F2F),
                            fontWeight: FontWeight.w700,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              OutlinedButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('취소'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('복원하기'),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _showError(String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('⚠️ 확인 필요'),
        content:
            Text(message, style: const TextStyle(height: 1.5, fontSize: 16)),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String emoji, String label, String value) {
    return Row(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 16)),
        const SizedBox(width: 6),
        Text('$label: ',
            style: const TextStyle(color: AppTheme.textSecondary,
                fontSize: 15)),
        Expanded(
          child: Text(value,
              style: const TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 15)),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────
  //  UI
  // ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('백업 파일 복원',
            style: TextStyle(fontWeight: FontWeight.w800)),
        backgroundColor: Colors.white,
        foregroundColor: AppTheme.primaryColor,
        elevation: 0,
        surfaceTintColor: Colors.white,
      ),
      body: _isRestoring ? _buildRestoringView() : _buildBody(),
    );
  }

  Widget _buildRestoringView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(
                color: AppTheme.primaryColor, strokeWidth: 4),
            const SizedBox(height: 28),
            Text(
              _statusMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary,
                height: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [

          // ══════════════════════════════════════
          //  카카오톡에서 받은 파일 (자동 인식)
          // ══════════════════════════════════════
          if (_selectedBackup != null) ...[
            _sectionHeader('📲', '받은 백업 파일'),
            const SizedBox(height: 12),
            _buildBackupCard(_selectedBackup!, highlight: true),
            const SizedBox(height: 32),
          ],

          // ══════════════════════════════════════
          //  직접 파일 선택 버튼 (가장 중요!)
          // ══════════════════════════════════════
          _sectionHeader('📁', '파일 선택으로 복원'),
          const SizedBox(height: 12),

          // 안내 박스
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F4FF),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: AppTheme.primaryColor.withOpacity(0.2), width: 1.5),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '💡 카카오톡에서 백업 파일을 받으셨나요?',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: AppTheme.primaryColor),
                ),
                SizedBox(height: 6),
                Text(
                  '카카오톡 → 파일 꾹 누르기 → "내 파일에 저장"\n'
                  '→ 아래 버튼을 눌러 저장된 파일을 선택하세요.',
                  style: TextStyle(
                      fontSize: 14,
                      color: AppTheme.textSecondary,
                      height: 1.5),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // 파일 선택 버튼 (크고 눈에 띄게)
          ElevatedButton(
            onPressed: _pickFile,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 20),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18)),
              elevation: 2,
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('📂', style: TextStyle(fontSize: 26)),
                SizedBox(width: 10),
                Text(
                  '백업 파일 선택하기',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // ══════════════════════════════════════
          //  자동 검색 결과 (Android 11 이하 기기에서만 표시)
          // ══════════════════════════════════════
          _sectionHeader('🔍', '자동으로 찾은 파일'),
          const SizedBox(height: 12),

          if (_isSearching)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(color: AppTheme.primaryColor),
                    SizedBox(height: 10),
                    Text('다운로드 폴더 검색 중...',
                        style:
                            TextStyle(color: AppTheme.textSecondary)),
                  ],
                ),
              ),
            )
          else if (_foundFiles.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 20, vertical: 24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Column(
                children: [
                  Text('📭', style: TextStyle(fontSize: 36)),
                  SizedBox(height: 10),
                  Text(
                    '자동으로 찾지 못했어요.\n위에서 직접 파일을 선택해 주세요.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      color: AppTheme.textSecondary,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            )
          else
            ..._foundFiles
                .where((f) => f.filePath != _selectedBackup?.filePath)
                .map((info) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _buildBackupCard(info),
                    )),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _sectionHeader(String emoji, String title) {
    return Row(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 20)),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppTheme.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildBackupCard(BackupInfo info, {bool highlight = false}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: highlight
              ? AppTheme.primaryColor
              : const Color(0xFFE0E0E0),
          width: highlight ? 2.5 : 1.5,
        ),
        boxShadow: highlight
            ? [
                BoxShadow(
                  color: AppTheme.primaryColor.withOpacity(0.10),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 파일명 + 크기
            Row(
              children: [
                const Text('💾', style: TextStyle(fontSize: 22)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    info.fileName,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F0F0),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(info.fileSizeStr,
                      style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary)),
                ),
              ],
            ),

            const SizedBox(height: 14),
            const Divider(height: 1, color: Color(0xFFF0F0F0)),
            const SizedBox(height: 14),

            // 카테고리 / 메모 수
            Row(
              children: [
                _chip('📦 ${info.categoryCount}개 카테고리'),
                const SizedBox(width: 8),
                _chip('📝 ${info.memoCount}개 메모'),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '🕐 ${info.dateStr}',
              style: const TextStyle(
                  fontSize: 13, color: AppTheme.textSecondary),
            ),

            const SizedBox(height: 16),

            // 복원 버튼
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => _startRestore(info),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: const Text(
                  '이 파일로 복원하기',
                  style: TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F4FF),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppTheme.primaryColor),
      ),
    );
  }
}
